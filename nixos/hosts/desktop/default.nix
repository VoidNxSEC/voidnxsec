{ inputs, ... }:
# desktop — 1TB offload server host
# Serves the laptop via: Nix binary cache (port 5000) + remote builds + NFS models
#
# BEFORE THIS WORKS: fill in hardware.nix with real UUIDs from:
#   sudo nixos-generate-config --show-hardware-config   (run on desktop)
#   lsblk -f
{
  imports = [
    ./hardware.nix
    ./profile.nix
    ../../modules/common/boot.nix
    ../../modules/common/security.nix
    ../../modules/common/networking.nix
    ../../modules/desktop/offload.nix
    ../../modules/network/tailscale.nix
    # NOT yet:
    #   ../../modules/common/impermanence.nix   (Phase 4)
    #   ./partitions.nix                        (disko — Phase 4)
  ];

  networking.hostName = "desktop";
  time.timeZone = "America/Bahia";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.11";
}
