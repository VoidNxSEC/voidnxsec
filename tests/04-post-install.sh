#!/usr/bin/env bash
# tests/04-post-install.sh — runs INSIDE the freshly installed Void Fortress VM
# after the first reboot. Validates that the install actually produced a
# bootable, mountable, sensible system.
#
# Usage (inside the VM, after first boot):
#   sudo bash /mnt/host/04-post-install.sh
#
# Exit code 0 = all green. Non-zero = at least one check failed.

set -uo pipefail

# Inline lib (so this script can run standalone in the VM without lib.sh present)
T_RED='\033[0;31m'; T_GREEN='\033[0;32m'; T_YELLOW='\033[1;33m'
T_CYAN='\033[0;36m'; T_BOLD='\033[1m'; T_NC='\033[0m'
TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0; FAILED_NAMES=()

pass()  { TESTS_RUN=$((TESTS_RUN+1)); TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  ${T_GREEN}✓${T_NC} $*"; }
fail()  { TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); FAILED_NAMES+=("$*"); echo -e "  ${T_RED}✗${T_NC} $*"; }
skip()  { echo -e "  ${T_YELLOW}~${T_NC} skip: $*"; }
section() { echo; echo -e "${T_BOLD}${T_CYAN}── $* ──${T_NC}"; }

if [[ $EUID -ne 0 ]]; then
    echo "must run as root (sudo bash $0)" >&2
    exit 2
fi

echo
echo -e "${T_BOLD}${T_CYAN}═══ Void Fortress — Post-Install Validation ═══${T_NC}"
echo "Hostname: $(hostname)"
echo "Kernel:   $(uname -r)"
echo "Date:     $(date)"

# ---------------------------------------------------------------------------
section "Boot environment"
# ---------------------------------------------------------------------------
if [[ -d /sys/firmware/efi ]]; then
    pass "booted in UEFI mode"
else
    fail "not UEFI (system fell back to BIOS?)"
fi
if [[ -d /sys/firmware/efi/efivars ]]; then
    pass "efivars accessible"
else
    skip "efivars not mounted"
fi

# ---------------------------------------------------------------------------
section "Filesystems and mounts"
# ---------------------------------------------------------------------------
if mountpoint -q /; then
    pass "/ mounted"
else
    fail "/ not a mountpoint"
fi
if mountpoint -q /boot; then
    pass "/boot mounted"
else
    fail "/boot not mounted"
fi
mountpoint -q /boot/efi && pass "/boot/efi mounted" || fail "/boot/efi not mounted"
mountpoint -q /home && pass "/home mounted" || fail "/home not mounted (LUKS2 unlock failed?)"

# Verify root is on a LUKS-backed device
root_src=$(findmnt -no SOURCE /)
if [[ "$root_src" == *"root_crypt"* || "$root_src" == "/dev/mapper/root_crypt" ]]; then
    pass "/ backed by /dev/mapper/root_crypt"
else
    fail "/ source is '$root_src' — expected /dev/mapper/root_crypt"
fi

home_src=$(findmnt -no SOURCE /home 2>/dev/null || echo "")
if [[ "$home_src" == *"home_crypt"* ]]; then
    pass "/home backed by /dev/mapper/home_crypt"
else
    fail "/home source is '$home_src' — expected /dev/mapper/home_crypt"
fi

# ---------------------------------------------------------------------------
section "Swap (regression check for fix #6)"
# ---------------------------------------------------------------------------
if swapon --show --noheadings | grep -q '^/dev/'; then
    swap_dev=$(swapon --show --noheadings | awk '{print $1}' | head -1)
    pass "swap active on $swap_dev"
    if [[ "$swap_dev" == *"/mapper/swap"* ]]; then
        pass "swap is on /dev/mapper/swap (encrypted, as expected)"
    else
        fail "swap is on $swap_dev — expected /dev/mapper/swap"
    fi
else
    fail "no active swap (mkswap or crypttab swap entry failed)"
fi

