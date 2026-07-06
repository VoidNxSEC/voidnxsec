#!/usr/bin/env bash
# audit.sh — Run Lynis security audit and emit JSONL report
# Integrates with schema/log-event.json for VoidNxSEC ecosystem
set -euo pipefail

LOG_FILE="/var/log/void-fortress/audit.jsonl"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || uuidgen)"
PID=$$

mkdir -p "$(dirname "$LOG_FILE")"

_emit() {
    local level="$1" phase="$2" msg="$3" extra="${4:-}"
    local ts; ts="$(date -Iseconds)"
    if [[ -n "$extra" ]]; then
        printf '{"ts":"%s","level":"%s","phase":"%s","msg":"%s","pid":%d,"boot_id":"%s",%s}\n' \
            "$ts" "$level" "$phase" "$msg" "$PID" "$BOOT_ID" "$extra" | tee -a "$LOG_FILE"
    else
        printf '{"ts":"%s","level":"%s","phase":"%s","msg":"%s","pid":%d,"boot_id":"%s"}\n' \
            "$ts" "$level" "$phase" "$msg" "$PID" "$BOOT_ID" | tee -a "$LOG_FILE"
    fi
}

[[ $EUID -ne 0 ]] && { echo "must run as root"; exit 1; }
command -v lynis >/dev/null 2>&1 || { echo "lynis not found — install with: nix-env -iA nixpkgs.lynis"; exit 1; }

_emit "STATE" "audit" "lynis audit started"

# Run Lynis audit (quiet mode, capture output)
LYNIS_REPORT="/tmp/lynis-report-$(date +%Y%m%d-%H%M%S).dat"
LYNIS_LOG="/tmp/lynis.log"

lynis audit system \
    --quiet \
    --no-colors \
    --logfile "$LYNIS_LOG" \
    --report-file "$LYNIS_REPORT" \
    2>/dev/null || true

# Extract hardening index score
SCORE=$(grep "^hardening_index=" "$LYNIS_REPORT" 2>/dev/null | cut -d= -f2 || echo "0")
WARNINGS=$(grep -c "^warning\[\]=" "$LYNIS_REPORT" 2>/dev/null || echo "0")
SUGGESTIONS=$(grep -c "^suggestion\[\]=" "$LYNIS_REPORT" 2>/dev/null || echo "0")

# Emit structured result
_emit "INFO" "audit" "lynis complete" \
    "\"lynis_score\":$SCORE,\"warnings\":$WARNINGS,\"suggestions\":$SUGGESTIONS"

# Threshold reporting
if [[ "$SCORE" -ge 90 ]]; then
    _emit "OK"   "audit" "hardening score EXCELLENT (≥90): $SCORE"
elif [[ "$SCORE" -ge 75 ]]; then
    _emit "OK"   "audit" "hardening score GOOD (≥75): $SCORE"
elif [[ "$SCORE" -ge 60 ]]; then
    _emit "WARN" "audit" "hardening score ACCEPTABLE (≥60): $SCORE — review warnings"
else
    _emit "FAIL" "audit" "hardening score LOW (<60): $SCORE — action required"
fi

# Print top warnings
echo ""
echo "=== Top Warnings ==="
grep "^warning\[\]=" "$LYNIS_REPORT" 2>/dev/null | head -10 | sed 's/^warning\[\]=/  [WARN] /' || echo "  None"

echo ""
echo "=== Hardening Index: $SCORE / 100 ==="
echo "    Warnings:    $WARNINGS"
echo "    Suggestions: $SUGGESTIONS"
echo "    Full report: $LYNIS_REPORT"
echo "    JSONL log:   $LOG_FILE"
