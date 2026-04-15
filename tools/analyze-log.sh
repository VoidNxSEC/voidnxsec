#!/bin/bash
# tools/analyze-log.sh — Análise de logs JSONL

LOG="${1:-/var/log/void-fortress/install.jsonl}"

echo "═══ VOID FORTRESS — Log Analysis ═══"
echo ""

# Timeline resumida
echo "▸ TIMELINE:"
jq -r '[.ts[11:19], .level, .phase, .msg[:60]] | join(" │ ")' "$LOG"
echo ""

# Só erros
echo "▸ ERROS:"
jq -r 'select(.level == "FAIL" or .level == "FATAL" or .level == "ERROR") |
  "  [\(.phase)] \(.msg)" +
  (if .cmd then " → cmd: \(.cmd[:80])" else "" end) +
  (if .stderr then "\n    stderr: \(.stderr[:200])" else "" end)' "$LOG"
echo ""

# Timing por fase
echo "▸ DURAÇÃO POR FASE:"
jq -rs '
  [.[] | select(.level == "STATE")] |
  . as $states |
  range(length - 1) as $i |
  {
    phase: $states[$i].phase,
    duration_s: (($states[$i+1].elapsed_ms - $states[$i].elapsed_ms) / 1000)
  }
' "$LOG" | jq -r '"  \(.phase): \(.duration_s)s"'
echo ""

# Comandos mais lentos
echo "▸ TOP 5 COMANDOS MAIS LENTOS:"
jq -r 'select(.duration_ms != null) |
  "\(.duration_ms)ms │ \(.msg) │ \(.cmd // "N/A" | .[:60])"' "$LOG" |
  sort -rn | head -5 | sed 's/^/  /'
echo ""

# Snapshots de memória ao longo do tempo
echo "▸ MEMÓRIA AO LONGO DA INSTALAÇÃO:"
jq -r 'select(.snapshot != null) |
  "  \(.ts[11:19]) │ \(.reason) │ RAM: \(.snapshot.mem_avail_mb)MB free │ Load: \(.snapshot.load_1m)"' "$LOG"
echo ""

# Resumo final
echo "▸ RESUMO:"
jq -rs '{
  total_events: length,
  errors: [.[] | select(.level == "FAIL" or .level == "FATAL")] | length,
  warnings: [.[] | select(.level == "WARN")] | length,
  commands_run: [.[] | select(.cmd != null)] | length,
  total_duration_s: ((.[length-1].elapsed_ms - .[0].elapsed_ms) / 1000),
  phases: [.[] | select(.level == "STATE") | .phase]
}' "$LOG"
