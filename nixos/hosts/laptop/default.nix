{ inputs, ... }:
{
  imports = [
    ./hardware.nix
    ./partitions.nix
    ./profile.nix
    ../../modules/common/boot.nix
    ../../modules/common/security.nix
    ../../modules/common/impermanence.nix
    ../../modules/common/secrets.nix
    ../../modules/common/networking.nix
    ../../modules/common/users.nix
    ../../modules/laptop/suspend.nix
    ../../modules/laptop/networking-wifi.nix
  ];

  networking.hostName = "voidnx-laptop";
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.11";
}
