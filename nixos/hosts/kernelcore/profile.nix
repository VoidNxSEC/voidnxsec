{ lib, pkgs, config, ... }:
# kernelcore — laptop workstation profile
# Intel Core (VMD) + NVIDIA RTX 3050 6GB, NVMe ~477GB
# Timezone: America/Bahia | Locale: en_US.UTF-8 | Keyboard: br-abnt2
#
# NVIDIA constraints applied here (override common/boot.nix):
#   - linuxPackages_latest instead of linuxPackages_hardened (NVIDIA proprietary incompatible)
#   - lockdown=integrity instead of lockdown=confidentiality (/dev/mem access required)
#   - module.sig_enforce=1 REMOVED (NVIDIA modules are unsigned)
#   - bluetooth NOT blacklisted (laptop needs it)
{
  # ── Boot overrides (NVIDIA safety) ─────────────────────────────────────────

  # boot.nix already uses linuxPackages_latest — no override needed for NVIDIA
  # (linuxPackages_hardened was removed from nixpkgs-unstable)

  # Override common/boot.nix kernel params: drop lockdown=confidentiality + sig_enforce
  # and add NVIDIA-specific params. Keep all other hardening params.
  boot.kernelParams = lib.mkForce [
    "init_on_alloc=1"
    "init_on_free=1"
    "page_poison=1"
    "slab_nomerge"
    "pti=on"
    "vsyscall=none"
    "mitigations=auto"
    "randomize_kstack_offset=on"
    "iommu=force"
    "iommu.passthrough=0"
    "iommu.strict=1"
    # lockdown=integrity: allows /dev/mem (NVIDIA needs it), blocks kexec/unsigned modules
    "lockdown=integrity"
    # NVIDIA power management
    "nvidia.NVreg_DynamicPowerManagement=0x02"
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
    "nvidia.NVreg_EnableGpuFirmware=1"
  ];

  # Lanzaboote + Secure Boot (Phase 2 — active from bootstrap)
  # boot.nix sets pkiBundle = "/persist/etc/secureboot"; override to /etc/secureboot
  # because impermanence is Phase 4 (root is not tmpfs yet).
  # Post-install Secure Boot enrollment (run once as root after first boot):
  #   sbctl create-keys
  #   sbctl enroll-keys --microsoft
  #   reboot → UEFI → enable Secure Boot
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";
  # systemd-boot.enable is set to false automatically by the lanzaboote module

  # Re-enable bluetooth (boot.nix blacklists it for server; laptop needs it)
  boot.blacklistedKernelModules = lib.mkForce [
    "dccp" "sctp" "rds" "tipc" "n-hdlc" "ax25" "netrom"
    "x25" "rose" "decnet" "econet" "af_802154" "ipx" "appletalk"
    "psnap" "p8023" "p8022" "can" "atm"
    "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs" "udf"
    # bluetooth + btusb intentionally NOT listed — laptop needs BT
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  # ── Swap: ZRAM only (no disk swap — SSD longevity) ─────────────────────────

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # ── sops: non-impermanence paths (Phase 4 will move to /persist) ───────────

  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/var/lib/sops-nix/key.txt";
    age.generateKey = true;
    secrets = {
      "user-password".neededForUsers = true;
      "root-password".neededForUsers = true;
    };
  };

  # ── Users ───────────────────────────────────────────────────────────────────

  users.mutableUsers = false;

  users.users.kernelcore = {
    isNormalUser = true;
    description = "kernel";
    shell = pkgs.zsh;
    extraGroups = [
      "wheel" "audio" "video" "nvidia" "docker" "render"
      "libvirtd" "kvm" "networkmanager" "input" "plugdev" "mcp-shared"
    ];
    hashedPasswordFile = config.sops.secrets."user-password".path;
    openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBG5StF4nUzkEsUei88BstktP/Q/g8BvlHeWnEDD+ii/jB7Fs4v4imG05tJU/jC8/ax2FFRSwoBRt7tH6RDp4Dys= user@iphone"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBE2jQWzD7N9sMWW+UKBNuxzS5v3Dt5g6UbZ/kd49b7XJugBLma8152DogVrblUxhPqfQfcCVrMHNHFlIkXAB9w= voidnxlabs"
    ];
    createHome = true;
    home = "/home/kernelcore";
  };

  users.users.root.hashedPasswordFile = config.sops.secrets."root-password".path;

  # ── Tailscale ───────────────────────────────────────────────────────────────

  services.tailscale.extraUpFlags = [ "--hostname=kernelcore" ];

  # ── Nix: binary cache client ────────────────────────────────────────────────
  # Phase 3: uncomment and fill in desktop Tailscale IP + public key

  nix.settings = {
    substituters = [
      "https://cache.nixos.org"
      # "http://<desktop-tailscale-ip>:5000"   # TODO Phase 3: add desktop cache
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      # "desktop:<pub-key>"                    # TODO Phase 3: run offload-generate-cache-keys on desktop
    ];
    experimental-features = [ "nix-command" "flakes" ];
  };

  # Remote builds on desktop (enable in Phase 3):
  # nix.distributedBuilds = true;
  # nix.buildMachines = [{
  #   hostName = "<desktop-tailscale-hostname>";
  #   systems  = [ "x86_64-linux" ];
  #   maxJobs  = 8;
  #   speedFactor = 4;
  #   supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
  #   sshUser  = "nix-builder";
  #   sshKey   = "/etc/nix/build-key";
  # }];

  # NFS mounts from desktop (enable in Phase 3):
  # fileSystems."/mnt/desktop-models" = {
  #   device = "<desktop-tailscale-hostname>:/data/models";
  #   fsType = "nfs";
  #   options = [ "_netdev" "ro" "soft" "timeo=30" ];
  # };

  # ── Base packages ───────────────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    git zsh curl wget htop btop ripgrep fd bat eza
    cryptsetup tpm2-tools sbctl
    jq age sops tailscale
    acpi powertop
  ];

  # ── Zsh ─────────────────────────────────────────────────────────────────────

  programs.zsh.enable = true;

  # ── Suspend/hibernate (laptop lid) ─────────────────────────────────────────

  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  services.logind.settings.Login = {
    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend";
    IdleAction = "lock";
    IdleActionSec = "10min";
    HibernateDelaySec = "60min";
    HandlePowerKey = "hibernate";
  };

  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "60min";
    SuspendState = "mem";
  };
}
