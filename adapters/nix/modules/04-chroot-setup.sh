#!/usr/bin/env bash
# modules/04-chroot-setup.sh — Chroot Setup phase
# Nix equivalent of the Void chroot configuration step: prepare everything the
# installed system needs on its very first boot, before leaving the live env.
#
# 1. SSH host key → /mnt/etc/ssh (sops-nix derives the age key from it;
#    without it, secrets cannot decrypt at activation).
# 2. Root's age key (if present in the live env) → /mnt/root/.config/sops.

run_chroot_setup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        run "copy SSH host key (dry)" true
        run "copy age key (dry)" true
        return 0
    fi

    # 1. sops-nix host key
    if [[ -f /etc/ssh/ssh_host_ed25519_key ]]; then
        mkdir -p /mnt/etc/ssh
        install -m 600 /etc/ssh/ssh_host_ed25519_key /mnt/etc/ssh/ssh_host_ed25519_key
        if [[ -f /etc/ssh/ssh_host_ed25519_key.pub ]]; then
            install -m 644 /etc/ssh/ssh_host_ed25519_key.pub /mnt/etc/ssh/ssh_host_ed25519_key.pub
        fi
        log_ok "SSH host key copied to /mnt/etc/ssh (sops-nix will work at first boot)"
    else
        log_warn "no /etc/ssh/ssh_host_ed25519_key in live env — sops-nix will fail at boot"
        log_warn "generate one (ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key) and re-run"
    fi

    # 2. age key for root (unlocks sops from inside the target before login)
    local age_key="${AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    if [[ -f "$age_key" ]]; then
        mkdir -p /mnt/root/.config/sops/age
        install -m 600 "$age_key" /mnt/root/.config/sops/age/keys.txt
        log_ok "age key copied to /mnt/root/.config/sops/age/keys.txt"
    else
        log_info "no age key found in live env ($age_key) — skipping"
    fi

    log_system_snapshot "post-chroot-setup"
    log_ok "chroot setup complete"
    return 0
}
