{ ... }:
# Laptop WiFi: NetworkManager + iwd backend + MAC randomization
{
  networking.networkmanager = {
    enable = true;
    wifi = {
      backend = "iwd";
      macAddress = "random";
      powersave = true;
    };
    dns = "systemd-resolved";
  };

  networking.wireless.iwd = {
    enable = true;
    settings = {
      General = {
        AddressRandomization = "network";
        EnableNetworkConfiguration = false; # let NM handle it
      };
      Network = {
        EnableIPv6 = true;
        RoutePriorityOffset = 300;
      };
    };
  };

  # Firewall: allow mDNS for local discovery (stricter than server)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
