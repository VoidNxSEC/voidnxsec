#!/usr/bin/env bash
# lib/rollback.sh — NixOS generation rollback + JSONL logging
# Called by voidnx.sh on failure or manually via: voidnx.sh rollback
# shellcheck source=./logger_v2.sh

rollback_nixos_generation() {
    local reason="${1:-manual}"
    log_warn "initiating NixOS rollback (reason: $reason)"

    if ! command -v nixos-rebuild >/dev/null 2>&1; then
        log_fail "nixos-rebuild not found — not a NixOS system"
        return 1
    fi

    local current_gen
    current_gen=$(nixos-rebuild list-generations 2>/dev/null | grep current | awk '{print $1}' || echo "unknown")
    log_info "current generation: $current_gen"

    log_cmd "nixos-rebuild rollback" nixos-rebuild switch --rollback

    local new_gen
    new_gen=$(nixos-rebuild list-generations 2>/dev/null | grep current | awk '{print $1}' || echo "unknown")
    log_ok "rolled back from generation $current_gen to $new_gen"
}

get_nixos_state() {
    if ! command -v nixos-rebuild >/dev/null 2>&1; then
        echo "NOT_NIXOS"
        return
    fi

    local gen boot_default sealed_tpm sb_state

    gen=$(readlink /run/current-system 2>/dev/null | grep -o '[0-9]\+-' | tr -d '-' || echo "0")
    boot_default=$(bootctl status 2>/dev/null | grep "Current Boot Loader Entry" | awk '{print $NF}' || echo "unknown")

    # Check if TPM2 slot is enrolled on root LUKS
    sealed_tpm="false"
    if command -v systemd-cryptenroll >/dev/null 2>&1; then
        if systemd-cryptenroll --list-devices 2>/dev/null | grep -q "tpm2"; then
            sealed_tpm="true"
        fi
    fi

    # Secure Boot state
    local sb_raw
    sb_raw=$(xxd -p /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null \
        | tail -c 2 || echo "00")
    [[ "$sb_raw" == "01" ]] && sb_state="active" || sb_state="inactive"

    printf '{"nixos_generation":%s,"boot_default":"%s","tpm_pcr_policy":"7+9","sealed_tpm":%s,"secureboot_state":"%s"}' \
        "$gen" "$boot_default" "$sealed_tpm" "$sb_state"
}
