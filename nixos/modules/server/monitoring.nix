{ pkgs, ... }:
# Server monitoring: systemd-journal + optional prometheus node exporter
{
  # Persistent journal (survives reboot via /persist/var/log)
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    MaxFileSec=1month
    ForwardToSyslog=no
    Compress=yes
  '';

  # AIDE: filesystem integrity monitoring (Lynis recommendation)
  # Checks for unauthorized file modifications
  services.aide = {
    enable = true;
    settings = {
      database_in = "file:/var/lib/aide/aide.db";
      database_out = "file:/var/lib/aide/aide.db.new";
    };
  };

  environment.systemPackages = with pkgs; [
    aide
    lynis
    nmap    # network audit
    openssl # cert validation
  ];
}
