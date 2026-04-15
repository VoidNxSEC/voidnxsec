LOG_FILE="/var/log/bootstrap-$(date +%Y%m%d-%H%M%S).log"

log() {
    local level=\$1; shift
    local msg="$*"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf "[%s] [%s] [PID:%s] %s\n" "$timestamp" "$level" "$$" "$msg" | tee -a "$LOG_FILE"
}

log_cmd() {
    # Executa comando com logging automático de stdout/stderr
    local description=\$1; shift
    log "INFO" "Executando: ${description}"
    log "DEBUG" "Comando: $*"

    local output
    local exit_code
    output=$("$@" 2>&1) && exit_code=$? || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log "OK" "${description} concluído (exit: ${exit_code})"
    else
        log "FAIL" "${description} falhou (exit: ${exit_code})"
        log "STDERR" "$output"
    fi

    echo "$output"
    return $exit_code
}

# Uso:
log_cmd "Atualizando pacotes" apt-get update -y
log_cmd "Instalando dependências" apt-get install -y curl wget git
