{ pkgs, ... }:
# Laptop profile: FDE + TPM2 + suspend/resume
{
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
    tpm2-tools
    sbctl
    # Laptop essentials
    brightnessctl
    acpi
    powertop
  ];

  # Hibernate support (requires swap >= RAM size)
  boot.kernelParams = [ "resume_offset=0" ]; # update offset after install

  # Screen lock on suspend
  services.logind = {
    lidSwitch = "suspend-then-hibernate";
    lidSwitchExternalPower = "lock";
    extraConfig = ''
      IdleAction=suspend-then-hibernate
      IdleActionSec=10min
      HibernateDelaySec=60min
    '';
  };

  # NetworkManager for wifi (iwd backend — faster, lighter)
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
  };
  networking.wireless.iwd.enable = true;
}
