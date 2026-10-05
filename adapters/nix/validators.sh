#!/usr/bin/env bash
# =============================================================================
# adapters/nix/validators.sh — NixOS phase validators
# =============================================================================
# Adapter contract (see docs/adding-a-distro.md): one validate_pre_<phase> and
# validate_post_<phase> function per pipeline phase, each returning the number
# of failures (0 = pass). Failure details are emitted through the JSONL logger
# (log_fail / log_warn / log_ok), so every validation is part of the ledger.
#
# The distro-agnostic checks (disk exists / not mounted / UEFI) are duplicated
# here on purpose: lib/validators.sh targets the Void Linux installer layout
# (LUKS1/LUKS2 partitions 4/5, xbps, dracut, GRUB) and stays untouched.
# =============================================================================

# ── Generic helpers ────────────────────────────────────────────────────────────

check_disk() {
    local errors=0
    local disk="${DISK:-}"

    if [[ -z "$disk" ]]; then
        log_fail "DISK is not set"
        return 1
    fi
    if [[ ! -b "$disk" ]]; then
        log_fail "disk not found: $disk"
        ((errors++))
    fi
    if mount | grep -q "^${disk}"; then
        log_fail "disk $disk has mounted partitions"
        mount | grep "^${disk}" | while read -r line; do log_fail "mounted: $line"; done
        ((errors++))
    fi
    local size_gb=0
    local size_bytes
    size_bytes=$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)
    size_gb=$(( size_bytes / 1073741824 ))
    if [[ $size_gb -lt 20 ]]; then
        log_fail "disk too small: ${size_gb}GB (minimum: 20GB)"
        ((errors++))
    else
        log_ok "disk: $disk — ${size_gb}GB"
    fi
    return $errors
}

check_uefi() {
    if [[ ! -d /sys/firmware/efi ]]; then
        log_fail "system is not in UEFI mode (required by disko ESP + lanzaboote)"
        return 1
    fi
    log_ok "UEFI firmware detected"
    return 0
}

# ── preflight ──────────────────────────────────────────────────────────────────

validate_pre_preflight() {
    local errors=0

    [[ $EUID -eq 0 ]] || { log_fail "must run as root"; ((errors++)); }

    check_disk; errors=$(( errors + $? ))

    command -v nix > /dev/null 2>&1 || { log_fail "nix not found — run from NixOS minimal ISO"; ((errors++)); }
    command -v cryptsetup > /dev/null 2>&1 || { log_fail "cryptsetup not found"; ((errors++)); }

    if [[ "$DRY_RUN" != "true" ]]; then
        check_uefi; errors=$(( errors + $? ))
    fi

    if [[ ! -f "$FLAKE_URI/flake.nix" ]]; then
        log_fail "flake.nix not found in FLAKE_URI: $FLAKE_URI"
        ((errors++))
    fi

    local partitions_file="$REPO_DIR/nixos/hosts/$HOST/partitions.nix"
    if [[ ! -f "$partitions_file" ]]; then
        log_fail "host '$HOST' has no partitions.nix at: $partitions_file"
        ((errors++))
    fi

    # LUKS passphrase must be resolvable before disk-setup
    if [[ -z "$LUKS_PASS" && -z "$LUKS_PASS_FILE" ]]; then
        log_warn "no LUKS passphrase provided — will prompt interactively"
    fi

    log_ok "preflight validation done ($errors failures)"
    return $errors
}

# ── disk-setup ─────────────────────────────────────────────────────────────────

validate_pre_disk_setup() {
    local errors=0
    local pass_file="${LUKS_PASS_FILE:-/tmp/luks-pass}"

    check_disk; errors=$(( errors + $? ))

    # Passphrase file (written by the preflight module) must exist and be 0600
    if [[ -f "$pass_file" ]]; then
        local perms
        perms=$(stat -c "%a" "$pass_file")
        if [[ "$perms" != "600" ]]; then
            log_fail "passphrase file $pass_file has insecure perms: $perms (expected 600)"
            ((errors++))
        else
            log_ok "passphrase file ready: $pass_file"
        fi
    else
        log_info "no passphrase file — disko will prompt interactively"
    fi

    return $errors
}

