# Just a file for reference.
# Acompanhar em tempo real (tipo tail -f mas estruturado)
tail -f /var/log/void-fortress/install.jsonl | jq -r '
  "\(.ts[11:19]) [\(.level)] \(.phase): \(.msg)"'

# Só erros, em tempo real
tail -f install.jsonl | jq -r 'select(.level=="FAIL" or .level=="FATAL")'

# Timeline de quanto cada comando demorou
jq -r 'select(.duration_ms) |
  "\(.duration_ms | tostring | (6 - length) * " " + .)ms │ \(.msg)"' install.jsonl

# Diff entre duas runs (comparar boot_ids)
diff <(jq -r 'select(.boot_id=="abc") | .msg' install.jsonl) \
     <(jq -r 'select(.boot_id=="def") | .msg' install.jsonl)

# Exportar pra CSV (pra Excel/Sheets)
jq -r '[.ts, .level, .phase, .msg, (.duration_ms // 0 | tostring)] | @csv' \
  install.jsonl > install.csv

# Quantas vezes cada fase foi tentada (detecta re-runs)
jq -r 'select(.level=="STATE") | .phase' install.jsonl | sort | uniq -c | sort -rn
