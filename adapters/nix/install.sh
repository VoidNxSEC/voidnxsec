#!/usr/bin/env bash
# =============================================================================
# adapters/nix/install.sh — NixOS adapter driver for the VoidNxSEC framework
# =============================================================================
# Maps the canonical framework pipeline onto NixOS (disko + nixos-install):
#
#   preflight → disk-setup → mount → base-install → chroot-setup
#             → bootloader → finalize
#
# Each phase runs: pre-validator → phase module → post-validator. Every event
# is emitted as JSONL via lib/logger_v2.sh (schema/log-event.json), the phase
# progress is persisted so `resume` continues where a run stopped, and a
# failure tears the mounts down via rollback.
#
# Usage:
#   sudo bash adapters/nix/install.sh                 # fresh install
#   sudo bash adapters/nix/install.sh resume          # continue after interruption
#   sudo bash adapters/nix/install.sh status          # read-only: disk/mounts/state
#   sudo bash adapters/nix/install.sh debug           # read-only: env + state detect
#   sudo bash adapters/nix/install.sh clean           # unmount + close crypt mappers
#
# Environment:
#   DISK        target disk (default: auto-detect nvme0n1 > sda > vda)
#   HOST        host in nixos/hosts/<HOST> + flake attribute (default: kernelcore)
#   FLAKE_URI   flake path (default: repo root)
#   FLAKE_ATTR  flake nixosConfigurations attribute (default: HOST, fallback voidnx-HOST)
#   LUKS_PASS   LUKS passphrase (alternative: --luks-pass FILE or interactive)
#   DRY_RUN     true = simulate without applying
#   SKIP_VALIDATION  true = skip pre/post validators
#   AUTO_REBOOT true = reboot after successful finalize
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTER_DIR="$SCRIPT_DIR"
REPO_DIR="$(cd "$ADAPTER_DIR/../.." && pwd)"

# ── Framework libs (distro-agnostic) ──────────────────────────────────────────

# shellcheck source=../../lib/logger_v2.sh
. "$REPO_DIR/lib/logger_v2.sh"
# shellcheck source=./validators.sh
. "$ADAPTER_DIR/validators.sh"
# shellcheck source=../../lib/state.sh
. "$REPO_DIR/lib/state.sh" # NixOS state machine (detect/save)
# shellcheck source=../../lib/rollback.sh
. "$REPO_DIR/lib/rollback.sh" # generation rollback helpers (used post-boot)

# ── Phase modules (function definitions only) ─────────────────────────────────

# shellcheck source=modules/00-preflight.sh
. "$ADAPTER_DIR/modules/00-preflight.sh"
# shellcheck source=modules/01-disk-setup.sh
. "$ADAPTER_DIR/modules/01-disk-setup.sh"
# shellcheck source=modules/02-mount.sh
. "$ADAPTER_DIR/modules/02-mount.sh"
# shellcheck source=modules/03-base-install.sh
. "$ADAPTER_DIR/modules/03-base-install.sh"
# shellcheck source=modules/04-chroot-setup.sh
. "$ADAPTER_DIR/modules/04-chroot-setup.sh"
# shellcheck source=modules/05-bootloader.sh
. "$ADAPTER_DIR/modules/05-bootloader.sh"
# shellcheck source=modules/06-finalize.sh
. "$ADAPTER_DIR/modules/06-finalize.sh"

# ── Configuration ──────────────────────────────────────────────────────────────

DISK="${DISK:-}"
HOST="${HOST:-kernelcore}"
FLAKE_URI="${FLAKE_URI:-$REPO_DIR}"
FLAKE_ATTR="${FLAKE_ATTR:-}"
LUKS_PASS="${LUKS_PASS:-}"
LUKS_PASS_FILE=""
DRY_RUN="${DRY_RUN:-false}"
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
AUTO_REBOOT="${AUTO_REBOOT:-false}"
PHASE_FILE="${PHASE_FILE:-/tmp/voidnx-nix.state}"

# Canonical pipeline (order matters)
PHASES=(preflight disk-setup mount base-install chroot-setup bootloader finalize)

# ── Colors ─────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

banner() {
    echo -e "${BOLD}${CYAN}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════╗
║   VOIDNXSEC — NixOS Adapter (disko + nixos-install)   ║
║   preflight → disk → mount → install → chroot → boot  ║
╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

info() { echo -e "${CYAN}  → $*${NC}"; }
warn_cli() { echo -e "${YELLOW}  [WARN] $*${NC}"; }

# ── Helpers ────────────────────────────────────────────────────────────────────

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}  [DRY] $*${NC}"
        return 0
    fi
    log_cmd "$1" "${@:2}"
}

phase_is_done() { grep -q "^PHASE_$1=done$" "$PHASE_FILE" 2>/dev/null; }

mark_phase_done() {
    [[ "$DRY_RUN" == "true" ]] && return 0 # dry runs must not record progress
    mkdir -p "$(dirname "$PHASE_FILE")"
    grep -q "^PHASE_$1=done$" "$PHASE_FILE" 2>/dev/null \
        || echo "PHASE_$1=done" >> "$PHASE_FILE"
}

# Rollback = teardown of the live install environment (pre-boot counterpart of
# lib/rollback.sh, which only applies to an installed NixOS).
rollback_teardown() {
    local reason="${1:-failure}"
    log_warn "rolling back live environment (reason: $reason)"
    run "unmounting /mnt recursively" umount -R /mnt || true
    for mapper in cryptroot root_crypt swap_crypt cryptswap; do
        if [[ -b "/dev/mapper/$mapper" ]]; then
            run "closing /dev/mapper/$mapper" cryptsetup close "$mapper" || true
        fi
    done
    log_ok "teardown complete"
}

