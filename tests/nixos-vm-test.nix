# tests/nixos-vm-test.nix — NixOS VM simulation of the bootstrap queue
#
# Boots a NixOS VM (QEMU, built by the Nix test driver) through the REAL
# bootloader (systemd-boot via OVMF) and asserts the outcome of every
# adapter phase:
#
#   base-install  → the VM itself is the installed system (built from the
#                   repo's common modules + flake)
#   chroot-setup  → ssh host key present (sops-nix readiness)
#   bootloader    → boot entries exist, bootctl sees systemd-boot
#   disk-setup    → LUKS2/Argon2id roundtrip on an extra virtual disk
#   mount         → open + mount + write + unmount the encrypted fs
#   preflight     → security params from common/boot.nix live in /proc/cmdline
#
# Notes:
# - common/boot.nix enables lanzaboote by default; the VM overrides it to
#   false (Phase 1 semantics, as hosts do) because Secure Boot keys are
#   enrolled post-boot by the adapter's bootloader phase.
# - module.sig_enforce=1 and iommu=force are dropped in the VM: the test
#   kernel ships unsigned modules (virtio_blk) and QEMU has no IOMMU.
#   The security-assertions CI job enforces them on the real configs.
# - The disko layouts are validated separately by the eval job; the LUKS
#   roundtrip here uses the exact cryptsetup args of partitions.nix.
#
# Wired into the flake as checks.x86_64-linux.vm-bootstrap.
{ inputs, pkgs, ... }:

let
  # Same hardening as common/boot.nix minus the two VM-hostile params.
  # NOTE: apparmor=1 and lsm=... come from security.apparmor.enable +
  # security.lsm (security/default.nix); mkForce on the list would wipe them
  # — keep them here explicitly (lsm value evaluated from voidnx-laptop).
  vmKernelParams = [
    "init_on_alloc=1"
    "init_on_free=1"
    "page_poison=1"
    "slab_nomerge"
    "pti=on"
    "vsyscall=none"
    "mitigations=auto"
    "lockdown=confidentiality"
    "randomize_kstack_offset=on"
    "apparmor=1"
    "lsm=landlock,yama,apparmor,bpf"
  ];
in
{
  name = "voidnxsec-bootstrap-vm";
  meta.timeout = 2400; # TCG (no KVM on GH runners) is slow — 40min ceiling

  nodes.machine = { config, lib, ... }: {
    imports = [
      inputs.lanzaboote.nixosModules.lanzaboote
      ../nixos/modules/common/boot.nix
      ../nixos/modules/common/security.nix
      ../nixos/modules/common/networking.nix
    ];

    # ── Phase 1 semantics (same as kernelcore before Secure Boot) ──
    boot.lanzaboote.enable = false;
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
    boot.kernelParams = lib.mkForce vmKernelParams;

    networking.hostName = "voidnx-test";
    time.timeZone = "America/Bahia";

    # ssh host keys — the chroot-setup phase expectation (sops-nix readiness)
    services.openssh.enable = true;

    environment.systemPackages = with pkgs; [
      cryptsetup
      jq
      file
    ];

    virtualisation = {
      useBootLoader = true; # boot through the real firmware + systemd-boot
      useEFIBoot = true;
      diskSize = 4096;
      emptyDiskImages = [ 512 ]; # /dev/vdb for the LUKS roundtrip
      memorySize = 2048;
    };
  };

  testScript = ''
    start_all()

    with subtest("base-install — system booted from the flake closure"):
        machine.wait_for_unit("multi-user.target", timeout=600)
        machine.succeed("test -L /run/current-system")
        machine.succeed("hostname | grep -q voidnx-test")
        machine.succeed("nix-store --version | grep -q nix")

    with subtest("preflight — hardening params applied at boot"):
        machine.succeed("grep -q pti=on /proc/cmdline")
        machine.succeed("grep -q init_on_alloc=1 /proc/cmdline")
        machine.succeed("grep -q vsyscall=none /proc/cmdline")
        machine.succeed("grep -q slab_nomerge /proc/cmdline")
        machine.succeed("grep -q 'lockdown=confidentiality' /proc/cmdline")
        machine.succeed("cat /proc/sys/kernel/kptr_restrict | grep -q '^2$'")
        machine.succeed("cat /proc/sys/fs/suid_dumpable | grep -q '^0$'")
        machine.succeed("cat /proc/sys/kernel/yama/ptrace_scope | grep -q '^2$'")
        diag = machine.execute(
            "echo '— /sys/kernel:'; ls /sys/kernel; "
            "echo '— securityfs in /proc/filesystems:'; grep -i securityfs /proc/filesystems; "
            "echo '— mounts:'; mount | grep -i security; "
            "echo '— dmesg apparmor:'; dmesg | grep -i apparmor | tail -5"
        )
        print(diag[1])
        machine.succeed("test -d /sys/kernel/security/apparmor")

    with subtest("chroot-setup — sops-nix host key present"):
        machine.succeed("test -f /etc/ssh/ssh_host_ed25519_key")

    with subtest("bootloader — entries installed and bootctl works"):
        machine.succeed("test -d /boot/loader/entries")
        machine.succeed("bootctl status | grep -qi systemd-boot")

    with subtest("disk-setup — LUKS2/Argon2id roundtrip (partitions.nix args)"):
        machine.succeed("printf '%s' voidnx-test-pass-1234 > /tmp/pass")
        machine.succeed(
            "cryptsetup luksFormat --type luks2 --pbkdf argon2id "
            "--iter-time 5000 --batch-mode --key-file /tmp/pass /dev/vdb"
        )
        machine.succeed("cryptsetup luksDump /dev/vdb | grep -q 'Version:[[:space:]]*2'")
        machine.succeed("cryptsetup luksDump /dev/vdb | grep -qi argon2id")
        machine.succeed("cryptsetup open --key-file /tmp/pass /dev/vdb cryptroot-test")

    with subtest("mount — encrypted fs usable end-to-end"):
        machine.succeed("mkfs.ext4 -q /dev/mapper/cryptroot-test")
        machine.succeed("mkdir -p /mnt/void-test")
        machine.succeed("mount /dev/mapper/cryptroot-test /mnt/void-test")
        machine.succeed("echo voidnx > /mnt/void-test/marker")
        machine.succeed("grep -q voidnx /mnt/void-test/marker")
        machine.succeed("umount /mnt/void-test")
        machine.succeed("cryptsetup close cryptroot-test")
        machine.succeed("rm -f /tmp/pass")

    with subtest("finalize — ledger tooling available"):
        machine.succeed("jq --version | grep -q jq")
  '';
}
