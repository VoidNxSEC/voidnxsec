#!/usr/bin/env bash
# modules/03-base-install.sh — Base Install phase
# Declarative base system install: nixos-install evaluates the host flake
# attribute, builds the closure and writes it into /mnt.

run_base_install() {
    local attr="${FLAKE_ATTR:-$HOST}"

    if [[ "$DRY_RUN" == "true" ]]; then
        run "nixos-install (dry)" true
        return 0
    fi

    log_info "installing $FLAKE_URI#$attr into /mnt (this is the long step)"
    log_info "building the closure + populating the Nix store"

    nixos-install \
        --flake "$FLAKE_URI#$attr" \
        --no-root-passwd \
        || { log_fail "nixos-install failed"; return 1; }

    log_system_snapshot "post-base-install"
    log_ok "base system installed"
    return 0
}
