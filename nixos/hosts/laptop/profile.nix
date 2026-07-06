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
    brightnessctl
    acpi
    powertop
  ];

  # resume_offset: update after install with:
  #   filefrag -v /persist/.swapfile | awk 'NR==4{print $4}'
  # (or run enroll-tpm.sh which prints the correct value)
  boot.kernelParams = [ "resume_offset=0" ];

  # All lid/power/idle actions in one place (suspend.nix owns systemd.sleep)
  services.logind = {
    lidSwitch = "suspend-then-hibernate";
    lidSwitchExternalPower = "suspend";
    extraConfig = ''
      IdleAction=lock
      IdleActionSec=10min
      HibernateDelaySec=60min
      HandlePowerKey=hibernate
    '';
  };
}
