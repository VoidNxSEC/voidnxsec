#!/usr/bin/env bash
# tests/03-vm-bootstrap.sh — boot a Void Linux live ISO in qemu/OVMF and run
# voidnx.sh against an empty virtual disk.
#
# This is INTERACTIVE: you'll need to enter LUKS passphrase + root/user passwords
# inside the VM. The script's job is to set up the environment so you can do that
# reliably and reproducibly.
#
# Requirements (host):
#   - qemu-system-x86_64
#   - OVMF firmware (path autodetected; override with OVMF_CODE / OVMF_VARS)
#   - ~25 GB free in $VM_DIR (default: ./tests/.vm/)
#   - Void Linux live ISO (auto-downloaded if not present, or provide VOID_ISO=...)
#
# Usage:
#   tests/03-vm-bootstrap.sh           # interactive bootstrap (default 20G disk)
#   DISK_SIZE=40G tests/03-vm-bootstrap.sh
#   VOID_ISO=/path/to/void.iso tests/03-vm-bootstrap.sh
#   SKIP_DOWNLOAD=1 tests/03-vm-bootstrap.sh    # error if no ISO present
#
# After install, run tests/04-post-install.sh INSIDE the booted VM.

set -uo pipefail

. "$(dirname "$0")/lib.sh"

init_suite "03 — VM bootstrap (qemu + OVMF + Void live ISO)"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
VM_DIR="${VM_DIR:-$TESTS_DIR/.vm}"
DISK_IMG="${DISK_IMG:-$VM_DIR/void-fortress.qcow2}"
DISK_SIZE="${DISK_SIZE:-20G}"
VM_RAM="${VM_RAM:-4096}"
VM_CPUS="${VM_CPUS:-2}"
VOID_ISO="${VOID_ISO:-$VM_DIR/void-live.iso}"
VOID_ISO_URL="${VOID_ISO_URL:-https://repo-default.voidlinux.org/live/current/void-live-x86_64-musl-20240314.iso}"

# OVMF firmware autodetect (NixOS, Arch, Debian paths)
OVMF_CODE="${OVMF_CODE:-}"
OVMF_VARS_TEMPLATE="${OVMF_VARS_TEMPLATE:-}"

