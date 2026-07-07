#!/usr/bin/env bash
# =============================================================================
# VOIDNXSEC — NixOS Nuclear Install
# =============================================================================
# Roda a partir do NixOS minimal ISO (ou qualquer live env com nix).
# Fluxo: disko (particiona + LUKS2) → nixos-install --flake
#
# Uso rápido:
#   export DISK=/dev/nvme0n1
#   export HOST=kernelcore
#   bash nixos-bootstrap.sh
#
# Variáveis opcionais:
#   LUKS_PASS   — passphrase LUKS (se vazio, pede interativamente)
#   FLAKE_URI   — URI do flake (padrão: repo local ou github)
#   DRY_RUN     — true para simular sem aplicar
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Configuração ──────────────────────────────────────────────────────────────

DISK="${DISK:-}"
HOST="${HOST:-kernelcore}"
LUKS_PASS="${LUKS_PASS:-}"
DRY_RUN="${DRY_RUN:-false}"
LOG_FILE="/tmp/nixos-bootstrap.log"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_URI="${FLAKE_URI:-$SCRIPT_DIR}"

# ── Cores ─────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Log ───────────────────────────────────────────────────────────────────────

log()     { echo -e "${GREEN}[$(date +'%H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN] $*${NC}" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR] $*${NC}" | tee -a "$LOG_FILE"; exit 1; }
info()    { echo -e "${CYAN}  → $*${NC}"; }
dry_run() { echo -e "${YELLOW}  [DRY] $*${NC}"; }

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run "$*"
    else
        log "$ $*"
        # shellcheck disable=SC2294
        eval "$@" 2>&1 | tee -a "$LOG_FILE"
    fi
}

# ── Validação ─────────────────────────────────────────────────────────────────

validate() {
    log "Validando ambiente..."

    [[ $EUID -eq 0 ]] || error "Execute como root (sudo bash $0)"

    # UEFI obrigatório (Lanzaboote)
    [[ -d /sys/firmware/efi ]] || error "UEFI não detectado. Este installer requer UEFI."
    info "UEFI: OK"

    # Disco
    if [[ -z "$DISK" ]]; then
        # Auto-detecta
        for dev in /dev/nvme0n1 /dev/sda /dev/vda; do
            [[ -b "$dev" ]] && { DISK="$dev"; break; }
        done
        [[ -z "$DISK" ]] && error "Nenhum disco detectado. Defina: export DISK=/dev/nvmeXn1"
        warn "Disco auto-detectado: $DISK — confirme antes de continuar"
    fi
    [[ -b "$DISK" ]] || error "Disco não encontrado: $DISK"
    info "Disco: $DISK ($(lsblk -dn -o SIZE "$DISK"))"

    # Host válido
    local partitions_file="$SCRIPT_DIR/nixos/hosts/$HOST/partitions.nix"
    [[ -f "$partitions_file" ]] || error "Host '$HOST' não tem partitions.nix em: $partitions_file"
    info "Host: $HOST"

    # Flake válido
    [[ -f "$FLAKE_URI/flake.nix" ]] || error "flake.nix não encontrado em: $FLAKE_URI"
    info "Flake: $FLAKE_URI"

    log "Validação OK"
}

# ── Habilitar Nix flakes ──────────────────────────────────────────────────────

enable_flakes() {
    log "Habilitando nix flakes..."
    if ! nix --version 2>/dev/null | grep -q "nix"; then
        error "nix não encontrado. Este script requer o NixOS minimal ISO."
    fi

    # Habilita flakes na sessão atual
    export NIX_CONFIG="experimental-features = nix-command flakes"
    mkdir -p /etc/nix
    grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null || \
        echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
    info "Flakes: habilitados"
}

# ── Particionamento via disko ─────────────────────────────────────────────────

partition() {
    log "Particionando $DISK com disko (host: $HOST)..."

    local partitions_nix="$SCRIPT_DIR/nixos/hosts/$HOST/partitions.nix"

    warn "ATENÇÃO: disko VAI APAGAR TUDO em $DISK"
    if [[ "$DRY_RUN" != "true" ]]; then
        read -rp "$(echo -e "${RED}Digite 'sim' para confirmar o apagamento de $DISK: ${NC}")" confirm
        [[ "$confirm" == "sim" ]] || error "Abortado pelo usuário."
    fi

    # Passa LUKS_PASS via arquivo temporário se definido
    if [[ -n "$LUKS_PASS" ]]; then
        local pass_file
        pass_file=$(mktemp)
        echo -n "$LUKS_PASS" > "$pass_file"
        chmod 600 "$pass_file"
        trap 'rm -f "$pass_file"' EXIT
        # disko usa passwordFile em partitions.nix — mas kernelcore usa passphrase interativa
        # aqui apenas registramos para o cryptsetup pós-disko se necessário
        info "Passphrase LUKS: definida via env"
    else
        info "Passphrase LUKS: será solicitada interativamente pelo disko"
    fi

    run "nix run github:nix-community/disko/latest -- \
        --mode disko \
        --arg disks '[\"$DISK\"]' \
        $partitions_nix"

    log "Particionamento concluído"
}

