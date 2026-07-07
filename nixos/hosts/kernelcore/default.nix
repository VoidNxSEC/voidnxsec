{ inputs, ... }:
# kernelcore — laptop host (Intel + RTX 3050, NVMe ~477GB, LUKS1)
# Phase status:
#   Phase 1 (current): real hardware, voidnxsec hardening, NVIDIA, Tailscale
#   Phase 2 (next):    Lanzaboote + Secure Boot
#   Phase 3:           Desktop offload cache + NFS + remote builds
#   Phase 4:           disko + LUKS2/Argon2id + impermanence (requires reinstall)
{
  imports = [
    ./hardware.nix
    ./profile.nix                              # NVIDIA overrides, users, sops, tailscale
    ../../modules/common/boot.nix             # kernel hardening (overridden for NVIDIA in profile)
    ../../modules/common/security.nix         # AppArmor, fail2ban, sysctl CIS/ANSSI
    ../../modules/common/networking.nix       # nftables, DoT DNS
    ../../modules/desktop/nvidia.nix          # NVIDIA RTX 3050 + CUDA + container toolkit
    ../../modules/network/tailscale.nix       # Tailscale mesh VPN
    # NOT imported (Phase 4):
    #   ../../modules/common/impermanence.nix
    #   ./partitions.nix                      # disko layout (LUKS2 migration)
    # NOT imported (different user — kernelcore, not nx):
    #   ../../modules/common/users.nix
    # secrets.nix replaced by inline sops config in profile.nix
  ];

  networking.hostName = "kernelcore";
  time.timeZone = "America/Bahia";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "br-abnt2";

  system.stateVersion = "25.11";
}
