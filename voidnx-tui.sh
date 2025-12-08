#!/usr/bin/env bash
# =============================================================================
# VOID FORTRESS TUI v1.0 - Interactive ncurses Terminal UI
# =============================================================================
# Features:
#   • Interactive menu-driven installation
#   • Real-time progress tracking
#   • ncurses-based dialogs and forms
#   • Safe navigation with confirm prompts
#   • Log viewer integrated
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# Global config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_SCRIPT="$SCRIPT_DIR/voidnx.sh"
STATE_FILE="/tmp/void-fortress.state"
LOG_FILE="/tmp/void-fortress.log"
TUI_LOG="/tmp/void-fortress-tui.log"

# Colors and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Check dependencies
check_dependencies() {
    local deps=(dialog whiptail)
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${YELLOW}Warning: $cmd not found, TUI may be limited${NC}"
        fi
    done
}

# Log function
tui_log() {
    echo "[$(date +'%H:%M:%S')] $*" >> "$TUI_LOG"
}

# Main menu
show_main_menu() {
    clear
    cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════════╗
║                 VOID FORTRESS TUI INSTALLER v1.0                     ║
║              Interactive Installation & Configuration                ║
║                                                                      ║
║              🔒 Full Disk Encryption (LUKS1 + LUKS2)                ║
║              🐧 Musl/Glibc Auto-Detection                           ║
║              🛡️  Security-Hardened Defaults                         ║
║              🖥️  Hyprland/Wayland GUI (Branch)                      ║
╚══════════════════════════════════════════════════════════════════════╝

BANNER
    echo
    echo "Select Operation:"
    echo "  1) New Installation (Full Setup)"
    echo "  2) Resume Installation (from checkpoint)"
    echo "  3) Check System Status"
    echo "  4) Open LUKS Devices"
    echo "  5) Mount Filesystems"
    echo "  6) Enter Chroot Shell"
    echo "  7) View Installation Log"
    echo "  8) Advanced Options"
    echo "  9) Exit"
    echo
    echo -n "Choose option [1-9]: "
}

# New installation wizard
new_installation_wizard() {
    clear
    echo -e "${CYAN}=== VOID FORTRESS NEW INSTALLATION ===${NC}"
    echo
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: Must run as root${NC}"
        sleep 2
        return 1
    fi
    
    # Check UEFI
    if [[ ! -d /sys/firmware/efi ]]; then
        echo -e "${RED}Error: Boot in UEFI mode required${NC}"
        sleep 2
        return 1
    fi
    
    # Disk selection
    echo -e "${YELLOW}Available Disks:${NC}"
    lsblk -dn -o NAME,SIZE,MODEL | nl
    echo
    read -rp "Enter disk number (or full path like /dev/vda): " disk_choice
    
    if [[ $disk_choice =~ ^[0-9]+$ ]]; then
        local disk_name=$(lsblk -dn -o NAME | sed -n "${disk_choice}p")
        export DISK="/dev/$disk_name"
    else
        export DISK="$disk_choice"
    fi
    
    if [[ ! -b "$DISK" ]]; then
        echo -e "${RED}Error: $DISK is not a valid block device${NC}"
        sleep 2
        return 1
    fi
    
    # Confirm disk selection
    echo
    lsblk -f "$DISK"
    echo
    echo -e "${YELLOW}WARNING: All data on $DISK will be DESTROYED${NC}"
    read -rp "Type 'yes' to continue: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${YELLOW}Installation cancelled${NC}"
        sleep 2
        return 1
    fi
    
    # Hostname
    read -rp "Enter hostname [void-fortress]: " hostname
    hostname="${hostname:-void-fortress}"
    export HOSTNAME="$hostname"
    
    # Username
    read -rp "Enter username [nx]: " username
    username="${username:-nx}"
    export USERNAME="$username"
    
    # Timezone
    read -rp "Enter timezone [America/Sao_Paulo]: " timezone
    timezone="${timezone:-America/Sao_Paulo}"
    export TIMEZONE="$timezone"
    
    echo
    echo -e "${GREEN}Configuration Summary:${NC}"
    echo "  Disk:     $DISK"
    echo "  Hostname: $HOSTNAME"
    echo "  User:     $USERNAME"
    echo "  Timezone: $TIMEZONE"
    echo
    
    # Run installer
    echo -e "${CYAN}Starting installation...${NC}"
    echo
    
    # Execute the installer script
    if bash "$INSTALLER_SCRIPT"; then
        echo
        echo -e "${GREEN}✓ Installation completed successfully!${NC}"
        echo -e "Next steps:"
        echo -e "  1. Reboot system"
        echo -e "  2. Boot into new system"
        echo -e "  3. Test LUKS unlock"
        sleep 3
    else
        echo
        echo -e "${RED}✗ Installation failed. Check logs.${NC}"
        sleep 3
        return 1
    fi
}

