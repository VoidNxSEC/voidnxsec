{ pkgs, ... }:
# Server profile: headless, minimal attack surface
{
  # No GUI, no desktop
  services.xserver.enable = false;

  # Minimal package set — only what a server needs
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    jq
    age
    sops
    lynis
    cryptsetup
    lvm2
    e2fsprogs
    dosfstools
    util-linux
    tpm2-tools
    sbctl
  ];

  # No sound
  hardware.pulseaudio.enable = false;

  # Disable unnecessary services
  services.avahi.enable = false;
  services.printing.enable = false;
}