run_phase() {
    local phase="$1"
    local fn="run_${phase//-/_}"

    if phase_is_done "$phase" && [[ "$RESUME" == "true" ]]; then
        log_skip "phase $phase already completed — skipping (resume)"
        return 0
    fi

    log_phase "$phase"

    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        local pre="validate_pre_${phase//-/_}"
        if declare -F "$pre" > /dev/null; then
            log_info "running pre-validator: $pre"
            "$pre" || { log_fatal "pre-validator $pre failed"; rollback_teardown "validator failure"; exit 1; }
        fi
    fi

    if ! declare -F "$fn" > /dev/null; then
        log_fatal "phase function $fn not defined"
        exit 1
    fi

    "$fn" || { log_fail "phase $phase failed"; rollback_teardown "phase failure"; exit 1; }

    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        local post="validate_post_${phase//-/_}"
        if declare -F "$post" > /dev/null; then
            log_info "running post-validator: $post"
            "$post" || { log_fatal "post-validator $post failed"; rollback_teardown "validator failure"; exit 1; }
        fi
    fi

    mark_phase_done "$phase"
    log_ok "phase $phase complete"
}

# ── Subcommands ────────────────────────────────────────────────────────────────

cmd_status() {
    log_phase "status"
    info "Target disk: ${DISK:-<not set>}"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$DISK" 2>/dev/null || warn_cli "disk $DISK not visible"
    info "Open mappers:"
    local found=""
    local m
    shopt -s nullglob
    for m in /dev/mapper/*; do
        [[ "${m##*/}" != "control" ]] && found+="${m##*/} "
    done
    shopt -u nullglob
    [[ -n "$found" ]] && echo "$found" || echo "  (none)"
    info "Mounts under /mnt:"
    findmnt -R /mnt 2>/dev/null || echo "  (none)"
    info "Phase progress ($PHASE_FILE):"
    cat "$PHASE_FILE" 2>/dev/null || echo "  (no state yet — nothing completed)"
    save_nixos_state "$(detect_nixos_state)"
}

cmd_debug() {
    log_phase "debug"
    info "REPO_DIR=$REPO_DIR"
    info "HOST=$HOST FLAKE_URI=$FLAKE_URI FLAKE_ATTR=${FLAKE_ATTR:-<auto>}"
    info "DISK=$DISK DRY_RUN=$DRY_RUN"
    info "UEFI: $([ -d /sys/firmware/efi ] && echo yes || echo no)"
    info "nix: $(command -v nix || echo 'NOT FOUND')"
    info "NixOS state: $(detect_nixos_state)"
}

cmd_clean() {
    log_phase "clean"
    rollback_teardown "manual clean"
    rm -f "$PHASE_FILE"
    log_ok "clean done — state file removed"
}

usage() {
    cat << EOF
VoidNxSEC — NixOS adapter

Usage: sudo bash adapters/nix/install.sh [command]

Commands:
  (default)      Run the full phase pipeline (fresh)
  resume         Continue from the last completed phase
  status         Read-only: disk, mappers, mounts, phase progress
  debug          Read-only: environment + NixOS state detection
  clean          Unmount /mnt and close crypt mappers

Environment:
  DISK        Target disk (default: auto-detect)
  HOST        Host name — nixos/hosts/<HOST> + flake attr (default: kernelcore)
  FLAKE_URI   Flake path (default: repo root)
  FLAKE_ATTR  Override flake nixosConfigurations attribute
  LUKS_PASS   LUKS passphrase (or use --luks-pass FILE)
  DRY_RUN     true = simulate
  AUTO_REBOOT true = reboot after finalize

Examples:
  sudo bash adapters/nix/install.sh
  HOST=laptop DISK=/dev/nvme0n1 sudo bash adapters/nix/install.sh
  sudo bash adapters/nix/install.sh --luks-pass /tmp/pass
  DRY_RUN=true sudo bash adapters/nix/install.sh
EOF
    exit 0
}

# ── Argument parsing ───────────────────────────────────────────────────────────

COMMAND="install"
RESUME=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)            usage ;;
        install)              COMMAND="install"; shift ;;
        resume)               COMMAND="install"; RESUME=true; shift ;;
        status)               COMMAND="status"; shift ;;
        debug)                COMMAND="debug"; shift ;;
        clean)                COMMAND="clean"; shift ;;
        --luks-pass)          LUKS_PASS_FILE="${2:?--luks-pass requires a file}"; shift 2 ;;
        *)                    echo "unknown argument: $1" >&2; usage ;;
    esac
done

# ── Main ───────────────────────────────────────────────────────────────────────

banner

case "$COMMAND" in
    status) cmd_status; exit 0 ;;
    debug)  cmd_debug;  exit 0 ;;
    clean)  cmd_clean;  exit 0 ;;
esac

# install (fresh or resume) — heavy validation lives in the preflight module
log_phase "bootstrap"
log_info "adapter=$ADAPTER_DIR repo=$REPO_DIR"
log_info "command=install resume=$RESUME dry_run=$DRY_RUN"

for phase in "${PHASES[@]}"; do
    run_phase "$phase"
done

log_ok "all phases complete"