# ---------------------------------------------------------------------------
section "fstab integrity"
# ---------------------------------------------------------------------------
if [[ -f /etc/fstab ]]; then
    pass "/etc/fstab exists"
    grep -qE '^\s*UUID=[a-f0-9-]+\s+/\s+ext4' /etc/fstab && pass "fstab has root entry" || fail "fstab missing root entry"
    grep -qE '^\s*/dev/mapper/swap\s+none\s+swap' /etc/fstab && pass "fstab swap uses mapper (fix #6)" || fail "fstab swap not on /dev/mapper/swap"
    if grep -qE '^\s*UUID=.*\s+swap\s+sw' /etc/fstab; then
        fail "fstab has raw UUID swap entry — fix #6 regression"
    else
        pass "no raw-UUID swap entry"
    fi
else
    fail "/etc/fstab missing"
fi

# ---------------------------------------------------------------------------
section "crypttab"
# ---------------------------------------------------------------------------
if [[ -f /etc/crypttab ]]; then
    pass "/etc/crypttab exists"
    grep -qE '^root_crypt\s+UUID=' /etc/crypttab && pass "crypttab: root_crypt entry" || fail "crypttab: missing root_crypt"
    grep -qE '^home_crypt\s+UUID=' /etc/crypttab && pass "crypttab: home_crypt entry" || fail "crypttab: missing home_crypt"
    grep -qE '^swap\s+UUID=.*urandom' /etc/crypttab && pass "crypttab: swap with urandom" || fail "crypttab: missing encrypted swap"
else
    fail "/etc/crypttab missing"
fi

# ---------------------------------------------------------------------------
section "LUKS auto-unlock key (fix #4)"
# ---------------------------------------------------------------------------
if [[ -f /boot/volume.key ]]; then
    pass "/boot/volume.key exists"
    perm=$(stat -c '%a' /boot/volume.key)
    [[ "$perm" == "0" || "$perm" == "000" ]] && pass "volume.key perms locked down ($perm)" || fail "volume.key perms = $perm (expected 000)"

    # Verify the key actually unlocks the root partition
    root_part=$(blkid -t TYPE=crypto_LUKS -o device | head -1 || true)
    if [[ -n "$root_part" ]]; then
        if cryptsetup luksDump "$root_part" 2>/dev/null | grep -q 'Key Slot'; then
            pass "LUKS partition has key slots configured"
        fi
    fi
else
    fail "/boot/volume.key missing — auto-unlock will not work (fix #4 may have regressed)"
fi

# ---------------------------------------------------------------------------
section "Bootloader (GRUB)"
# ---------------------------------------------------------------------------
[[ -d /boot/grub ]] && pass "/boot/grub exists" || fail "/boot/grub missing"
[[ -f /boot/grub/grub.cfg ]] && pass "grub.cfg generated" || fail "grub.cfg missing"
[[ -d /boot/efi/EFI/void ]] && pass "EFI bootloader installed at /boot/efi/EFI/void" || fail "EFI bootloader not installed"

if [[ -f /etc/default/grub ]]; then
    grep -q "GRUB_ENABLE_CRYPTODISK=y" /etc/default/grub && pass "GRUB cryptodisk enabled" || fail "GRUB cryptodisk not enabled"
    grep -q "rd.luks.uuid=" /etc/default/grub && pass "GRUB cmdline has rd.luks.uuid" || fail "missing rd.luks.uuid in GRUB cmdline"
fi

# ---------------------------------------------------------------------------
section "Initramfs (regression check for fix #3)"
# ---------------------------------------------------------------------------
kver=$(uname -r)
if [[ -f "/boot/initramfs-${kver}.img" ]] || ls /boot/initramfs-* >/dev/null 2>&1; then
    initramfs=$(ls -1 /boot/initramfs-* 2>/dev/null | head -1)
    pass "initramfs present: $(basename "$initramfs")"
    # Verify it's for THE installed kernel, not an unrelated version
    if [[ "$initramfs" == *"$kver"* ]]; then
        pass "initramfs matches running kernel $kver (fix #3 holds)"
    else
        fail "initramfs ($initramfs) does NOT match kernel $kver — fix #3 regression"
    fi
    # Inspect contents: should include crypttab + volume.key
    if command -v lsinitrd &>/dev/null; then
        if lsinitrd "$initramfs" 2>/dev/null | grep -q 'crypttab'; then
            pass "initramfs includes crypttab"
        else
            fail "initramfs missing crypttab"
        fi
        if lsinitrd "$initramfs" 2>/dev/null | grep -q 'volume.key'; then
            pass "initramfs includes volume.key"
        else
            fail "initramfs missing volume.key (auto-unlock broken)"
        fi
    else
        skip "lsinitrd not available — cannot inspect initramfs contents"
    fi
