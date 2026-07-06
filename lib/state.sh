#!/usr/bin/env bash
# lib/state.sh — NixOS state detection for voidnx.sh
# Extends the 12-state Void Linux state machine with NixOS bootstrap states
# shellcheck source=./logger_v2.sh

# NixOS bootstrap states:
# NIXOS_FLAKE_MISSING   — repo present but no nixosConfigurations defined
# NIXOS_NOT_DEPLOYED    — disk partitioned but NixOS not yet installed
# NIXOS_BOOTED          — booted into NixOS, TPM not enrolled
# NIXOS_TPM_ENROLLED    — TPM2 enrolled, Secure Boot pending
# NIXOS_SECUREBOOT_ON   — Secure Boot active — fully operational
# NIXOS_READY           — all layers active, Lynis score ≥ 75

detect_nixos_state() {
    local repo_dir="${REPO_DIR:-/opt/voidnxsec}"

    if ! command -v nixos-rebuild >/dev/null 2>&1; then
        if [[ -f "${repo_dir}/flake.nix" ]]; then
            echo "NIXOS_NOT_DEPLOYED"
        else
            echo "NIXOS_FLAKE_MISSING"
        fi
        return
    fi

    # Check TPM enrollment
    local tpm_enrolled=false
    if command -v systemd-cryptenroll >/dev/null 2>&1; then
        systemd-cryptenroll --list-devices 2>/dev/null | grep -q "tpm2" && tpm_enrolled=true
    fi

    # Check Secure Boot
    local sb_raw
    sb_raw=$(cat /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null \
        | xxd -p | tail -c 2 || echo "00")

    if [[ "$sb_raw" == "01" ]] && $tpm_enrolled; then
        echo "NIXOS_SECUREBOOT_ON"
    elif $tpm_enrolled; then
        echo "NIXOS_TPM_ENROLLED"
    else
        echo "NIXOS_BOOTED"
    fi
}

save_nixos_state() {
    local state="$1"
    local state_file="${STATE_FILE:-/tmp/void-fortress.state}"
    {
        echo "NIXOS_STATE=$state"
        echo "NIXOS_STATE_TS=$(date -Iseconds)"
    } >> "$state_file"
}
