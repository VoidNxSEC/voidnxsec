#!/usr/bin/env bash
# modules/01-disk-setup.sh — Disk Setup phase
# Declarative partitioning + LUKS encryption via disko (replaces the manual
# sfdisk/cryptsetup sequence of the Void track with the host's partitions.nix).

run_disk_setup() {
    local partitions_file="$REPO_DIR/nixos/hosts/$HOST/partitions.nix"

    log_warn "disko WILL DESTROY ALL DATA on the disk declared in $partitions_file"
    if [[ "$DRY_RUN" != "true" ]]; then
        read -rp "Type 'sim' to confirm wiping the target disk: " confirm
        [[ "$confirm" == "sim" ]] || { log_fatal "aborted by user"; return 1; }
    fi

    # disko resolves through the repo flake lock (deterministic pin)
    local disko_args=(--mode disko "$partitions_file")

    # Function-style configs ({ disks ? [...] }:) accept a disk list
    if grep -qE '^\s*\{?\s*disks\s*\?' "$partitions_file" 2>/dev/null; then
        disko_args+=(--arg disks "[\"$DISK\"]")
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        run "disko format+encrypt (dry)" true
        return 0
    fi

    log_info "running disko --mode disko (this can take a while)"
    nix --extra-experimental-features 'nix-command flakes' run \
        --inputs-from "$FLAKE_URI" \
        'github:nix-community/disko#disko' -- "${disko_args[@]}" \
        || { log_fail "disko failed"; return 1; }

    log_system_snapshot "post-disk-setup"
    log_ok "disk layout applied (partitions + LUKS + filesystems)"
    return 0
}
