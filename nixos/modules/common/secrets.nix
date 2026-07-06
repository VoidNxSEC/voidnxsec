{ ... }:
# sops-nix: encrypted secrets management
# Secrets encrypted with age, decrypted at boot using SSH host key
# Safe for git version control — no plaintext secrets ever committed
{
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    # Use SSH host key (persisted) to derive age decryption key
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
    age.keyFile = "/persist/etc/age/key.txt";
    age.generateKey = true;

    secrets = {
      # User password hash — used by users.nix
      "user-password" = {
        neededForUsers = true;
      };
      # Root password hash
      "root-password" = {
        neededForUsers = true;
      };
      # Note: SSH host key is NOT a sops secret.
      # services.openssh.hostKeys (in server/services.nix) generates and manages
      # /persist/etc/ssh/ssh_host_ed25519_key. sops uses that EXISTING key as input
      # to derive the age decryption key — no circular dependency.
    };
  };
}
