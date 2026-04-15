#!/bin/bash
# lib/logger.sh — JSONL structured logging para VOID FORTRESS
#
# Formato: uma linha JSON por evento, compatível com:
#   - jq (análise local)
#   - GitHub Actions (annotations)
#   - qualquer log aggregator

# ══════════════════════════════════════════════
# Config
# ══════════════════════════════════════════════
LOG_DIR="${LOG_DIR:-/var/log/void-fortress}"
LOG_JSONL="${LOG_DIR}/install.jsonl"
LOG_HUMAN="${LOG_DIR}/install.log"
LOG_STDERR="${LOG_DIR}/stderr.log"

BOOT_ID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s)"
SESSION_START="$(date -u +%s%3N 2>/dev/null || date -u +%s)"

mkdir -p "$LOG_DIR"

# ══════════════════════════════════════════════
# Core: json_escape + emit
# ══════════════════════════════════════════════
_json_escape() {
    # Escapa strings para JSON sem dependências externas
    local s="\$1"
    s="${s//\\/\\\\}"      # backslash
    s="${s//\"/\\\"}"      # double quote
    s="${s//$'\n'/\\n}"    # newline
    s="${s//$'\r'/\\r}"    # carriage return
    s="${s//$'\t'/\\t}"    # tab
    printf '%s' "$s"
}

_emit_jsonl() {
    local level="\$1"
    local phase="\$2"
    local msg="\$3"
    local extra="${4:-}"  # JSON object extra fields (sem chaves externas)

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

    local elapsed_ms
    local now_ms
    now_ms=$(date -u +%s%3N 2>/dev/null || date -u +%s)
    elapsed_ms=$(( now_ms - SESSION_START ))

    local escaped_msg
    escaped_msg=$(_json_escape "$msg")

    # Monta JSON na mão (zero dependências — nem jq precisa existir)
    local json="{"
    json+="\"ts\":\"${ts}\","
    json+="\"elapsed_ms\":${elapsed_ms},"
    json+="\"level\":\"${level}\","
    json+="\"phase\":\"${phase}\","
    json+="\"msg\":\"${escaped_msg}\","
    json+="\"pid\":$$,"
    json+="\"boot_id\":\"${BOOT_ID}\""

    # Extra fields opcionais
    if [[ -n "$extra" ]]; then
        json+=",${extra}"
    fi

    json+="}"

    # Escrita atômica (append)
    echo "$json" >> "$LOG_JSONL"

    # Human-readable parallel (pra quem tá olhando o terminal)
    local color=""
    local reset="\033[0m"
    case "$level" in
        FATAL|FAIL) color="\033[1;31m" ;;  # vermelho bold
        ERROR)      color="\033[0;31m" ;;  # vermelho
        WARN)       color="\033[0;33m" ;;  # amarelo
        OK)         color="\033[0;32m" ;;  # verde
        SKIP)       color="\033[0;36m" ;;  # cyan
        DEBUG)      color="\033[0;90m" ;;  # cinza
        STATE)      color="\033[1;35m" ;;  # magenta bold
        *)          color="\033[0m"    ;;  # default
    esac

    local human_line
    human_line=$(printf "[%s] [%-5s] [%-15s] %s" "$ts" "$level" "$phase" "$msg")

    # Terminal (colorido)
    printf "${color}%s${reset}\n" "$human_line" >&2

    # Arquivo human (sem cores)
    echo "$human_line" >> "$LOG_HUMAN"
}

# ══════════════════════════════════════════════
# API pública
# ══════════════════════════════════════════════
# Fase atual (setada por cada módulo)
CURRENT_PHASE="init"

log_phase() {
    CURRENT_PHASE="\$1"
    _emit_jsonl "STATE" "$CURRENT_PHASE" "Phase started: ${CURRENT_PHASE}"
}

log_info()  { _emit_jsonl "INFO"  "$CURRENT_PHASE" "$1" "${2:-}"; }
log_ok()    { _emit_jsonl "OK"    "$CURRENT_PHASE" "$1" "${2:-}"; }
log_warn()  { _emit_jsonl "WARN"  "$CURRENT_PHASE" "$1" "${2:-}"; }
log_fail()  { _emit_jsonl "FAIL"  "$CURRENT_PHASE" "$1" "${2:-}"; }
log_fatal() { _emit_jsonl "FATAL" "$CURRENT_PHASE" "$1" "${2:-}"; }
log_debug() { _emit_jsonl "DEBUG" "$CURRENT_PHASE" "$1" "${2:-}"; }
log_skip()  { _emit_jsonl "SKIP"  "$CURRENT_PHASE" "$1" "${2:-}"; }

