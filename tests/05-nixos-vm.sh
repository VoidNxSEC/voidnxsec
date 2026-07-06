#!/usr/bin/env bash
# tests/05-nixos-vm.sh — NixOS bootstrap validation in QEMU VM
#
# Two test modes:
#   eval   (default in CI) — nix flake check + dry-build, no VM required
#   vm     (local/self-hosted) — full nixos-anywhere VM install + boot check
#
# Prerequisites for eval mode:
#   - nix (with flakes enabled)
#
# Prerequisites for vm mode:
#   - nix, qemu-system-x86_64, OVMF firmware, KVM (optional but strongly recommended)
#   - nixos-anywhere available in nix path
#
# Usage:
#   tests/05-nixos-vm.sh              # eval mode (default)
#   TEST_MODE=vm tests/05-nixos-vm.sh # full VM install
#   PROFILE=server tests/05-nixos-vm.sh
#   PROFILE=laptop tests/05-nixos-vm.sh

set -euo pipefail
IFS=$'\n\t'

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"
VM_DIR="${VM_DIR:-$TESTS_DIR/.vm-nixos}"
TEST_MODE="${TEST_MODE:-eval}"
PROFILE="${PROFILE:-server}"
DISK_SIZE="${DISK_SIZE:-20G}"
VM_RAM="${VM_RAM:-4096}"
VM_CPUS="${VM_CPUS:-2}"
LUKS_PASS="${LUKS_PASS:-voidnx-test-pass-1234}"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; FAIL=0; SKIP=0

pass() { echo -e "${GREEN}  [PASS]${NC} $1"; (( PASS++ )); }
fail() { echo -e "${RED}  [FAIL]${NC} $1"; (( FAIL++ )); }
skip() { echo -e "${YELLOW}  [SKIP]${NC} $1"; (( SKIP++ )); }
info() { echo -e "${CYAN}  [INFO]${NC} $1"; }
section() { echo -e "\n${BOLD}── $1 ──${NC}"; }

finish() {
    echo ""
    echo -e "${BOLD}Results: ${GREEN}$PASS passed${NC} / ${RED}$FAIL failed${NC} / ${YELLOW}$SKIP skipped${NC}"
    [[ $FAIL -eq 0 ]]
}

# ── OVMF autodetect (shared with tests/03-vm-bootstrap.sh) ────────────────