validate_post_disk_setup() {
    local errors=0

    # At least one crypt mapper must be open after disko
    local mappers=0
    local m
    shopt -s nullglob
    for m in /dev/mapper/*; do
        [[ "${m##*/}" != "control" ]] && ((mappers++))
    done
    shopt -u nullglob
    if [[ "$mappers" -eq 0 ]]; then
        log_fail "no crypt mappers open after disko"
        ((errors++))
    else
        log_ok "crypt mappers open: $mappers"
    fi

    # Root filesystem must be mounted at /mnt
    if ! mountpoint -q /mnt 2>/dev/null; then
        log_fail "/mnt is not mounted — disko --mode disko should mount it"
        ((errors++))
    else
        log_ok "/mnt mounted"
    fi

    return $errors
}

# ── mount ──────────────────────────────────────────────────────────────────────

validate_pre_mount() {
    local errors=0

    if ! mountpoint -q /mnt 2>/dev/null; then
        log_fail "/mnt is not mounted (run install.sh clean, then re-run disk-setup)"
        ((errors++))
    fi

    return $errors
}

validate_post_mount() {
    local errors=0

    # Expected sub-mounts (from the repo disko layouts): /mnt/boot and either
    # /mnt (root) or /mnt/persist (impermanence hosts)
    findmnt /mnt/boot > /dev/null 2>&1 \
        || { log_fail "/mnt/boot is not mounted"; ((errors++)); }

    local root_ok=false
    findmnt /mnt > /dev/null 2>&1 && root_ok=true
    findmnt /mnt/persist > /dev/null 2>&1 && root_ok=true
    if [[ "$root_ok" != "true" ]]; then
        log_fail "no root filesystem under /mnt (expected /mnt or /mnt/persist)"
        ((errors++))
    fi

    log_ok "mount layout verified"
    return $errors
}

# ── base-install ───────────────────────────────────────────────────────────────

validate_pre_base_install() {
    local errors=0

    if ! mountpoint -q /mnt 2>/dev/null; then
        log_fail "/mnt is not mounted — cannot run nixos-install"
        ((errors++))
    fi

    # flake attribute must exist
    local attr="${FLAKE_ATTR:-$HOST}"
    if ! nix --extra-experimental-features 'nix-command flakes' \
            eval --raw "$FLAKE_URI#nixosConfigurations.$attr.config.system.build.toplevel.drvPath" > /dev/null 2>&1; then
        log_warn "cannot evaluate $FLAKE_URI#nixosConfigurations.$attr — install will fail"
        ((errors++))
    else
        log_ok "flake attribute $attr evaluates"
    fi

    return $errors
}

validate_post_base_install() {
    local errors=0

    # The Nix store must be populated in the target
    if [[ ! -d /mnt/nix/store ]]; then
        log_fail "/mnt/nix/store does not exist — nixos-install did not complete"
        ((errors++))
    else
        local entries
        entries=$(find /mnt/nix/store -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
        if [[ "$entries" -eq 0 ]]; then
            log_fail "/mnt/nix/store is empty"
            ((errors++))
        else
            log_ok "/mnt/nix/store populated ($entries entries)"
        fi
    fi

    [[ -f /mnt/etc/os-release ]] || { log_warn "/mnt/etc/os-release missing"; }
    [[ -d /mnt/etc/nixos ]] || { log_warn "/mnt/etc/nixos missing — flake not copied"; }

    return $errors
}

# ── chroot-setup ───────────────────────────────────────────────────────────────

validate_post_chroot_setup() {
    local errors=0

    # sops-nix host key must be present for secrets at first boot
    if [[ ! -f /mnt/etc/ssh/ssh_host_ed25519_key ]]; then
        log_fail "/mnt/etc/ssh/ssh_host_ed25519_key missing — sops-nix will fail at boot"
        ((errors++))
    else
        log_ok "sops-nix host key present"
    fi

    return $errors
}

# ── bootloader ─────────────────────────────────────────────────────────────────

validate_post_bootloader() {
    local errors=0

    # systemd-boot or lanzaboote UKIs must exist under /mnt/boot
    if [[ -d /mnt/boot/loader/entries ]] || [[ -d /mnt/boot/EFI/Linux ]]; then
        log_ok "boot entries present under /mnt/boot"
    else
        log_fail "no boot entries found under /mnt/boot"
        ((errors++))
    fi

    return $errors
}

# ── finalize ───────────────────────────────────────────────────────────────────

validate_post_finalize() {
    local errors=0

    if [[ ! -f "$PHASE_FILE" ]]; then
        log_fail "phase state file $PHASE_FILE missing"
        ((errors++))
    else
        local done_phases
        done_phases=$(grep -c '^PHASE_.*=done$' "$PHASE_FILE")
        log_ok "phase ledger: $done_phases phases done"
    fi

    return $errors
}
