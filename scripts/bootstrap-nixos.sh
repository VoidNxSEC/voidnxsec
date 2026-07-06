#!/usr/bin/env bash
# bootstrap-nixos.sh — VoidNxSEC NixOS bootstrap cirúrgico
# Deploys voidnx-server or voidnx-laptop via nixos-anywhere + disko
# Emits JSONL events compatible with schema/log-event.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/voidnx-nixos-bootstrap.jsonl"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || uuidgen)"
SESSION_START="$(date -Iseconds)"
PID=$$

# ── JSONL logging (compatible with schema/log-event.json) ──────────────────

_emit() {
    local level="$1" phase="$2" msg="$3"
    local elapsed=$(( $(date +%s%3N) - $(date -d "$SESSION_START" +%s%3N 2>/dev/null || echo 0) ))
    printf '{"ts":"%s","level":"%s","phase":"%s","msg":"%s","pid":%d,"boot_id":"%s","elapsed_ms":%d}\n' \
        "$(date -Iseconds)" "$level" "$phase" "$msg" "$PID" "$BOOT_ID" "$elapsed" \
        | tee -a "$LOG_FILE"
}

log_info()  { _emit "INFO"  "$PHASE" "$1"; echo "  [INFO]  $1" >&2; }
log_ok()    { _emit "OK"    "$PHASE" "$1"; echo "  [ OK ]  $1" >&2; }
log_warn()  { _emit "WARN"  "$PHASE" "$1"; echo "  [WARN]  $1" >&2; }
log_fail()  { _emit "FAIL"  "$PHASE" "$1"; echo "  [FAIL]  $1" >&2; }
log_fatal() { _emit "FATAL" "$PHASE" "$1"; echo "  [FATAL] $1" >&2; exit 1; }

# ── Preflight checks ───────────────────────────────────────────────────────

PHASE="preflight"
_emit "STATE" "$PHASE" "bootstrap started"

[[ $EUID -ne 0 ]] && log_fatal "must run as root"
[[ -d "$REPO_DIR/nixos" ]] || log_fatal "nixos/ directory not found — run from repo root"

command -v nix      >/dev/null 2>&1 || log_fatal "nix not found"
command -v ssh      >/dev/null 2>&1 || log_fatal "ssh not found"
command -v age      >/dev/null 2>&1 || log_warn  "age not found — sops secrets won't work"

log_ok "preflight passed"

# ── Target selection ───────────────────────────────────────────────────────

PHASE="target-select"

usage() {
    cat >&2 <<EOF
Usage: $0 <profile> <target-host> [options]

  Profiles:
    server   Deploy voidnx-server (headless, sda/nvme)
    laptop   Deploy voidnx-laptop (NVMe, TPM2 + hibernate)

  Target:
    IP or hostname reachable via SSH as root (nixos live ISO or kexec)

  Options:
    --disk DEVICE     Override disk device (default: server=/dev/sda, laptop=/dev/nvme0n1)
    --luks-pass FILE  File containing LUKS passphrase (default: prompts interactively)
    --dry-run         Show what would happen without executing

  Examples:
    $0 server 192.168.1.10
    $0 laptop 192.168.1.20 --disk /dev/nvme0n1 --luks-pass /tmp/pass
EOF
    exit 1
}

[[ $# -lt 2 ]] && usage

PROFILE="${1:-}"
TARGET_HOST="${2:-}"
DISK=""
LUKS_PASS_FILE=""
DRY_RUN=false

shift 2
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)       DISK="$2";          shift 2 ;;
        --luks-pass)  LUKS_PASS_FILE="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true;        shift   ;;
        *)            log_fatal "unknown option: $1" ;;
    esac
done

case "$PROFILE" in
    server) [[ -z "$DISK" ]] && DISK="/dev/sda"      ;;
    laptop) [[ -z "$DISK" ]] && DISK="/dev/nvme0n1"  ;;
    *)      log_fatal "unknown profile: $PROFILE (use 'server' or 'laptop')" ;;
esac

FLAKE_TARGET="$REPO_DIR#voidnx-$PROFILE"

log_info "profile:     $PROFILE"
log_info "target host: $TARGET_HOST"
log_info "disk device: $DISK"
log_info "flake:       $FLAKE_TARGET"
log_info "dry-run:     $DRY_RUN"

# ── LUKS passphrase ────────────────────────────────────────────────────────

PHASE="luks-setup"

if [[ -z "$LUKS_PASS_FILE" ]]; then
    log_info "LUKS passphrase not provided via --luks-pass, prompting..."
    LUKS_PASS_TMP=$(mktemp)
    trap 'rm -f "$LUKS_PASS_TMP"' EXIT
    read -rsp "Enter LUKS passphrase: " LUKS_PASS; echo
    read -rsp "Confirm LUKS passphrase: " LUKS_PASS_CONFIRM; echo
    [[ "$LUKS_PASS" != "$LUKS_PASS_CONFIRM" ]] && log_fatal "passphrases do not match"
    printf '%s' "$LUKS_PASS" > "$LUKS_PASS_TMP"
    unset LUKS_PASS LUKS_PASS_CONFIRM
    LUKS_PASS_FILE="$LUKS_PASS_TMP"
fi

[[ -f "$LUKS_PASS_FILE" ]] || log_fatal "LUKS pass file not found: $LUKS_PASS_FILE"
log_ok "LUKS passphrase ready"

# ── Deploy via nixos-anywhere ──────────────────────────────────────────────

PHASE="deploy"

NIXOS_ANYWHERE_ARGS=(
    --flake "$FLAKE_TARGET"
    --target-host "root@$TARGET_HOST"
    --disk-encryption-keys "/tmp/luks-pass" "$LUKS_PASS_FILE"
    --extra-files "$REPO_DIR/secrets"
)

if $DRY_RUN; then
    log_info "DRY-RUN: would execute nixos-anywhere with args:"
    printf '  %s\n' "${NIXOS_ANYWHERE_ARGS[@]}" >&2
    _emit "STATE" "$PHASE" "dry-run complete"
    exit 0
fi

log_info "deploying $PROFILE to $TARGET_HOST via nixos-anywhere..."
_emit "STATE" "$PHASE" "nixos-anywhere starting"

nix run github:nix-community/nixos-anywhere -- "${NIXOS_ANYWHERE_ARGS[@]}"

log_ok "nixos-anywhere deploy complete"
_emit "STATE" "$PHASE" "deploy complete"

# ── Post-deploy instructions ───────────────────────────────────────────────

PHASE="post-deploy"

cat >&2 <<EOF

  Deploy complete. Next steps:

  1. Wait for the system to reboot and come online
  2. Enroll TPM2 for LUKS auto-unlock (run after first boot):
       ssh nx@$TARGET_HOST 'sudo bash /etc/nixos/scripts/enroll-tpm.sh'

  3. Enroll Secure Boot keys:
       ssh nx@$TARGET_HOST 'sudo sbctl create-keys && sudo sbctl enroll-keys --microsoft'

  4. Reboot into UEFI, enable Secure Boot, then verify:
       ssh nx@$TARGET_HOST 'sbctl verify && sbctl status'

  5. Run Lynis audit:
       ssh nx@$TARGET_HOST 'sudo lynis audit system'

  JSONL log: $LOG_FILE
EOF

_emit "OK" "$PHASE" "bootstrap complete — follow post-deploy steps"