autodetect_ovmf() {
    local candidates_code=(
        /run/libvirt/nix-ovmf/OVMF_CODE.fd
        /usr/share/OVMF/OVMF_CODE.fd
        /usr/share/OVMF/OVMF_CODE_4M.fd
        /usr/share/edk2/x64/OVMF_CODE.fd
        /usr/share/edk2-ovmf/x64/OVMF_CODE.fd
    )
    local candidates_vars=(
        /run/libvirt/nix-ovmf/OVMF_VARS.fd
        /usr/share/OVMF/OVMF_VARS.fd
        /usr/share/OVMF/OVMF_VARS_4M.fd
        /usr/share/edk2/x64/OVMF_VARS.fd
        /usr/share/edk2-ovmf/x64/OVMF_VARS.fd
    )
    for p in "${candidates_code[@]}"; do
        [[ -f "$p" ]] && { OVMF_CODE="$p"; break; }
    done
    # Also try nix store
    if [[ -z "${OVMF_CODE:-}" ]]; then
        OVMF_CODE=$(find /nix/store -maxdepth 4 -name "OVMF_CODE.fd" 2>/dev/null | head -1 || true)
    fi
    for p in "${candidates_vars[@]}"; do
        [[ -f "$p" ]] && { OVMF_VARS_TEMPLATE="$p"; break; }
    done
    if [[ -z "${OVMF_VARS_TEMPLATE:-}" ]]; then
        OVMF_VARS_TEMPLATE=$(find /nix/store -maxdepth 4 -name "OVMF_VARS.fd" 2>/dev/null | head -1 || true)
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# MODE: eval — fast nix evaluation (CI-safe, no VM)
# ═══════════════════════════════════════════════════════════════════════════

run_eval_tests() {
    section "NixOS Eval Tests (no VM)"
    info "Profile: voidnx-$PROFILE | Repo: $REPO_DIR"

    cd "$REPO_DIR"

    # 1. nix flake check (evaluates all outputs, catches import errors)
    info "Running nix flake check..."
    if nix flake check --no-build 2>/tmp/nixos-eval.log; then
        pass "nix flake check passed"
    else
        fail "nix flake check failed"
        cat /tmp/nixos-eval.log >&2
    fi

    # 2. Check nixosConfigurations exist
    info "Checking nixosConfigurations outputs..."
    if nix eval .#nixosConfigurations.voidnx-server.config.system.build.toplevel.drvPath \
        --no-update-lock-file 2>/tmp/nixos-eval.log; then
        pass "voidnx-server config evaluates"
    else
        fail "voidnx-server config evaluation failed"
        cat /tmp/nixos-eval.log >&2
    fi

    if nix eval .#nixosConfigurations.voidnx-laptop.config.system.build.toplevel.drvPath \
        --no-update-lock-file 2>/tmp/nixos-eval.log; then
        pass "voidnx-laptop config evaluates"
    else
        fail "voidnx-laptop config evaluation failed"
        cat /tmp/nixos-eval.log >&2
    fi

    # 3. disko dry-run (validates partition config syntax)
    info "Validating disko partition config for $PROFILE..."
    if nix eval ".#nixosConfigurations.voidnx-${PROFILE}.config.disko.devices" \
        --no-update-lock-file >/dev/null 2>/tmp/nixos-eval.log; then
        pass "disko config for voidnx-$PROFILE is valid"
    else
        fail "disko config for voidnx-$PROFILE failed"
        cat /tmp/nixos-eval.log >&2
    fi

    # 4. Check Lanzaboote is enabled
    info "Checking Lanzaboote (Secure Boot) enabled..."
    LB=$(nix eval ".#nixosConfigurations.voidnx-${PROFILE}.config.boot.lanzaboote.enable" \
        --no-update-lock-file 2>/dev/null || echo "false")
    if [[ "$LB" == "true" ]]; then
        pass "Lanzaboote enabled on voidnx-$PROFILE"
    else
        fail "Lanzaboote NOT enabled on voidnx-$PROFILE"
    fi

    # 5. Check systemd initrd (required for TPM2)
    info "Checking systemd initrd..."
    SINITRD=$(nix eval ".#nixosConfigurations.voidnx-${PROFILE}.config.boot.initrd.systemd.enable" \
        --no-update-lock-file 2>/dev/null || echo "false")
    if [[ "$SINITRD" == "true" ]]; then
        pass "systemd initrd enabled (TPM2 unlock possible)"
    else
        fail "systemd initrd NOT enabled"
    fi

    # 6. Check AppArmor
    info "Checking AppArmor..."
    AA=$(nix eval ".#nixosConfigurations.voidnx-${PROFILE}.config.security.apparmor.enable" \
        --no-update-lock-file 2>/dev/null || echo "false")
    if [[ "$AA" == "true" ]]; then
        pass "AppArmor enabled"
    else
        fail "AppArmor NOT enabled"
    fi

    # 7. Check impermanence root is tmpfs
    info "Checking impermanence (root-as-tmpfs)..."
    ROOTFS=$(nix eval ".#nixosConfigurations.voidnx-${PROFILE}.config.fileSystems.\"/\".fsType" \
        --no-update-lock-file 2>/dev/null | tr -d '"' || echo "unknown")
    if [[ "$ROOTFS" == "tmpfs" ]]; then
        pass "Root filesystem is tmpfs (impermanence active)"
    else
        fail "Root filesystem is '$ROOTFS' — expected tmpfs"
    fi

    # 8. Lint scripts
    section "Script Linting"
    for script in "$REPO_DIR"/scripts/*.sh; do
        if bash -n "$script" 2>/tmp/lint.log; then
            pass "syntax ok: $(basename "$script")"
        else
            fail "syntax error: $(basename "$script")"
            cat /tmp/lint.log >&2
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# MODE: vm — full QEMU install via nixos-anywhere
# ═══════════════════════════════════════════════════════════════════════════

run_vm_tests() {
    section "NixOS VM Tests (QEMU + nixos-anywhere)"
    info "Profile: voidnx-$PROFILE | Disk: $DISK_SIZE | RAM: ${VM_RAM}MB"

    # Prerequisites
    local missing=()
    command -v nix              >/dev/null 2>&1 || missing+=("nix")
    command -v qemu-system-x86_64 >/dev/null 2>&1 || missing+=("qemu-system-x86_64")

    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "Missing prerequisites: ${missing[*]}"
        info "Install with: nix-shell -p ${missing[*]}"
        finish
        return
    fi

    autodetect_ovmf
    if [[ -z "${OVMF_CODE:-}" ]]; then
        skip "OVMF firmware not found — skipping VM test"
        info "Install with: nix-shell -p OVMF"
        finish
        return
    fi

    pass "OVMF found: $OVMF_CODE"

    # Create VM workspace
    mkdir -p "$VM_DIR"
    DISK_IMG="$VM_DIR/nixos-test-${PROFILE}.qcow2"
    OVMF_VARS="$VM_DIR/OVMF_VARS_${PROFILE}.fd"
    cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"

    # Create test disk
    info "Creating ${DISK_SIZE} qcow2 disk..."
    qemu-img create -f qcow2 "$DISK_IMG" "$DISK_SIZE" >/dev/null
    pass "Disk created: $DISK_IMG"

    # Write LUKS passphrase for non-interactive use
    printf '%s' "$LUKS_PASS" > /tmp/luks-pass-test
    chmod 600 /tmp/luks-pass-test

    # nixos-anywhere VM test
    # Starts a QEMU VM, runs disko + NixOS install, validates success
    info "Running nixos-anywhere --vm-test for voidnx-$PROFILE..."
    info "(This will take 5-15 minutes on first run — nix builds the closure)"

    local vm_log="$VM_DIR/vm-install-${PROFILE}.log"

    # nixos-anywhere --vm-test uses an internal QEMU VM
    # it doesn't need an external disk or boot sequence — it's self-contained
    if nix run github:nix-community/nixos-anywhere -- \
        --flake "$REPO_DIR#voidnx-$PROFILE" \
        --vm-test \
        --disk-encryption-keys "/tmp/luks-pass" /tmp/luks-pass-test \
        2>&1 | tee "$vm_log" | grep -E "(phase|PASS|FAIL|error|ERROR|done)" ; then
        pass "nixos-anywhere --vm-test succeeded for voidnx-$PROFILE"
    else
        fail "nixos-anywhere --vm-test FAILED for voidnx-$PROFILE"
        info "Full log: $vm_log"
    fi

    # Cleanup sensitive data
    rm -f /tmp/luks-pass-test

    # Validate installed disk image boots (optional — boot check)
    if [[ "${BOOT_CHECK:-0}" == "1" ]]; then
        section "Boot Check (QEMU)"
        info "Booting installed system — checking it reaches login prompt..."

        local kvm_flag=""
        [[ -e /dev/kvm ]] && kvm_flag="-enable-kvm"

        timeout 120 qemu-system-x86_64 \
            $kvm_flag \
            -m "$VM_RAM" \
            -smp "$VM_CPUS" \
            -drive file="$DISK_IMG",format=qcow2,if=virtio \
            -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
            -drive if=pflash,format=raw,file="$OVMF_VARS" \
            -nographic \
            -serial file:"$VM_DIR/serial-${PROFILE}.log" \
            -no-reboot \
            2>/dev/null &
        local qemu_pid=$!

        # Wait for boot and check for login prompt in serial log
        local boot_ok=false
        for _ in $(seq 1 24); do
            sleep 5
            if grep -q "login:" "$VM_DIR/serial-${PROFILE}.log" 2>/dev/null; then
                boot_ok=true
                break
            fi
        done

        kill "$qemu_pid" 2>/dev/null || true

        if $boot_ok; then
            pass "System booted and reached login prompt"
        else
            fail "System did not reach login prompt within 120s"
        fi
    else
        skip "Boot check skipped (set BOOT_CHECK=1 to enable)"
    fi

    info "VM artifacts: $VM_DIR/"
}

# ── Entry point ─────────────────────────────────────────────────────────────

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   VoidNxSEC — NixOS Bootstrap Tests (suite 05)          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  Mode:    $TEST_MODE"
echo "  Profile: voidnx-$PROFILE"

case "$TEST_MODE" in
    eval) run_eval_tests ;;
    vm)   run_eval_tests; run_vm_tests ;;
    *)    echo "Unknown TEST_MODE: $TEST_MODE (use 'eval' or 'vm')"; exit 1 ;;
esac

finish
