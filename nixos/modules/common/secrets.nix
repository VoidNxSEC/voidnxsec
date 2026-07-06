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
      # SSH host key (persisted via impermanence)
      "ssh-host-ed25519-key" = {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        mode = "0600";
        owner = "root";
        group = "root";
      };
    };
  };
}