# Resume installation
resume_installation() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo -e "${YELLOW}No previous installation state found${NC}"
        sleep 2
        return 1
    fi
    
    source "$STATE_FILE"
    clear
    echo -e "${CYAN}=== RESUMING INSTALLATION ===${NC}"
    echo
    echo "Previous state: $PHASE"
    echo "Disk: $DISK"
    echo
    
    read -rp "Resume from last checkpoint? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        return 1
    fi
    
    # Export variables and run installer in resume mode
    export DISK
    bash "$INSTALLER_SCRIPT" resume
}

# Check system status
check_status() {
    clear
    echo -e "${CYAN}=== SYSTEM STATUS ===${NC}"
    echo
    
    # Load state if exists
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
        echo -e "${GREEN}Installation State: $PHASE${NC}"
        echo "Last update: $(date -d @"$TIMESTAMP" '+%Y-%m-%d %H:%M:%S')"
        echo
    fi
    
    # Run status command
    bash "$INSTALLER_SCRIPT" status
    
    echo
    read -rp "Press Enter to return to menu..."
}

# View installation log
view_log() {
    clear
    if [[ -f "$LOG_FILE" ]]; then
        tail -50 "$LOG_FILE" | less -R
    else
        echo -e "${YELLOW}No log file found${NC}"
        sleep 2
    fi
}

# Advanced options menu
advanced_options() {
    while true; do
        clear
        echo -e "${CYAN}=== ADVANCED OPTIONS ===${NC}"
        echo
        echo "  1) Open LUKS Devices"
        echo "  2) Mount Filesystems"
        echo "  3) Cleanup & Unmount"
        echo "  4) Debug Shell (safety: ROOT only)"
        echo "  5) View Raw Logs"
        echo "  6) Back to Main Menu"
        echo
        read -rp "Choose option [1-6]: " choice
        
        case "$choice" in
            1)
                clear
                echo -e "${CYAN}Opening LUKS devices...${NC}"
                bash "$INSTALLER_SCRIPT" open
                read -rp "Press Enter to continue..."
                ;;
            2)
                clear
                echo -e "${CYAN}Mounting filesystems...${NC}"
                bash "$INSTALLER_SCRIPT" mount
                read -rp "Press Enter to continue..."
                ;;
            3)
                clear
                echo -e "${YELLOW}Running cleanup (will unmount all)...${NC}"
                bash "$INSTALLER_SCRIPT" clean
                read -rp "Press Enter to continue..."
                ;;
            4)
                clear
                echo -e "${YELLOW}WARNING: Debug shell provides direct access${NC}"
                read -rp "Continue? (y/n): " confirm
                if [[ "$confirm" == "y" ]]; then
                    bash "$INSTALLER_SCRIPT" shell
                fi
                ;;
            5)
                view_log
                ;;
            6)
                break
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# Main loop
main() {
    check_dependencies
    
    while true; do
        show_main_menu
        read -r choice
        
        case "$choice" in
            1) new_installation_wizard ;;
            2) resume_installation ;;
            3) check_status ;;
            4) bash "$INSTALLER_SCRIPT" open && sleep 2 ;;
            5) bash "$INSTALLER_SCRIPT" mount && sleep 2 ;;
            6) bash "$INSTALLER_SCRIPT" shell ;;
            7) view_log ;;
            8) advanced_options ;;
            9) 
                echo
                echo -e "${CYAN}Thank you for using VOID FORTRESS!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
