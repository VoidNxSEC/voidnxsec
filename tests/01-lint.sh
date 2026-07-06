#!/usr/bin/env bash
# tests/01-lint.sh — static analysis: bash syntax + (optional) shellcheck.

. "$(dirname "$0")/lib.sh"

init_suite "01 — Static analysis (lint)"

# 1. bash -n on every shell script in the project
mapfile -t scripts < <(find "$PROJECT_DIR" -maxdepth 2 -type f \
    \( -name "*.sh" -o -name "voidnx*" \) ! -path "*/.git/*" 2>/dev/null)

if (( ${#scripts[@]} == 0 )); then
    fail "no scripts found to lint"
else
    for s in "${scripts[@]}"; do
        # Only lint things that look like bash
        if head -1 "$s" 2>/dev/null | grep -qE '^#!.*(bash|sh)'; then
            if bash -n "$s" 2>/dev/null; then
                pass "syntax: $(basename "$s")"
            else
                fail "syntax: $(basename "$s") — bash -n failed"
                bash -n "$s" 2>&1 | sed 's/^/      /'
            fi
        fi
    done
fi

# 2. shellcheck (optional — installed via shellcheck or shfmt)
if command -v shellcheck &>/dev/null; then
    for s in "${scripts[@]}"; do
        if head -1 "$s" 2>/dev/null | grep -qE '^#!.*(bash|sh)'; then
            # -e SC1091: don't follow sourced files (they may not exist at lint time)
            # -e SC2086: word splitting — too noisy, project uses it intentionally
            if shellcheck -e SC1091,SC2086,SC2155,SC2034 "$s" >/dev/null 2>&1; then
                pass "shellcheck: $(basename "$s")"
            else
                fail "shellcheck: $(basename "$s") — see warnings"
                shellcheck -e SC1091,SC2086,SC2155,SC2034 "$s" 2>&1 | head -20 | sed 's/^/      /'
            fi
        fi
    done
else
    skip "shellcheck not installed (xbps-install shellcheck)"
fi

# 3. Sanity check: voidnx.sh defines all functions referenced in handle_state
required_functions=(
    detect_environment validate_system_requirements auto_select_disk
    detect_disk_size_and_adjust detect_installation_state handle_state
    partition_disk setup_luks open_luks mount_filesystems
    bootstrap_system generate_fstab generate_chroot_script run_chroot_config
    cleanup cleanup_chroot prepare_chroot
)
for fn in "${required_functions[@]}"; do
    if grep -qE "^[[:space:]]*${fn}\(\)" "$SCRIPT_UNDER_TEST"; then
        pass "function defined: $fn"
    else
        fail "function MISSING: $fn"
    fi
done

# 4. No remaining void_crypt / void-vg references in EXECUTABLE code (fixes #1, #2, #18)
# Comments are allowed (they may describe the fix historically).
hits=$(grep -nE 'void_crypt|void-vg|/dev/void-vg' "$SCRIPT_UNDER_TEST" \
       | awk -F: '{ line=$0; sub(/^[0-9]+:/, "", line); if (line !~ /^[[:space:]]*#/) print $0 }')
if [[ -n "$hits" ]]; then
    fail "void_crypt or void-vg still referenced in code (regression of fix #1/#2/#18)"
    # shellcheck disable=SC2001
    echo "$hits" | sed 's/^/      /'
else
    pass "no stale void_crypt / void-vg references in code"
fi

# 5. dracut --kver should NOT use uname -r (regression for fix #3)
if grep -nE 'dracut.*--kver.*uname' "$SCRIPT_UNDER_TEST" >/dev/null; then
    fail "dracut --kver still uses \$(uname -r) (regression of fix #3)"
else
    pass "dracut --kver does not use uname -r"
fi

# 6. fstab swap line should reference /dev/mapper/swap (regression for fix #6)
if grep -nE '/dev/mapper/swap.*swap' "$SCRIPT_UNDER_TEST" >/dev/null; then
    pass "fstab swap uses /dev/mapper/swap"
else
    fail "fstab swap entry does not use /dev/mapper/swap (regression of fix #6)"
fi

# 7. trap exit_trap should appear before the case statement (regression for fix #7)
trap_line=$(grep -n '^trap exit_trap EXIT' "$SCRIPT_UNDER_TEST" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016
case_line=$(grep -n '^case "${1:-}"' "$SCRIPT_UNDER_TEST" | head -1 | cut -d: -f1)
if [[ -n "$trap_line" && -n "$case_line" && "$trap_line" -lt "$case_line" ]]; then
    pass "trap registered before case dispatch"
else
    fail "trap exit_trap not before case (regression of fix #7)"
fi

# 8. configure.sh heredoc should define warn() (regression for fix #5)
if grep -nE 'warn\(\).*WARN' "$SCRIPT_UNDER_TEST" >/dev/null; then
    pass "warn() defined inside chroot configure.sh"
else
    fail "warn() missing in chroot configure.sh (regression of fix #5)"
fi

# 9. recompute_part_suffix() should exist and be called from auto_select_disk (fix #8)
if grep -qE '^recompute_part_suffix\(\)' "$SCRIPT_UNDER_TEST"; then
    pass "recompute_part_suffix() function defined (fix #8)"
else
    fail "recompute_part_suffix() not defined (regression of fix #8)"
fi
auto_select_body=$(awk '/^auto_select_disk\(\) \{/,/^\}/' "$SCRIPT_UNDER_TEST")
if echo "$auto_select_body" | grep -q 'recompute_part_suffix'; then
    pass "auto_select_disk calls recompute_part_suffix (fix #8)"
else
    fail "auto_select_disk does NOT call recompute_part_suffix"
fi

# 10. base-system-essentials should NOT appear (fix #9)
if grep -q 'base-system-essentials' "$SCRIPT_UNDER_TEST"; then
    fail "base-system-essentials still in BASE_PKGS (regression of fix #9)"
else
    pass "base-system-essentials not present (fix #9)"
fi

# 11. apparmor=1 / security=apparmor should not be in default GRUB cmdline (fix #10)
if grep -E 'GRUB_CMDLINE_LINUX_DEFAULT=.*apparmor=1' "$SCRIPT_UNDER_TEST" >/dev/null; then
    fail "apparmor=1 still in GRUB_CMDLINE_LINUX_DEFAULT (regression of fix #10)"
else
    pass "apparmor not in default GRUB cmdline (fix #10)"
fi

# 12. Non-interactive password support (fix #11)
if grep -q 'LUKS_PASS' "$SCRIPT_UNDER_TEST"; then
    pass "LUKS_PASS supported in voidnx.sh (fix #11)"
else
    fail "LUKS_PASS not handled (regression of fix #11)"
fi
if grep -q 'chpasswd' "$SCRIPT_UNDER_TEST"; then
    pass "chpasswd used for non-interactive passwd (fix #11)"
else
    fail "chpasswd not used (regression of fix #11)"
fi

# 13. required_tools should include the missing tools (fix #12)
validate_body=$(awk '/^validate_system_requirements\(\) \{/,/^\}/' "$SCRIPT_UNDER_TEST")
for new_tool in bc uuidgen fuser wipefs swapon mkswap chpasswd; do
    if echo "$validate_body" | grep -qw "$new_tool"; then
        pass "required_tools includes $new_tool (fix #12)"
    else
        fail "required_tools missing $new_tool (regression of fix #12)"
    fi
done

# 14. IS_LIVE detection should use explicit if (fix #13)
if grep -E 'if \[\[ -f /run/void-live \]\] \|\| grep' "$SCRIPT_UNDER_TEST" >/dev/null; then
    pass "IS_LIVE detection uses explicit if (fix #13)"
else
    fail "IS_LIVE detection still ambiguous (regression of fix #13)"
fi

# 15. Package count should not use wc -c (fix #14)
if grep -E '\$\{#BASE_PKGS\[@\]\} packages' "$SCRIPT_UNDER_TEST" >/dev/null; then
    pass "package count uses array length directly (fix #14)"
else
    fail "package count still uses wc -c trick (regression of fix #14)"
fi

finish_suite
