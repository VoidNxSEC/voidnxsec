{ pkgs, ... }:
# Server monitoring: systemd-journal + AIDE integrity check
{
  # Persistent journal (survives reboot via /persist/var/log)
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    MaxFileSec=1month
    ForwardToSyslog=no
    Compress=yes
  '';

  # AIDE: filesystem integrity monitoring (Lynis recommendation)
  # No NixOS service module — configure via systemd timer manually after install:
  #   aide --init && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  #   aide --check
  systemd.tmpfiles.rules = [
    "d /var/lib/aide 0700 root root -"
  ];

  environment.systemPackages = with pkgs; [
    aide
    lynis
    nmap
    openssl
  ];
}
