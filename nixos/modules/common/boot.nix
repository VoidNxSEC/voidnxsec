{ lib, pkgs, ... }:
# Boot hardening: Lanzaboote (Secure Boot) + TPM2 + hardened kernel params
# References: NSA/CISA, CIS Level 2, NixOS Lanzaboote docs (2026)
{
  # Lanzaboote replaces systemd-boot for Secure Boot support
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/persist/etc/secureboot";
  };
  # lanzaboote requires systemd-boot disabled explicitly
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  # efiSysMountPoint is set per-host in hardware.nix:
  #   server: "/boot/efi" (separate /boot partition)
  #   laptop: "/boot"     (EFI partition is /boot directly)

  # systemd initrd required for systemd-cryptenroll (TPM2 unlock)
  boot.initrd.systemd.enable = true;

  # Kernel hardening params
  # Inherited from voidnx.sh (production-tested) + new 2026 additions
  boot.kernelParams = [
    # --- Memory safety (from voidnx.sh) ---
    "init_on_alloc=1"           # zero memory on allocation
    "init_on_free=1"            # zero memory on free
    "page_poison=1"             # poison freed pages
    "slab_nomerge"              # prevent slab cache merging

    # --- Spectre/Meltdown mitigations (from voidnx.sh) ---
    "pti=on"                    # Page Table Isolation
    "vsyscall=none"             # disable vsyscall (legacy attack surface)
    "mitigations=auto"

    # --- Kernel lockdown (new 2026) ---
    "lockdown=confidentiality"  # blocks /dev/mem, kexec, unsigned modules
    "module.sig_enforce=1"      # require signed kernel modules

    # --- ASLR / stack randomization ---
    "randomize_kstack_offset=on"

    # --- DMA protection ---
    "iommu=force"               # force IOMMU — blocks DMA attacks (PCILeech, etc.)
    "iommu.passthrough=0"
    "iommu.strict=1"
  ];

  # Kernel sysctl hardening (see also security.nix for full list)
  boot.kernel.sysctl = {
    # Disable kexec — prevents loading alternative kernels at runtime
    "kernel.kexec_load_disabled" = 1;
    # Restrict /proc/kallsyms
    "kernel.kptr_restrict" = 2;
    # Restrict dmesg to root
    "kernel.dmesg_restrict" = 1;
  };

  # Use latest hardened kernel
  boot.kernelPackages = pkgs.linuxPackages_hardened;

  # Disable unnecessary kernel features
  boot.blacklistedKernelModules = [
    "dccp"       # obscure protocol, attack surface
    "sctp"       # obscure protocol
    "rds"        # known vulnerabilities
    "tipc"       # unused in most deployments
    "n-hdlc"
    "ax25"
    "netrom"
    "x25"
    "rose"
    "decnet"
    "econet"
    "af_802154"
    "ipx"
    "appletalk"
    "psnap"
    "p8023"
    "p8022"
    "can"
    "atm"
    "cramfs"     # legacy filesystems
    "freevxfs"
    "jffs2"
    "hfs"
    "hfsplus"
    "squashfs"
    "udf"
    "bluetooth"  # disable if not needed (override in laptop profile)
    "btusb"
  ];
}
