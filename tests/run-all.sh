#!/usr/bin/env bash
# tests/run-all.sh — runs the offline test suites (lint + unit). Prints a
# summary and exits non-zero if anything failed.
#
# VM-based suites (03, 04) are skipped here because they're interactive and
# require qemu/ISO setup. Run them manually:
#   tests/03-vm-bootstrap.sh
#   bash /mnt/host/04-post-install.sh   # inside the VM after first boot

set -uo pipefail

. "$(dirname "$0")/lib.sh"

echo
echo -e "${T_BOLD}╔════════════════════════════════════════════════════════════════╗${T_NC}"
echo -e "${T_BOLD}║          Void Fortress — Offline Test Suite                    ║${T_NC}"
echo -e "${T_BOLD}╚════════════════════════════════════════════════════════════════╝${T_NC}"

OVERALL_FAIL=0

run_suite() {
    local script="$1"
    if bash "$script"; then
        return 0
    else
        OVERALL_FAIL=$((OVERALL_FAIL + 1))
        return 1
    fi
}

run_suite "$TESTS_DIR/01-lint.sh"   || true
run_suite "$TESTS_DIR/02-unit.sh"   || true

echo
echo -e "${T_BOLD}─── Skipped (interactive) ──────────────────────────────────────${T_NC}"
echo "  03-vm-bootstrap.sh   — run manually: tests/03-vm-bootstrap.sh"
echo "  04-post-install.sh   — run inside VM after first boot"

echo
if (( OVERALL_FAIL == 0 )); then
    echo -e "${T_GREEN}${T_BOLD}══════════════════════════════════════${T_NC}"
    echo -e "${T_GREEN}${T_BOLD}  OFFLINE SUITES: ALL GREEN${T_NC}"
    echo -e "${T_GREEN}${T_BOLD}══════════════════════════════════════${T_NC}"
    exit 0
else
    echo -e "${T_RED}${T_BOLD}══════════════════════════════════════${T_NC}"
    echo -e "${T_RED}${T_BOLD}  OFFLINE SUITES: $OVERALL_FAIL FAILURE(S)${T_NC}"
    echo -e "${T_RED}${T_BOLD}══════════════════════════════════════${T_NC}"
    exit 1
fi
