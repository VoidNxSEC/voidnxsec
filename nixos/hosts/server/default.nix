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
    ../../modules/server/services.nix
    ../../modules/server/monitoring.nix
  ];

  networking.hostName = "voidnx-server";
  time.timeZone = "America/Sao_Paulo";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "25.11";
}
