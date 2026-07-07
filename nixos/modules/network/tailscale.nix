{ pkgs, ... }:
# Tailscale mesh VPN — minimal base module
# Per-host options (hostname, authKeyFile, subnet router) set in host profile.nix
{
  services.tailscale = {
    enable = true;
    port = 41641;
    interfaceName = "tailscale0";
  };

  # Tailscaled systemd hardening
  systemd.services.tailscaled = {
    after = [ "network-pre.target" ];
    wants = [ "network-pre.target" ];
    serviceConfig = {
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/tailscale" ];
      MemoryMax = "512M";
      TasksMax = 256;
      Restart = "on-failure";
      RestartSec = 30;
      StateDirectory = "tailscale";
    };
  };

  networking.firewall = {
    allowedUDPPorts = [ 41641 ];
    trustedInterfaces = [ "tailscale0" ];
    # Required for subnet routing/exit node; safe default for mesh VPN
    checkReversePath = "loose";
  };

  environment.systemPackages = with pkgs; [ tailscale ];

  environment.shellAliases = {
    ts-status = "tailscale status";
    ts-ip     = "tailscale ip -4";
    ts-peers  = "tailscale status --peers";
    ts-up     = "sudo systemctl start tailscaled && sudo tailscale up";
    ts-logs   = "journalctl -u tailscaled -f";
  };
}