# ── Instalar NixOS ────────────────────────────────────────────────────────────

install_nixos() {
    log "Instalando NixOS (flake: $FLAKE_URI#$HOST)..."

    # Copia a chave SSH do host para o sistema instalado se já existir
    # (permite sops-nix descriptografar no primeiro boot)
    if [[ -f /etc/ssh/ssh_host_ed25519_key && "$DRY_RUN" != "true" ]]; then
        local ssh_target="/mnt/etc/ssh"
        mkdir -p "$ssh_target"
        cp /etc/ssh/ssh_host_ed25519_key     "$ssh_target/"
        cp /etc/ssh/ssh_host_ed25519_key.pub "$ssh_target/" 2>/dev/null || true
        chmod 600 "$ssh_target/ssh_host_ed25519_key"
        info "SSH host key copiada → /mnt/etc/ssh/"
    fi

    run "nixos-install \
        --flake \"$FLAKE_URI#$HOST\" \
        --no-root-passwd \
        --show-trace"

    log "nixos-install concluído"
}

# ── Sbctl: enroll Secure Boot keys ───────────────────────────────────────────

setup_secureboot() {
    log "Configurando chaves Secure Boot (sbctl)..."

    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run "sbctl create-keys && sbctl enroll-keys --microsoft"
        return
    fi

    if ! command -v sbctl &>/dev/null; then
        warn "sbctl não encontrado no live env — faça o enrollment no primeiro boot:"
        warn "  sbctl create-keys"
        warn "  sbctl enroll-keys --microsoft"
        warn "  reboot → UEFI → habilitar Secure Boot"
        return
    fi

    if sbctl status 2>/dev/null | grep -q "Setup Mode: Enabled"; then
        run "sbctl create-keys"
        run "sbctl enroll-keys --microsoft"
        info "Chaves Secure Boot enrolladas. Habilite Secure Boot no UEFI após reboot."
    else
        warn "UEFI não está em Setup Mode. Habilite no firmware antes de enroll."
        warn "Pós-boot: sbctl create-keys && sbctl enroll-keys --microsoft"
    fi
}

# ── Summary ───────────────────────────────────────────────────────────────────

summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   NixOS instalado com sucesso!           ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    info "Host:   $HOST"
    info "Disco:  $DISK"
    info "Flake:  $FLAKE_URI"
    info "Log:    $LOG_FILE"
    echo ""
    warn "Próximos passos:"
    echo "  1. Habilite Secure Boot no UEFI (Setup Mode)"
    echo "  2. sbctl create-keys && sbctl enroll-keys --microsoft"
    echo "  3. reboot"
    echo ""
}

# ── Help ──────────────────────────────────────────────────────────────────────

usage() {
    cat << EOF
NixOS Nuclear Install — voidnxsec bootstrap

Uso:
  sudo bash nixos-bootstrap.sh [opções]

Variáveis de ambiente:
  DISK        Disco alvo (ex: /dev/nvme0n1)
  HOST        Host do flake (padrão: kernelcore)
  LUKS_PASS   Passphrase LUKS (vazio = interativo)
  FLAKE_URI   Caminho do flake (padrão: diretório do script)
  DRY_RUN     true = simula sem aplicar

Exemplos:
  # Instalação padrão (kernelcore, interativo)
  sudo bash nixos-bootstrap.sh

  # Host específico, dry-run
  HOST=laptop DRY_RUN=true sudo bash nixos-bootstrap.sh

  # Totalmente automatizado (CI/cloud)
  DISK=/dev/sda HOST=server LUKS_PASS=\$SECRET sudo bash nixos-bootstrap.sh

EOF
    exit 0
}

# ── Main ──────────────────────────────────────────────────────────────────────

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

echo -e "${BOLD}${CYAN}"
cat << 'EOF'
╔═══════════════════════════════════════════════════╗
║   VOIDNXSEC — NixOS Nuclear Install               ║
║   disko + LUKS2/Argon2id + Lanzaboote             ║
╚═══════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

validate
enable_flakes
partition
install_nixos
setup_secureboot
summary
