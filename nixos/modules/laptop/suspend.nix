{ lib, pkgs, ... }:
# Laptop suspend/hibernate: TPM2-sealed keys survive sleep safely
# systemd-cryptenroll PCR policy enforced on resume
{
  powerManagement.enable = true;

  # systemd-sleep config (logind triggers are in profile.nix)
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=60min
    SuspendState=mem
  '';

  # Bluetooth — enable on laptop (override blacklist from common boot.nix)
  boot.blacklistedKernelModules = lib.mkForce [
    "dccp" "sctp" "rds" "tipc" "n-hdlc" "ax25" "netrom"
    "x25" "rose" "decnet" "econet" "af_802154" "ipx" "appletalk"
    "psnap" "p8023" "p8022" "can" "atm"
    "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs" "udf"
    # bluetooth and btusb intentionally NOT blacklisted on laptop
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
    settings.Policy.AutoEnable = "false";
  };

  # Persist Bluetooth pairings and NetworkManager connections across reboots
  environment.persistence."/persist" = {
    directories = [
      "/var/lib/bluetooth"
      "/var/lib/NetworkManager"
    ];
  };
}
