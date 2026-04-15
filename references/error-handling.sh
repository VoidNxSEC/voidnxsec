#!/bin/bash
set -Eeo pipefail

# Função de error handling
error_handler() {
    local exit_code=$?
    local line_number=\$1
    local command=\$2
    echo "============================================="
    echo "[FATAL] Erro no script de bootstrap"
    echo "  Linha:   ${line_number}"
    echo "  Comando: ${command}"
    echo "  Exit:    ${exit_code}"
    echo "  Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "============================================="
    # Opcional: dump de estado
    dump_system_state
    exit $exit_code
}

dump_system_state() {
    echo ">>> ESTADO DO SISTEMA NO MOMENTO DO ERRO <<<"
    echo "-- Disk:"
    df -h 2>/dev/null
    echo "-- Memory:"
    free -m 2>/dev/null
    echo "-- Network:"
    ip addr 2>/dev/null || ifconfig 2>/dev/null
    echo "-- Processos:"
    ps aux --sort=-%mem | head -20
    echo "-- Últimas linhas do syslog:"
    tail -30 /var/log/syslog 2>/dev/null || journalctl -n 30 --no-pager
}

trap 'error_handler ${LINENO} "${BASH_COMMAND}"' ERR
