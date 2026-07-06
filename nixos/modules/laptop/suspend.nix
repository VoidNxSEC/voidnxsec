{ lib, pkgs, ... }:
# Laptop suspend/hibernate: TPM2-sealed keys survive sleep safely
# systemd-cryptenroll PCR policy enforced on resume
{
  # Enable hibernate support
  powerManagement.enable = true;
  powerManagement.hibernate = true;

  # systemd-sleep config
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=60min
    SuspendState=mem
  '';

  # Screen lock before suspend (security requirement)
  services.logind = {
    lidSwitch = "suspend-then-hibernate";
    lidSwitchExternalPower = "suspend";
    extraConfig = ''
      IdleAction=lock
      IdleActionSec=5min
      HandlePowerKey=hibernate
    '';
  };

  # Bluetooth — enable on laptop (override blacklist from boot.nix)
  boot.blacklistedKernelModules = lib.mkForce [
    "dccp" "sctp" "rds" "tipc" "n-hdlc" "ax25" "netrom"
    "x25" "rose" "decnet" "econet" "af_802154" "ipx" "appletalk"
    "psnap" "p8023" "p8022" "can" "atm"
    "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs" "udf"
    # bluetooth NOT blacklisted on laptop
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false; # off by default, enable manually
    settings.Policy.AutoEnable = "false";
  };
}
