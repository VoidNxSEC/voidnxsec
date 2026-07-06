{ config, ... }:
# Declarative user management
# Passwords managed via sops-nix — no plaintext in config
{
  users = {
    mutableUsers = false; # declarative only — no passwd/useradd at runtime

    users = {
      root = {
        hashedPasswordFile = config.sops.secrets."root-password".path;
      };

      nx = {
        isNormalUser = true;
        description = "VoidNx user";
        # wheel = sudo, networkmanager for wifi on laptop
        extraGroups = [ "wheel" "audio" "video" "input" "kvm" "networkmanager" ];
        hashedPasswordFile = config.sops.secrets."user-password".path;
        # SSH public key — add yours here
        openssh.authorizedKeys.keys = [
          # "ssh-ed25519 AAAA... user@host"
        ];
        # Persist home via impermanence (declared in impermanence.nix)
        createHome = true;
        home = "/home/nx";
        shell = "/run/current-system/sw/bin/bash";
      };
    };
  };
}
