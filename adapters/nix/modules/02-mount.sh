#!/usr/bin/env bash
# modules/02-mount.sh — Mount phase
# In the Nix track, disko --mode disko already mounts everything under /mnt.
# This phase verifies the mount layout and repairs it with `disko --mode mount`
# when the run is resumed after a crash between formatting and mounting.

run_mount() {
    if findmnt /mnt > /dev/null 2>&1; then
        log_ok "disko mounts already present — nothing to do"
        log_cmd "mount layout" findmnt -R -o TARGET,SOURCE,FSTYPE /mnt
        return 0
    fi

    log_warn "/mnt not mounted — re-running disko in mount mode"
    if [[ "$DRY_RUN" == "true" ]]; then
        run "disko mount (dry)" true
        return 0
    fi

    nix --extra-experimental-features 'nix-command flakes' run \
        --inputs-from "$FLAKE_URI" \
        'github:nix-community/disko#disko' \
        --mode mount "$REPO_DIR/nixos/hosts/$HOST/partitions.nix" \
        || { log_fail "disko --mode mount failed"; return 1; }

    log_system_snapshot "post-mount"
    log_ok "filesystems mounted under /mnt"
    return 0
}
