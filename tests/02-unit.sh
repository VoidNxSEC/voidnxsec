#!/usr/bin/env bash
# tests/02-unit.sh — unit tests for pure-ish functions in voidnx.sh.
#
# Strategy: source voidnx.sh in a NON-EXECUTING way (we wrap the case dispatch),
# then call individual functions with mocked external commands (cryptsetup,
# blkid, vgs, mountpoint, lsblk, etc.) injected via PATH.

. "$(dirname "$0")/lib.sh"

init_suite "02 — Unit tests (functions in isolation)"

# ---------------------------------------------------------------------------
# Helper: source voidnx.sh without running main / case dispatch.
# We do this by replacing the trailing `case` with a noop in a temp copy.
# ---------------------------------------------------------------------------
SOURCED_COPY="$(mktemp --suffix=.sh)"
trap 'rm -f "$SOURCED_COPY"' EXIT

# Strip from the line `case "${1:-}" in` to end of file, replacing with `:`
awk '
    /^case "\$\{1:-\}" in$/ { print ":"; skipping=1; next }
    skipping { next }
    { print }
' "$SCRIPT_UNDER_TEST" > "$SOURCED_COPY"

# Also neutralize set -e so a single test failure doesn't kill the runner
sed -i 's/^set -euo pipefail$/set +e; set -uo pipefail/' "$SOURCED_COPY"

# ---------------------------------------------------------------------------
# Test: p() builds correct partition names for nvme/sda
# ---------------------------------------------------------------------------
test_partition_naming() {
    (
        # Force DISK + PART_SUFFIX without re-running detect_environment
        # shellcheck disable=SC1090
        source "$SOURCED_COPY"
        DISK=/dev/nvme0n1
        PART_SUFFIX=p
        local r1=$(p 1) r4=$(p 4)
        assert_eq "/dev/nvme0n1p1" "$r1" "p() nvme partition 1"
        assert_eq "/dev/nvme0n1p4" "$r4" "p() nvme partition 4"

        DISK=/dev/sda
        PART_SUFFIX=""
        local s1=$(p 1) s5=$(p 5)
        assert_eq "/dev/sda1" "$s1" "p() sda partition 1"
        assert_eq "/dev/sda5" "$s5" "p() sda partition 5"

        DISK=/dev/vda
        PART_SUFFIX=""
        local v3=$(p 3)
        assert_eq "/dev/vda3" "$v3" "p() vda partition 3"
    )
}
test_partition_naming

# ---------------------------------------------------------------------------
# Test: detect_installation_state correctly reports states given mocked env
# ---------------------------------------------------------------------------
test_state_detection() {
    local mockdir
    mockdir=$(mktemp -d)
    trap 'rm -rf "$mockdir"' RETURN

    # Mock cryptsetup, blkid, mountpoint, vgs as needed
    mock_cmd "$mockdir" cryptsetup 'exit 0'
    mock_cmd "$mockdir" blkid 'echo "TYPE=ext4"'
    mock_cmd "$mockdir" mountpoint 'exit 0'
    mock_cmd "$mockdir" vgs 'exit 0'

    PATH="$mockdir:$PATH" bash -c "
        source '$SOURCED_COPY'
        DISK=/dev/loop99
        PART_SUFFIX=p
        # No disk present
        result=\$(detect_installation_state)
        echo \"\$result\"
    " > "$mockdir/out.txt" 2>&1

    local result
    result=$(cat "$mockdir/out.txt")
    assert_contains "$result" "NO_DISK" "state=NO_DISK when /dev/loop99 missing"
}
test_state_detection

# ---------------------------------------------------------------------------
# Test: state machine no longer references LVM (regression for fix #2)
# ---------------------------------------------------------------------------
test_no_lvm_state() {
    if grep -E 'STATE="NO_LVM"' "$SCRIPT_UNDER_TEST" >/dev/null; then
        fail "STATE=NO_LVM still present (regression of fix #2)"
    else
        pass "no STATE=NO_LVM in detect_installation_state"
    fi
    if grep -E 'vgs void-vg' "$SCRIPT_UNDER_TEST" >/dev/null; then
        fail "vgs void-vg still called (regression of fix #2)"
    else
        pass "no vgs void-vg call"
    fi
}
test_no_lvm_state

