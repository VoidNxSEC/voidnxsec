{ ... }:
# Root-as-tmpfs impermanence setup
# Defeats malware persistence: root is wiped on every boot
# Only /persist (on LUKS2 encrypted partition) survives reboots
# Reference: nix-community/impermanence + Anduril defense-grade approach
{
  # /persist must be mounted before impermanence binds directories
  fileSystems."/persist".neededForBoot = true;

  # Root filesystem is RAM (tmpfs) — wiped on shutdown
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };

  # /tmp with security mount flags (CIS Benchmark mandatory)
  fileSystems."/tmp" = {
    device = "none";
    fsType = "tmpfs";
    options = [ "nodev" "nosuid" "noexec" "size=1G" "mode=1777" ];
  };

  # /var/tmp bound to /tmp (CIS recommendation)
  fileSystems."/var/tmp" = {
    device = "/tmp";
    fsType = "none";
    options = [ "bind" "nodev" "nosuid" "noexec" ];
  };

  # Declare what persists across reboots
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/etc/nixos"              # NixOS configuration
      "/var/log"                # System logs (audit, journal)
      "/var/lib/systemd"        # systemd state (timers, credentials)
      "/var/lib/nixos"          # NixOS state
      "/var/lib/fail2ban"       # fail2ban state
      "/var/lib/auditd"         # auditd state
      "/etc/secureboot"         # Lanzaboote signing keys
      "/etc/ssh"                # SSH host keys (needed for sops-nix decrypt)
      "/var/lib/aide"           # AIDE integrity database (server monitoring)
    ];
    files = [
      "/etc/machine-id"         # stable machine identity
      "/etc/adjtime"            # time adjustment state
    ];
    users.nx = {
      directories = [
        "Documents"
        "Downloads"
        ".config"
        ".local"
        ".ssh"
      ];
    };
  };
}
