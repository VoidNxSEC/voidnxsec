#!/bin/bash
# VOID FORTRESS - Automated Installation Script
# For CI/CD pipelines and unattended installations

set -euo pipefail
IFS=$'\n\t'

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration - Set these via environment variables
DISK="${DISK:-/dev/vda}"
HOSTNAME="${HOSTNAME:-void-fortress}"
USERNAME="${USERNAME:-nx}"
TIMEZONE="${TIMEZONE:-America/Sao_Paulo}"
LOCALE="${LOCALE:-en_US.UTF-8}"

# Encryption passphrases (NEVER hardcode in production!)
ROOT_PASS="${ROOT_PASS:-}"
USER_PASS="${USER_PASS:-}"
LUKS_PASS="${LUKS_PASS:-}"

# Options
DRY_RUN="${DRY_RUN:-false}"
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
AUTO_REBOOT="${AUTO_REBOOT:-false}"
LOG_FILE="${LOG_FILE:-/tmp/void-fortress-auto.log}"

# Functions
log() {
    local msg="[$(date +'%H:%M:%S')] $*"
    echo -e "${GREEN}${msg}${NC}" | tee -a "$LOG_FILE"
}

warn() {
    local msg="[$(date +'%H:%M:%S')] WARNING: $*"
    echo -e "${YELLOW}${msg}${NC}" | tee -a "$LOG_FILE"
}

error() {
    local msg="[$(date +'%H:%M:%S')] ERROR: $*"
    echo -e "${RED}${msg}${NC}" | tee -a "$LOG_FILE"
    exit 1
}

validate_config() {
    log "Validating configuration..."
    
    # Check required variables
    [[ -z "$DISK" ]] && error "DISK not set"
    [[ -z "$HOSTNAME" ]] && error "HOSTNAME not set"
    [[ -z "$USERNAME" ]] && error "USERNAME not set"
    [[ -z "$TIMEZONE" ]] && error "TIMEZONE not set"
    
    # Check if in automated mode
    if [[ -z "$ROOT_PASS" || -z "$USER_PASS" || -z "$LUKS_PASS" ]]; then
        error "For automated installation, all passwords must be set:"
        error "  export ROOT_PASS='your_root_password'"
        error "  export USER_PASS='your_user_password'"
        error "  export LUKS_PASS='your_luks_password'"
    fi
    
    # Check disk
    if [[ ! -b "$DISK" ]]; then
        error "Disk not found: $DISK"
    fi
    
    log "Configuration valid ✓"
}

show_config() {
    cat << EOF
${BLUE}INSTALLATION CONFIGURATION${NC}

System Settings:
  • Hostname: $HOSTNAME
  • Username: $USERNAME (password: $([ -z "$USER_PASS" ] && echo "not set" || echo "set"))
  • Timezone: $TIMEZONE
  • Locale: $LOCALE

Installation Target:
  • Disk: $DISK
  • LUKS Password: $([ -z "$LUKS_PASS" ] && echo "not set" || echo "set")

Behavior:
  • Dry Run: $DRY_RUN
  • Skip Validation: $SKIP_VALIDATION
  • Auto Reboot: $AUTO_REBOOT
  • Log File: $LOG_FILE

EOF
}

confirm() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No changes will be made"
        return 0
    fi
    
    local question="$1"
    read -rp "${YELLOW}${question} (yes/no): ${NC}" -i "no" response
    
    [[ "$response" == "yes" ]] && return 0 || return 1
}

prepare_environment() {
    log "Preparing environment..."
    
    # Create temporary directory for scripts
    mkdir -p /tmp/void-fortress-auto
    
    # Download installer if not present
    if [[ ! -f "./voidnx.sh" ]]; then
        if command -v git &>/dev/null; then
            git clone https://github.com/VoidNxSEC/VoidSEC.git /tmp/void-fortress-auto
        else
            error "Git not found. Please ensure voidnx.sh is in current directory."
        fi
    fi
    
    log "Environment ready ✓"
}

run_installation() {
    log "Starting automated installation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would execute: ./voidnx.sh"
        return 0
    fi
    
    # Prepare environment for automated mode
    export DISK
    export HOSTNAME
    export USERNAME
    export TIMEZONE
    export LOCALE
    
    # Run installer with error handling
    if bash ./voidnx.sh 2>&1 | tee -a "$LOG_FILE"; then
        log "Installation completed successfully!"
        
        if [[ "$AUTO_REBOOT" == "true" ]]; then
            log "Rebooting system in 10 seconds..."
            sleep 10
            reboot
        else
            log "Installation ready. Review /tmp/void-fortress.log and reboot when ready."
        fi
    else
        error "Installation failed! Check $LOG_FILE for details."
    fi
}

# Main execution
main() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║     VOID FORTRESS - Automated Installation                     ║
║          Press Ctrl+C to abort at any time                     ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Validation
    [[ "$SKIP_VALIDATION" != "true" ]] && validate_config
    
    # Show configuration
    show_config
    
    # Confirmation
    confirm "Proceed with installation?" || {
        log "Installation cancelled"
        exit 0
    }
    
    # Preparation
    prepare_environment
    
    # Installation
    run_installation
}

# Help
usage() {
    cat << EOF
VOID FORTRESS - Automated Installation

Usage: sudo bash install-auto.sh [OPTIONS]

Environment Variables:
  DISK              Disk to install to (required)
  HOSTNAME          System hostname
  USERNAME          Primary username
  TIMEZONE          System timezone
  LOCALE            System locale
  ROOT_PASS         Root password
  USER_PASS         User password
  LUKS_PASS         LUKS encryption password

Options:
  DRY_RUN=true      Show what would be done without changes
  SKIP_VALIDATION   Skip configuration validation
  AUTO_REBOOT=true  Automatically reboot after installation
  LOG_FILE=...      Custom log file location

Example:
  export DISK=/dev/sda
  export HOSTNAME=mypc
  export USERNAME=user
  export ROOT_PASS=SecureRootPass123
  export USER_PASS=SecureUserPass456
  export LUKS_PASS=SecureLUKSPass789
  sudo bash install-auto.sh

EOF
    exit 0
}

# Handle arguments
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

# Require root
[[ $EUID -eq 0 ]] || error "This script must be run as root"

# Run
main