# ══════════════════════════════════════════════
# Command execution com structured output
# ══════════════════════════════════════════════
log_cmd() {
    local description="\$1"; shift
    local cmd_string="$*"

    local start_ms
    start_ms=$(date -u +%s%3N 2>/dev/null || date -u +%s)

    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)

    local exit_code=0
    "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

    local end_ms
    end_ms=$(date -u +%s%3N 2>/dev/null || date -u +%s)
    local duration_ms=$(( end_ms - start_ms ))

    local stdout_content stderr_content
    stdout_content=$(_json_escape "$(tail -c 4096 "$stdout_file")")
    stderr_content=$(_json_escape "$(tail -c 4096 "$stderr_file")")

    local extra=""
    extra+="\"cmd\":\"$(_json_escape "$cmd_string")\""
    extra+=",\"exit_code\":${exit_code}"
    extra+=",\"duration_ms\":${duration_ms}"
    extra+=",\"stdout\":\"${stdout_content}\""
    extra+=",\"stderr\":\"${stderr_content}\""

    if [[ $exit_code -eq 0 ]]; then
        _emit_jsonl "OK" "$CURRENT_PHASE" "$description" "$extra"
    else
        _emit_jsonl "FAIL" "$CURRENT_PHASE" "$description" "$extra"
        # Stderr também vai pro log de erros dedicado
        cat "$stderr_file" >> "$LOG_STDERR"
    fi

    rm -f "$stdout_file" "$stderr_file"
    return $exit_code
}

# ══════════════════════════════════════════════
# System snapshot (estado do host como JSON)
# ══════════════════════════════════════════════
log_system_snapshot() {
    local reason="${1:-manual}"

    local mem_total mem_avail disk_avail load_1m
    mem_total=$(awk '/MemTotal/{print int(\$2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    mem_avail=$(awk '/MemAvailable/{print int(\$2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
    disk_avail=$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ' || echo 0)
    load_1m=$(awk '{print \$1}' /proc/loadavg 2>/dev/null || echo "0")

    local luks_open=""
    for mapper in /dev/mapper/*_crypt; do
        [[ -b "$mapper" ]] && luks_open+="$(basename "$mapper"),"
    done
    luks_open="${luks_open%,}"

    local mounts_void=""
    mounts_void=$(mount | grep "/mnt/void" | awk '{print \$3}' | tr '\n' ',' || true)
    mounts_void="${mounts_void%,}"

    local extra=""
    extra+="\"reason\":\"$(_json_escape "$reason")\""
    extra+=",\"snapshot\":{"
    extra+="\"mem_total_mb\":${mem_total}"
    extra+=",\"mem_avail_mb\":${mem_avail}"
    extra+=",\"disk_avail_kb\":${disk_avail}"
    extra+=",\"load_1m\":${load_1m}"
    extra+=",\"luks_open\":\"${luks_open}\""
    extra+=",\"mounts_void\":\"${mounts_void}\""
    extra+=",\"uptime_sec\":$(awk '{print int(\$1)}' /proc/uptime 2>/dev/null || echo 0)"
    extra+="}"

    _emit_jsonl "INFO" "$CURRENT_PHASE" "System snapshot" "$extra"
}

# ══════════════════════════════════════════════
# Error handler com context dump
# ══════════════════════════════════════════════
_error_handler_jsonl() {
    local exit_code=$?
    local line_number=\$1
    local bash_command=\$2

    local extra=""
    extra+="\"line\":${line_number}"
    extra+=",\"command\":\"$(_json_escape "$bash_command")\""
    extra+=",\"exit_code\":${exit_code}"
    extra+=",\"bash_source\":\"$(_json_escape "${BASH_SOURCE[1]:-unknown}")\""
    extra+=",\"funcname\":\"$(_json_escape "${FUNCNAME[1]:-main}")\""

    # Stack trace
    local stack=""
    for ((i=1; i<${#FUNCNAME[@]}; i++)); do
        stack+="${BASH_SOURCE[$i]:-?}:${BASH_LINENO[$((i-1))]}:${FUNCNAME[$i]} → "
    done
    stack="${stack% → }"
    extra+=",\"stack\":\"$(_json_escape "$stack")\""

    _emit_jsonl "FATAL" "$CURRENT_PHASE" "Unhandled error" "$extra"

    # Snapshot do sistema no momento do crash
    log_system_snapshot "crash"
}

trap '_error_handler_jsonl ${LINENO} "${BASH_COMMAND}"' ERR
