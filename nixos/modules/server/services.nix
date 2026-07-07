{ ... }:
# Server-specific services: hardened SSH + firewall rules
{
  # Hardened OpenSSH server
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      # Auth hardening
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      PermitEmptyPasswords = false;

      # Crypto hardening (modern algorithms only)
      Ciphers = [ "chacha20-poly1305@openssh.com" "aes256-gcm@openssh.com" "aes128-gcm@openssh.com" ];
      KexAlgorithms = [ "curve25519-sha256" "curve25519-sha256@libssh.org" ];
      Macs = [ "hmac-sha2-512-etm@openssh.com" "hmac-sha2-256-etm@openssh.com" "umac-128-etm@openssh.com" ];
      # HostKeyAlgorithms is typed as atom (string) in NixOS — comma-separated
      HostKeyAlgorithms = "ssh-ed25519,ssh-ed25519-cert-v01@openssh.com";

      # Session hardening
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
      LoginGraceTime = 30;
      MaxAuthTries = 3;
      MaxSessions = 5;
      MaxStartups = "10:30:60";

      # Disable forwarding (server — not a jump host by default)
      AllowAgentForwarding = false;
      AllowTcpForwarding = false;
      X11Forwarding = false;

      # Logging
      LogLevel = "VERBOSE";
    };
    # Host key type: ed25519 only
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  # Open SSH in firewall
  networking.firewall.allowedTCPPorts = [ 22 ];
}