# ---------------------------------------------------------------------------
# Test: state detection uses root_crypt mapper (regression for fix #1)
# ---------------------------------------------------------------------------
test_state_uses_root_crypt() {
    # Extract just the detect_installation_state function body
    local body
    body=$(awk '/^detect_installation_state\(\) \{/,/^\}/' "$SCRIPT_UNDER_TEST")
    assert_contains "$body" "/dev/mapper/root_crypt" "state checks /dev/mapper/root_crypt"
    assert_not_contains "$body" "/dev/mapper/void_crypt" "state does NOT check /dev/mapper/void_crypt"
}
test_state_uses_root_crypt

# ---------------------------------------------------------------------------
# Test: generate_chroot_script body — key generation order (fix #4)
# ---------------------------------------------------------------------------
test_key_generation_order() {
    local body
    body=$(awk '/^generate_chroot_script\(\) \{/,/^\}/' "$SCRIPT_UNDER_TEST")

    # The host-side dd of volume.key must come before luksAddKey
    local dd_pos
    dd_pos=$(echo "$body" | grep -n 'dd .* of=/mnt/boot/volume.key' | head -1 | cut -d: -f1)
    local addkey_pos
    addkey_pos=$(echo "$body" | grep -n 'cryptsetup luksAddKey' | head -1 | cut -d: -f1)

    if [[ -n "$dd_pos" && -n "$addkey_pos" && "$dd_pos" -lt "$addkey_pos" ]]; then
        pass "volume.key generated BEFORE luksAddKey (fix #4)"
    else
        fail "key generation/luksAddKey order wrong (dd=$dd_pos, addkey=$addkey_pos)"
    fi
}
test_key_generation_order

# ---------------------------------------------------------------------------
# Test: configure.sh heredoc — kernel detection (fix #3)
# ---------------------------------------------------------------------------
test_dracut_kernel_detection() {
    # The heredoc generates the chroot script. Look for KVER detection.
    if grep -E 'KVER=.*ls /lib/modules' "$SCRIPT_UNDER_TEST" >/dev/null; then
        pass "configure.sh detects KVER from /lib/modules (fix #3)"
    else
        fail "configure.sh does NOT detect KVER from /lib/modules"
    fi
}
test_dracut_kernel_detection

# ---------------------------------------------------------------------------
# Test: validate_system_requirements function exists and lists key tools
# ---------------------------------------------------------------------------
test_validate_requirements_lists_tools() {
    local body
    body=$(awk '/^validate_system_requirements\(\) \{/,/^\}/' "$SCRIPT_UNDER_TEST")
    for tool in cryptsetup sfdisk mkfs.ext4 mkfs.vfat blkid lsblk xbps-install dracut grub-install; do
        assert_contains "$body" "$tool" "required_tools includes $tool"
    done
}
test_validate_requirements_lists_tools

# ---------------------------------------------------------------------------
# Test: trap is exit_trap not raw cleanup (fix #7)
# ---------------------------------------------------------------------------
test_exit_trap_indirection() {
    if grep -E '^trap exit_trap EXIT' "$SCRIPT_UNDER_TEST" >/dev/null; then
        pass "uses exit_trap indirection (fix #7)"
    else
        fail "no 'trap exit_trap EXIT' found"
    fi
    if grep -E 'RUN_CLEANUP_ON_EXIT=' "$SCRIPT_UNDER_TEST" >/dev/null; then
        pass "RUN_CLEANUP_ON_EXIT flag present (fix #7)"
    else
        fail "RUN_CLEANUP_ON_EXIT flag missing"
    fi
}
test_exit_trap_indirection

finish_suite
