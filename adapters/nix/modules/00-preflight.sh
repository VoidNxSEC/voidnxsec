#!/usr/bin/env bash
# modules/00-preflight.sh — Pre-flight phase
# Environment resolution, disk/host/flake checks, LUKS passphrase handling.

run_preflight() {
    # ── Disk resolution ──────────────────────────────────────────────
    if [[ -z "$DISK" ]]; then
        for dev in /dev/nvme0n1 /dev/sda /dev/vda; do
            [[ -b "$dev" ]] && { DISK="$dev"; break; }
        done
        if [[ -z "$DISK" ]]; then
            log_fatal "no disk detected — set DISK=/dev/<disk>"
            return 1
        fi
        log_warn "disk auto-detected: $DISK — confirm before continuing"
    fi

    # ── Flake attribute resolution ────────────────────────────────────
    # Repo hosts map to flake attrs: kernelcore→kernelcore,
    # laptop→voidnx-laptop, server→voidnx-server (templates).
    if [[ -z "$FLAKE_ATTR" ]]; then
        if nix --extra-experimental-features 'nix-command flakes' \
                eval --raw "$FLAKE_URI#nixosConfigurations.$HOST.config.networking.hostName" \
                > /dev/null 2>&1; then
            FLAKE_ATTR="$HOST"
        elif nix --extra-experimental-features 'nix-command flakes' \
                eval --raw "$FLAKE_URI#nixosConfigurations.voidnx-$HOST.config.networking.hostName" \
                > /dev/null 2>&1; then
            FLAKE_ATTR="voidnx-$HOST"
        else
            log_fatal "no flake attribute for host '$HOST' (tried: $HOST, voidnx-$HOST)"
            return 1
        fi
    fi

    # ── Disk vs partitions.nix device ─────────────────────────────────
    local partitions_file="$REPO_DIR/nixos/hosts/$HOST/partitions.nix"
    local declared_device
    declared_device=$(grep -oE 'device = "/dev/[a-z0-9]+"' "$partitions_file" | head -1 | sed -E 's/.*"(\/dev\/[a-z0-9]+)".*/\1/')
    if [[ -n "$declared_device" && "$declared_device" != "$DISK" ]]; then
        log_warn "partitions.nix declares device $declared_device but DISK=$DISK"
        log_warn "disko will use the declared device — verify partitions.nix or DISK"
    fi

    # ── LUKS passphrase ───────────────────────────────────────────────
    local pass_target="${LUKS_PASS_FILE:-/tmp/luks-pass}"

    if [[ -n "$LUKS_PASS" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            umask 077
            printf '%s' "$LUKS_PASS" > "$pass_target"
            chmod 600 "$pass_target"
        fi
        log_ok "LUKS passphrase staged at $pass_target (from LUKS_PASS env)"
    elif [[ -n "$LUKS_PASS_FILE" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            install -m 600 "$LUKS_PASS_FILE" "$pass_target"
        fi
        log_ok "LUKS passphrase staged at $pass_target (from file)"
    else
        if [[ "$DRY_RUN" != "true" ]]; then
            local pass confirm
            read -rsp "Enter LUKS passphrase: " pass; echo
            read -rsp "Confirm LUKS passphrase: " confirm; echo
            [[ "$pass" == "$confirm" ]] || { log_fatal "passphrases do not match"; return 1; }
            umask 077
            printf '%s' "$pass" > "$pass_target"
            chmod 600 "$pass_target"
            unset pass confirm
        fi
        log_ok "LUKS passphrase staged at $pass_target (interactive)"
    fi

    # ── Network / flake sanity ────────────────────────────────────────
    if ping -c1 -W5 cache.nixos.org > /dev/null 2>&1; then
        log_ok "network reachable (cache.nixos.org)"
    else
        log_warn "cache.nixos.org unreachable — builds may fail"
    fi

    # ── Config summary + initial state ────────────────────────────────
    log_info "host=$HOST flake_attr=$FLAKE_ATTR disk=$DISK flake=$FLAKE_URI"
    log_info "partitions=$partitions_file dry_run=$DRY_RUN"

    log_system_snapshot "pre-flight"

    save_nixos_state "$(detect_nixos_state)"
    return 0
}
