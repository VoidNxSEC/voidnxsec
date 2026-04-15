CHECKPOINT_DIR="/var/lib/bootstrap/checkpoints"
mkdir -p "$CHECKPOINT_DIR"

checkpoint_done() {
    local step=\$1
    [[ -f "${CHECKPOINT_DIR}/${step}.done" ]]
}

checkpoint_set() {
    local step=\$1
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "${CHECKPOINT_DIR}/${step}.done"
    log "INFO" "Checkpoint salvo: ${step}"
}

run_step() {
    local step_name=\$1; shift
    local step_func=\$1; shift

    if checkpoint_done "$step_name"; then
        log "SKIP" "Step '${step_name}' já executado — pulando"
        return 0
    fi

    log "INFO" "=== Iniciando step: ${step_name} ==="
    if $step_func "$@"; then
        checkpoint_set "$step_name"
        log "OK" "=== Step '${step_name}' concluído ==="
    else
        log "FAIL" "=== Step '${step_name}' FALHOU ==="
        return 1
    fi
}

# Uso:
step_install_packages() {
    apt-get update -y && apt-get install -y curl wget git build-essential
}

step_configure_firewall() {
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw --force enable
}

run_step "01-install-packages" step_install_packages
run_step "02-configure-firewall" step_configure_firewall
# Se falhar no step 02, re-executar o script retoma do step 02
