#!/usr/bin/env bash
# enroll-tpm.sh — Enroll TPM2 for LUKS auto-unlock
# Run AFTER first successful boot with Secure Boot active
# PCR 7 = Secure Boot state, PCR 9 = kernel + initrd
# DO NOT use PCR 0 (breaks on firmware updates)
set -euo pipefail

echo "[INFO] Checking prerequisites..."

[[ $EUID -ne 0 ]] && { echo "[FATAL] must run as root"; exit 1; }
command -v systemd-cryptenroll >/dev/null 2>&1 || { echo "[FATAL] systemd-cryptenroll not found"; exit 1; }
command -v tpm2_getcap >/dev/null 2>&1 || { echo "[FATAL] tpm2-tools not found"; exit 1; }

# Verify TPM2 is available and Secure Boot is active
if ! tpm2_getcap properties-fixed 2>/dev/null | grep -q "TPM2_PT_MANUFACTURER"; then
    echo "[FATAL] TPM2 device not found or not accessible"
    exit 1
fi

SB_STATE=$(xxd -p /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | tail -c 2 || echo "00")
if [[ "$SB_STATE" != "01" ]]; then
    echo "[WARN] Secure Boot does not appear to be active (state: $SB_STATE)"
    echo "[WARN] TPM binding to PCR 7 without active Secure Boot provides weaker guarantees"
    read -rp "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

echo "[OK] TPM2 available, Secure Boot state checked"

# Detect LUKS devices
LUKS_DEVICES=()
while IFS= read -r dev; do
    LUKS_DEVICES+=("$dev")
done < <(lsblk -rno NAME,TYPE | awk '$2=="crypt"{print "/dev/mapper/"$1}' 2>/dev/null || true)

# Also detect underlying LUKS block devices
while IFS= read -r dev; do
    if cryptsetup isLuks "$dev" 2>/dev/null; then
        LUKS_DEVICES+=("$dev")
    fi
done < <(lsblk -rno NAME,TYPE | awk '$2=="part"{print "/dev/"$1}')

if [[ ${#LUKS_DEVICES[@]} -eq 0 ]]; then
    echo "[FATAL] No LUKS devices detected"
    exit 1
fi

echo "[INFO] Found LUKS devices:"
printf '  %s\n' "${LUKS_DEVICES[@]}"

# Enroll TPM2 on each LUKS partition
for dev in "${LUKS_DEVICES[@]}"; do
    # Skip non-LUKS and mapper devices (enroll on the raw partition)
    [[ "$dev" == /dev/mapper/* ]] && continue
    cryptsetup isLuks "$dev" 2>/dev/null || continue

    echo "[INFO] Enrolling TPM2 on $dev (PCR 7+9)..."
    systemd-cryptenroll \
        --tpm2-device=auto \
        --tpm2-pcrs=7+9 \
        --tpm2-with-pin=no \
        "$dev"
    echo "[OK] Enrolled: $dev"
done

echo ""
echo "[OK] TPM2 enrollment complete."
echo "     On next boot, LUKS will unlock automatically if:"
echo "     - Secure Boot state matches (PCR 7)"
echo "     - Kernel + initrd match (PCR 9)"
echo "     - TPM policy is valid"
echo ""
echo "     To revoke TPM key slot: systemd-cryptenroll --wipe-slot=tpm2 <device>"
