{ config, lib, pkgs, ... }:
# Desktop offload server — Nix binary cache + remote builds + optional NFS
# Ported from /etc/nixos/modules/services/offload-server.nix
# Enable on the desktop host (1TB) to feed the laptop's Nix store.
#
# Setup after deploy:
#   offload-generate-cache-keys          # generates /var/cache-priv-key.pem
#   offload-server-status                # verify everything is up
#   # Copy public key and add to laptop's nix.settings.trusted-public-keys
with lib;
{
  options.services.offload-server = {
    enable = mkEnableOption "Nix binary cache + remote build server";

    cachePort = mkOption {
      type = types.port;
      default = 5000;
      description = "Port for nix-serve binary cache";
    };

    builderUser = mkOption {
      type = types.str;
      default = "nix-builder";
      description = "System user for remote SSH builds";
    };

    cacheKeyPath = mkOption {
      type = types.str;
      default = "/var/cache-priv-key.pem";
      description = "Path to nix-serve signing private key";
    };

    laptopSshKey = mkOption {
      type = types.str;
      default = "";
      description = "SSH public key of the laptop's nix-builder identity";
    };

    enableNFS = mkOption {
      type = types.bool;
      default = false;
      description = "Export /nix/store + /data read-only via NFS (for model/dataset sharing)";
    };

    nfsAllowedCIDR = mkOption {
      type = types.str;
      default = "100.64.0.0/10";
      description = "CIDR allowed to mount NFS exports (default: Tailscale range)";
    };

    dataExports = mkOption {
      type = types.listOf types.str;
      default = [ "/data/models" "/data/datasets" ];
      description = "Extra directories to export via NFS";
    };
  };

  config = mkIf config.services.offload-server.enable {

    # ── nix-serve binary cache ────────────────────────────────────────────────

    services.nix-serve = {
      enable = true;
      port = config.services.offload-server.cachePort;
      bindAddress = "0.0.0.0";
      secretKeyFile = config.services.offload-server.cacheKeyPath;
    };

    # ── Remote builder user ───────────────────────────────────────────────────

    users.users.${config.services.offload-server.builderUser} = {
      isSystemUser = true;
      group = config.services.offload-server.builderUser;
      home = "/var/lib/${config.services.offload-server.builderUser}";
      createHome = true;
      shell = pkgs.bash;
      description = "Nix remote build user";
      openssh.authorizedKeys.keys =
        optional (config.services.offload-server.laptopSshKey != "")
          config.services.offload-server.laptopSshKey;
    };

    users.groups.${config.services.offload-server.builderUser} = { };

    nix.settings.trusted-users = [ config.services.offload-server.builderUser ];
    nix.settings.keep-outputs = true;
    nix.settings.keep-derivations = true;

    # ── NFS exports (optional) ────────────────────────────────────────────────

    services.nfs.server = mkIf config.services.offload-server.enableNFS {
      enable = true;
      exports =
        let
          opts = "${config.services.offload-server.nfsAllowedCIDR}(ro,sync,no_subtree_check,no_root_squash)";
          nixLine = "/nix/store ${opts}";
          dataLines = concatMapStrings (p: "\n${p} ${opts}") config.services.offload-server.dataExports;
        in
        "${nixLine}${dataLines}\n";
    };

    services.rpcbind.enable = mkIf config.services.offload-server.enableNFS true;

    systemd.tmpfiles.rules =
      [ "d /var/lib/${config.services.offload-server.builderUser}/.ssh 0700 ${config.services.offload-server.builderUser} ${config.services.offload-server.builderUser} -" ]
      ++ map (p: "d ${p} 0755 root root -") config.services.offload-server.dataExports;

    # ── Firewall ──────────────────────────────────────────────────────────────

    networking.firewall.allowedTCPPorts =
      [ 22 config.services.offload-server.cachePort ]
      ++ optionals config.services.offload-server.enableNFS [ 2049 111 ];

    networking.firewall.allowedUDPPorts =
      optionals config.services.offload-server.enableNFS [ 2049 111 ];

    # ── Management scripts ────────────────────────────────────────────────────

    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "offload-generate-cache-keys" ''
        PRIV="${config.services.offload-server.cacheKeyPath}"
        PUB="''${PRIV/priv/pub}"
        if [ -f "$PRIV" ]; then
          echo "Keys already exist at $PRIV / $PUB"
          echo "Delete them manually to regenerate."
          exit 1
        fi
        sudo nix-store --generate-binary-cache-key cache.$(hostname) "$PRIV" "$PUB"
        echo "Private: $PRIV"
        echo "Public key (add to laptop trusted-public-keys):"
        cat "$PUB"
      '')

      (writeShellScriptBin "offload-server-status" ''
        echo "=== Offload Server Status ==="
        systemctl is-active nix-serve   && echo "nix-serve: UP (port ${toString config.services.offload-server.cachePort})" || echo "nix-serve: DOWN"
        systemctl is-active sshd        && echo "sshd: UP" || echo "sshd: DOWN"
        ${optionalString config.services.offload-server.enableNFS
          "systemctl is-active nfs-server && echo 'nfs-server: UP' || echo 'nfs-server: DOWN'"}
        echo ""
        echo "Nix store: $(du -sh /nix/store 2>/dev/null | cut -f1)"
        echo "Disk free: $(df -h /nix/store | awk 'NR==2{print $4}')"
        echo ""
        if curl -sf http://localhost:${toString config.services.offload-server.cachePort}/nix-cache-info >/dev/null; then
          echo "Cache: accessible"
        else
          echo "Cache: NOT accessible — check nix-serve and key"
        fi
      '')
    ];

    # ── Boot activation ───────────────────────────────────────────────────────

    system.activationScripts.offload-server-setup = ''
      if [ ! -f "${config.services.offload-server.cacheKeyPath}" ]; then
        echo "WARNING: cache signing key missing — run: offload-generate-cache-keys"
      fi
    '';
  };
}
