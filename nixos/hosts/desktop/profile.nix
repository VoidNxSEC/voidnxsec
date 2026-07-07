{ lib, pkgs, config, ... }:
# desktop — offload server profile (1TB disk)
# Feeds the laptop Nix store cache, remote builds, and AI model NFS share
{
  # ── Boot ────────────────────────────────────────────────────────────────────

  # No NVIDIA on desktop — can use hardened kernel from boot.nix
  # Override bluetooth blacklist to enable if desktop has BT
  boot.blacklistedKernelModules = lib.mkForce [
    "dccp" "sctp" "rds" "tipc" "n-hdlc" "ax25" "netrom"
    "x25" "rose" "decnet" "econet" "af_802154" "ipx" "appletalk"
    "psnap" "p8023" "p8022" "can" "atm"
    "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs" "udf"
    "bluetooth" "btusb"   # desktop: no BT needed (override if required)
  ];

  # ── sops paths (non-impermanence system) ────────────────────────────────────

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

  users.users.nx = {
    isNormalUser = true;
    description = "VoidNx user";
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPasswordFile = config.sops.secrets."user-password".path;
    openssh.authorizedKeys.keys = [
      # TODO: add desktop SSH public keys here
    ];
    createHome = true;
    home = "/home/nx";
    shell = pkgs.bash;
  };

  users.users.root.hashedPasswordFile = config.sops.secrets."root-password".path;

  # ── Tailscale ───────────────────────────────────────────────────────────────

  services.tailscale.extraUpFlags = [ "--hostname=desktop" ];

  # ── Offload server (Nix binary cache + NFS) ─────────────────────────────────
  # The laptop configures its nix.settings.substituters to point here after setup.

  services.offload-server = {
    enable = true;
    cachePort = 5000;
    builderUser = "nix-builder";
    cacheKeyPath = "/var/cache-priv-key.pem";
    enableNFS = true;
    nfsAllowedCIDR = "100.64.0.0/10";   # Tailscale IP range
    dataExports = [
      "/data/models"
      "/data/datasets"
      "/data/containers"
    ];
    # TODO: set laptop SSH public key after generating on kernelcore:
    #   ssh-keygen -t ed25519 -f /etc/nix/build-key -N ""
    #   cat /etc/nix/build-key.pub
    laptopSshKey = "";
  };

  # ── SSH server ───────────────────────────────────────────────────────────────

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    hostKeys = [{
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }];
  };

  # ── Nix ─────────────────────────────────────────────────────────────────────

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    keep-outputs = true;
    keep-derivations = true;
  };

  # ── Base packages ────────────────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    git curl wget htop jq age sops tailscale
    nfs-utils nmap openssl
  ];
}
