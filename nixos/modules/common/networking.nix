{ ... }:
# Network hardening: nftables firewall + DNS over TLS
# References: ANSSI-BP-028 Intermediary, CIS Benchmark
{
  # Use nftables (modern, replaces iptables)
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    # Drop all incoming by default; allow only what's explicitly opened
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    # Block ICMP flood
    pingLimit = "--limit 1/minute --limit-burst 5";
    # Log dropped packets for audit
    logRefusedConnections = true;
    logRefusedPackets = true;
  };

  # DNS over TLS via systemd-resolved (ANSSI recommendation)
  services.resolved = {
    enable = true;
    dnssec = "true";
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1#cloudflare-dns.com" "9.9.9.9#dns.quad9.net" ];
    extraConfig = ''
      DNSOverTLS=yes
    '';
  };

  # Disable IPv6 router advertisements (already in sysctl but belt-and-suspenders)
  networking.enableIPv6 = true; # keep ipv6 but hardened via sysctl
}