else
    fail "no initramfs in /boot"
fi

# ---------------------------------------------------------------------------
section "User and sudo"
# ---------------------------------------------------------------------------
expected_user="${VOIDNX_USER:-nx}"
if id "$expected_user" &>/dev/null; then
    pass "user $expected_user exists"
    id "$expected_user" | grep -q wheel && pass "$expected_user in wheel group" || fail "$expected_user not in wheel"
    [[ -d "/home/$expected_user" ]] && pass "/home/$expected_user exists" || fail "no home dir for $expected_user"
else
    fail "user $expected_user missing"
fi
[[ -f /etc/sudoers.d/wheel ]] && pass "sudoers.d/wheel configured" || fail "sudoers.d/wheel missing"

# ---------------------------------------------------------------------------
section "Networking and locale"
# ---------------------------------------------------------------------------
[[ -f /etc/hostname ]] && pass "hostname set: $(cat /etc/hostname)" || fail "no /etc/hostname"
[[ -L /etc/localtime ]] && pass "timezone link: $(readlink /etc/localtime)" || fail "/etc/localtime not a symlink"

# ---------------------------------------------------------------------------
section "Encryption verification"
# ---------------------------------------------------------------------------
# Confirm the underlying partitions are actually LUKS-formatted
for part in $(lsblk -nlo NAME,FSTYPE | awk '$2=="crypto_LUKS"{print $1}'); do
    pass "/dev/$part is crypto_LUKS"
done

# Verify LUKS1 on root (per script design) and LUKS2 on home
root_phys=$(cryptsetup status root_crypt 2>/dev/null | awk '/device:/ {print $2}')
home_phys=$(cryptsetup status home_crypt 2>/dev/null | awk '/device:/ {print $2}')
if [[ -n "$root_phys" ]]; then
    luks_ver=$(cryptsetup luksDump "$root_phys" 2>/dev/null | awk '/Version:/ {print $2}')
    [[ "$luks_ver" == "1" ]] && pass "root LUKS version = 1 (as designed)" || fail "root LUKS version = $luks_ver, expected 1"
fi
if [[ -n "$home_phys" ]]; then
    luks_ver=$(cryptsetup luksDump "$home_phys" 2>/dev/null | awk '/Version:/ {print $2}')
    [[ "$luks_ver" == "2" ]] && pass "home LUKS version = 2 (as designed)" || fail "home LUKS version = $luks_ver, expected 2"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
if (( TESTS_FAILED == 0 )); then
    echo -e "${T_GREEN}${T_BOLD}══════════════════════════════════════${T_NC}"
    echo -e "${T_GREEN}${T_BOLD}  ALL POST-INSTALL CHECKS PASSED ($TESTS_PASSED/$TESTS_RUN)${T_NC}"
    echo -e "${T_GREEN}${T_BOLD}══════════════════════════════════════${T_NC}"
    exit 0
else
    echo -e "${T_RED}${T_BOLD}══════════════════════════════════════${T_NC}"
    echo -e "${T_RED}${T_BOLD}  $TESTS_FAILED FAILED, $TESTS_PASSED PASSED (of $TESTS_RUN)${T_NC}"
    echo -e "${T_RED}${T_BOLD}══════════════════════════════════════${T_NC}"
    echo
    echo "Failed checks:"
    for n in "${FAILED_NAMES[@]}"; do
        echo -e "  ${T_RED}- $n${T_NC}"
    done
    exit 1
fi
