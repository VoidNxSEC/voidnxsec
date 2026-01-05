#!/bin/bash
# VOID FORTRESS Quick Start
# One-liner installation scripts for common scenarios

set -euo pipefail

REPO_URL="https://github.com/VoidNxSEC/VoidSEC"
SCRIPT_DIR="/tmp/void-fortress"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_menu() {
    clear
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║        VOID FORTRESS - Quick Installation Menu                 ║
╚════════════════════════════════════════════════════════════════╝

Choose installation type:

  1) Fresh Installation (interactive)
  2) Fresh Installation (express - 20GB VM)
  3) Fresh Installation (large disk - 50GB+)
  4) Resume Interrupted Installation
  5) Check Installation Status
  6) Open LUKS and Mount Only
  7) Interactive Shell (debug/manual steps)
  8) Clean Up and Unmount
  9) View Installation Log
  0) Exit

EOF
}

download_scripts() {
    echo -e "${BLUE}Downloading VOID FORTRESS scripts...${NC}"
    
    if [[ -d "$SCRIPT_DIR" ]]; then
        rm -rf "$SCRIPT_DIR"
    fi
    mkdir -p "$SCRIPT_DIR"
    
    cd "$SCRIPT_DIR"
    git clone --depth 1 "$REPO_URL" . 2>/dev/null || {
        echo "Git clone failed, trying curl..."
        curl -L -o voidnx.sh "$REPO_URL/raw/main/voidnx.sh" || {
            echo "Download failed!"
            return 1
        }
        chmod +x voidnx.sh
    }
    
    echo -e "${GREEN}✓ Scripts ready${NC}"
    return 0
}

main_menu() {
    while true; do
        show_menu
        read -rp "Select option (0-9): " choice
        
        case "$choice" in
            1)
                echo -e "${BLUE}Starting interactive installation...${NC}"
                sudo bash "$SCRIPT_DIR/voidnx.sh"
                ;;
            2)
                echo -e "${BLUE}Quick VM installation (20GB)...${NC}"
                export DISK="${DISK:-/dev/vda}"
                sudo bash "$SCRIPT_DIR/voidnx.sh"
                ;;
            3)
                echo -e "${BLUE}Large disk installation (50GB+)...${NC}"
                export DISK="${DISK:-/dev/sda}"
                sudo bash "$SCRIPT_DIR/voidnx.sh"
                ;;
            4)
                echo -e "${BLUE}Resuming installation...${NC}"
                sudo bash "$SCRIPT_DIR/voidnx.sh" resume
                ;;
            5)
                echo -e "${BLUE}Installation status:${NC}"
                sudo bash "$SCRIPT_DIR/voidnx.sh" debug
                read -rp "Press Enter to continue..."
                ;;
            6)
                echo -e "${BLUE}Opening LUKS and mounting...${NC}"
                sudo bash "$SCRIPT_DIR/voidnx.sh" mount
                echo -e "${GREEN}✓ Filesystems mounted at /mnt${NC}"
                read -rp "Press Enter to continue..."
                ;;
            7)
                echo -e "${BLUE}Opening interactive shell...${NC}"
                sudo bash "$SCRIPT_DIR/voidnx.sh" shell
                ;;
            8)
                echo -e "${YELLOW}Cleaning up and unmounting...${NC}"
                sudo bash "$SCRIPT_DIR/voidnx.sh" clean
                echo -e "${GREEN}✓ Cleanup complete${NC}"
                read -rp "Press Enter to continue..."
                ;;
            9)
                less /tmp/void-fortress.log || echo "No log file found"
                ;;
            0)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Main flow
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}This script will launch installers that require root.${NC}"
    echo "Please ensure you can use sudo without password, or run: sudo bash quickstart.sh"
fi

download_scripts || exit 1
main_menu
