#!/usr/bin/env bash
# modules/06-finalize.sh — Finalize phase
# Summary of the install, post-boot checklist (TPM enroll, Secure Boot
# enablement, Lynis), final state save, optional auto-reboot.

run_finalize() {
    local attr="${FLAKE_ATTR:-$HOST}"

    # Leave the target in a clean state for reboot
    if [[ "$DRY_RUN" != "true" ]] && findmnt /mnt > /dev/null 2>&1; then
        log_info "unmounting /mnt (state persists in the JSONL ledger)"
        log_cmd "unmounting /mnt recursively" umount -R /mnt || true
    fi

    save_nixos_state "$(detect_nixos_state)"

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   NixOS bootstrap complete!                  ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    info "host:    $attr"
    info "disk:    $DISK"
    info "flake:   $FLAKE_URI"
    info "ledger:  $LOG_JSONL"
    echo ""
    warn_cli "Post-boot checklist:"
    echo "  1. Reboot and log in"
    echo "  2. Enroll TPM2 on the root LUKS (PCR 7+9):"
    echo "       sudo bash scripts/enroll-tpm.sh"
    echo "  3. Secure Boot keys (if not enrolled during bootloader phase):"
    echo "       sudo sbctl create-keys && sudo sbctl enroll-keys --microsoft"
    echo "  4. Enable Secure Boot in UEFI, reboot, verify:"
    echo "       sbctl verify && sbctl status"
    echo "  5. Audit the ledger: tools/analyze-log.sh"
    echo ""

    if [[ "$AUTO_REBOOT" == "true" ]]; then
        log_warn "AUTO_REBOOT=true — rebooting in 10 seconds (Ctrl+C to abort)"
        sleep 10
        reboot
    else
        log_info "reboot when ready"
    fi

    log_ok "finalize complete"
    return 0
}