autodetect_ovmf() {
    local candidates_code=(
        /run/libvirt/nix-ovmf/OVMF_CODE.fd
        /usr/share/OVMF/OVMF_CODE.fd
        /usr/share/OVMF/OVMF_CODE_4M.fd
        /usr/share/edk2/x64/OVMF_CODE.fd
        /usr/share/edk2-ovmf/x64/OVMF_CODE.fd
        /nix/store/*/share/OVMF/OVMF_CODE.fd
    )
    local candidates_vars=(
        /run/libvirt/nix-ovmf/OVMF_VARS.fd
        /usr/share/OVMF/OVMF_VARS.fd
        /usr/share/OVMF/OVMF_VARS_4M.fd
        /usr/share/edk2/x64/OVMF_VARS.fd
        /usr/share/edk2-ovmf/x64/OVMF_VARS.fd
    )
    if [[ -z "$OVMF_CODE" ]]; then
        for c in "${candidates_code[@]}"; do
            for resolved in $c; do
                [[ -f "$resolved" ]] && OVMF_CODE="$resolved" && break 2
            done
        done
    fi
    if [[ -z "$OVMF_VARS_TEMPLATE" ]]; then
        for c in "${candidates_vars[@]}"; do
            for resolved in $c; do
                [[ -f "$resolved" ]] && OVMF_VARS_TEMPLATE="$resolved" && break 2
            done
        done
    fi
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
preflight() {
    if ! command -v qemu-system-x86_64 &>/dev/null; then
        fail "qemu-system-x86_64 not installed"
        return 1
    fi
    pass "qemu-system-x86_64 found"

    if ! command -v qemu-img &>/dev/null; then
        fail "qemu-img not installed"
        return 1
    fi
    pass "qemu-img found"

    autodetect_ovmf
    if [[ -z "$OVMF_CODE" || ! -f "$OVMF_CODE" ]]; then
        fail "OVMF_CODE.fd not found — set OVMF_CODE=/path/to/OVMF_CODE.fd"
        return 1
    fi
    pass "OVMF_CODE: $OVMF_CODE"

    if [[ -z "$OVMF_VARS_TEMPLATE" || ! -f "$OVMF_VARS_TEMPLATE" ]]; then
        fail "OVMF_VARS.fd not found — set OVMF_VARS_TEMPLATE=/path/to/OVMF_VARS.fd"
        return 1
    fi
    pass "OVMF_VARS template: $OVMF_VARS_TEMPLATE"

    mkdir -p "$VM_DIR"
    pass "VM dir: $VM_DIR"

    # KVM acceleration check
    if [[ -r /dev/kvm ]]; then
        pass "/dev/kvm available — using hardware acceleration"
        ACCEL="-enable-kvm -cpu host"
    else
        skip "/dev/kvm not readable — falling back to TCG (slow)"
        ACCEL="-cpu max"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Disk setup
# ---------------------------------------------------------------------------
prepare_disk() {
    if [[ -f "$DISK_IMG" ]]; then
        echo
        echo -e "${T_YELLOW}Disk image already exists: $DISK_IMG${T_NC}"
        read -rp "Recreate from scratch? [y/N]: " yn
        if [[ "$yn" =~ ^[Yy]$ ]]; then
            rm -f "$DISK_IMG"
        else
            pass "reusing existing disk: $(qemu-img info "$DISK_IMG" | grep 'virtual size')"
            return 0
        fi
    fi

    qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE" >/dev/null
    pass "created blank qcow2: $DISK_IMG ($DISK_SIZE)"
}

# ---------------------------------------------------------------------------
# ISO setup
# ---------------------------------------------------------------------------
prepare_iso() {
    if [[ -f "$VOID_ISO" ]]; then
        pass "ISO present: $VOID_ISO"
        return 0
    fi

    if [[ "${SKIP_DOWNLOAD:-0}" == "1" ]]; then
        fail "no ISO at $VOID_ISO and SKIP_DOWNLOAD=1"
        return 1
    fi

    echo
    echo -e "${T_YELLOW}Void Linux live ISO not found.${T_NC}"
    echo "Download URL: $VOID_ISO_URL"
    echo "(Pick a more recent ISO from https://repo-default.voidlinux.org/live/current/ "
    echo " and re-run with VOID_ISO_URL=... to override)"
    read -rp "Download now? [y/N]: " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
        fail "user declined ISO download"
        return 1
    fi

    if command -v curl &>/dev/null; then
        curl -L -o "$VOID_ISO" "$VOID_ISO_URL" || { fail "ISO download failed"; return 1; }
    elif command -v wget &>/dev/null; then
        wget -O "$VOID_ISO" "$VOID_ISO_URL" || { fail "ISO download failed"; return 1; }
    else
        fail "neither curl nor wget available"
        return 1
    fi
    pass "downloaded ISO ($(du -h "$VOID_ISO" | cut -f1))"
}

# ---------------------------------------------------------------------------
# Shared folder setup — exposes voidnx.sh to the VM via 9p virtfs
# ---------------------------------------------------------------------------
prepare_shared_folder() {
    SHARED="$VM_DIR/shared"
    mkdir -p "$SHARED"
    cp "$SCRIPT_UNDER_TEST" "$SHARED/voidnx.sh"
    cp "$TESTS_DIR/04-post-install.sh" "$SHARED/" 2>/dev/null || true
    cp "$TESTS_DIR/lib.sh" "$SHARED/" 2>/dev/null || true
    chmod +x "$SHARED/voidnx.sh"
    pass "shared folder ready: $SHARED (will be mounted at /mnt/host inside VM)"
}

# ---------------------------------------------------------------------------
# Boot the VM
# ---------------------------------------------------------------------------
boot_vm() {
    # Per-instance OVMF_VARS so we don't pollute the template
    local ovmf_vars="$VM_DIR/OVMF_VARS.fd"
    if [[ ! -f "$ovmf_vars" ]]; then
        cp "$OVMF_VARS_TEMPLATE" "$ovmf_vars"
    fi

    cat << EOF

${T_BOLD}${T_CYAN}Launching VM...${T_NC}

Inside the VM (after live ISO boots):

  1. Login as ${T_BOLD}root${T_NC} (default password: ${T_BOLD}voidlinux${T_NC} on most ISOs)
  2. Mount the shared folder:
       ${T_GREEN}mkdir -p /mnt/host${T_NC}
       ${T_GREEN}mount -t 9p -o trans=virtio,version=9p2000.L hostshare /mnt/host${T_NC}
  3. Run the installer:
       ${T_GREEN}cd /mnt/host${T_NC}
       ${T_GREEN}DISK=/dev/vda bash ./voidnx.sh${T_NC}
  4. After install completes, ${T_BOLD}power off${T_NC} the VM (do NOT reboot — see step 5).
  5. Re-run this script with: ${T_GREEN}BOOT_INSTALLED=1 $0${T_NC}
     (it boots the disk without the ISO so you test real boot path).
  6. After first boot, login and run: ${T_GREEN}bash /mnt/host/04-post-install.sh${T_NC}

Press Ctrl+A then X to exit qemu (serial console).
Press Ctrl+Alt+G to release mouse from the GUI window.

EOF
    read -rp "Press Enter to launch (or Ctrl+C to abort)..."

    local cdrom_args=()
    if [[ "${BOOT_INSTALLED:-0}" != "1" ]]; then
        cdrom_args=(-cdrom "$VOID_ISO" -boot order=d)
    else
        pass "BOOT_INSTALLED=1 — booting from disk only (no ISO)"
    fi

    qemu-system-x86_64 \
        $ACCEL \
        -m "$VM_RAM" \
        -smp "$VM_CPUS" \
        -machine q35,smm=on \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$ovmf_vars" \
        -drive file="$DISK_IMG",if=virtio,format=qcow2 \
        "${cdrom_args[@]}" \
        -netdev user,id=n0 \
        -device virtio-net-pci,netdev=n0 \
        -virtfs local,path="$SHARED",mount_tag=hostshare,security_model=mapped-xattr,id=hostshare \
        -display gtk \
        -serial mon:stdio \
        -name "void-fortress-test"

    pass "VM exited (qemu return: $?)"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    preflight || { finish_suite; exit 1; }
    prepare_disk
    if [[ "${BOOT_INSTALLED:-0}" != "1" ]]; then
        prepare_iso || { finish_suite; exit 1; }
    fi
    prepare_shared_folder
    boot_vm

    finish_suite
}

main "$@"
