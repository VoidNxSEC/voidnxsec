{ ... }:
# Laptop WiFi: NetworkManager + iwd backend + DNS over TLS
{
  networking.networkmanager = {
    enable = true;
    wifi = {
      backend = "iwd";
      macAddress = "random";        # MAC randomization per network
      powersave = true;
    };
    dns = "systemd-resolved";
    # Disable insecure connection types
    connectionConfig = {
      "connection.auth-retries" = 3;
    };
  };

  networking.wireless.iwd = {
    enable = true;
    settings = {
      General = {
        AddressRandomization = "network"; # stable per-network random MAC
        EnableNetworkConfiguration = false; # let NM handle it
      };
      Network = {
        EnableIPv6 = true;
        RoutePriorityOffset = 300;
      };
    };
  };

  # Firewall: more open than server (allow mDNS for local discovery)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
