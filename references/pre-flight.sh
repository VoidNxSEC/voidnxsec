preflight_checks() {
    local errors=0

    # Root check
    if [[ $EUID -ne 0 ]]; then
        log "FAIL" "Script precisa rodar como root"
        ((errors++))
    fi

    # OS check
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        log "INFO" "OS: ${PRETTY_NAME} (ID=${ID}, VERSION=${VERSION_ID})"
        case "$ID" in
            ubuntu|debian|kali) log "INFO" "Distro suportada: ${ID}" ;;
            *) log "WARN" "Distro não testada: ${ID}"; ((errors++)) ;;
        esac
    else
        log "FAIL" "/etc/os-release não encontrado"
        ((errors++))
    fi

    # Conectividade
    if ! ping -c1 -W3 8.8.8.8 &>/dev/null; then
        log "FAIL" "Sem conectividade de rede"
        ((errors++))
    fi

    # DNS
    if ! host github.com &>/dev/null; then
        log "FAIL" "DNS não está resolvendo"
        ((errors++))
    fi

    # Espaço em disco (mínimo 2GB)
    local available_kb
    available_kb=$(df / --output=avail | tail -1 | tr -d ' ')
    if [[ $available_kb -lt 2097152 ]]; then
        log "FAIL" "Espaço insuficiente: $(( available_kb / 1024 ))MB (mínimo: 2048MB)"
        ((errors++))
    fi

    # Memória (mínimo 512MB)
    local mem_mb
    mem_mb=$(awk '/MemTotal/ {print int(\$2/1024)}' /proc/meminfo)
    if [[ $mem_mb -lt 512 ]]; then
        log "FAIL" "Memória insuficiente: ${mem_mb}MB (mínimo: 512MB)"
        ((errors++))
    fi

    if [[ $errors -gt 0 ]]; then
        log "FATAL" "Preflight failed com ${errors} erro(s)"
        return 1
    fi

    log "OK" "Todas as pré-condições satisfeitas"
    return 0
}
