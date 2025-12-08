#!/usr/bin/env bash
# =============================================================================
# VOID FORTRESS COMPLETE v3.0 - Fully Integrated Installation System
# =============================================================================
# Features:
#   • Smart state detection & recovery
#   • Musl/glibc auto-detection
#   • LUKS1 root + LUKS2 home (Argon2id)
#   • Chroot paradox handler
#   • Automatic error recovery
#   • Progress persistence
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ━━━━━━━━━━━━━━━━━━━━━━ GLOBAL CONFIGURATION ━━━━━━━━━━━━━━━━━━━━━━
SCRIPT_VERSION="3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="/tmp/void-fortress.state"
LOG_FILE="/tmp/void-fortress.log"

# User Configuration (edit these!)
# Auto-detect common disk types: nvme > vda (VM) > sda (HD) > nvme0n1 (fallback)
if [[ -b /dev/nvme0n1 ]]; then
    DISK="${DISK:-/dev/nvme0n1}"
elif [[ -b /dev/vda ]]; then
    DISK="${DISK:-/dev/vda}"
elif [[ -b /dev/sda ]]; then
    DISK="${DISK:-/dev/sda}"
else
    DISK="${DISK:-/dev/nvme0n1}"  # Fallback if nothing found
fi
LINUX_PARTITION="/"
LINUX_PARTITION_COUNT=5

CHROOT_MARKER="/tmp/.void-fortress-chroot"

# Default partition sizes (will be adjusted based on disk size)
EFI_SIZE="512M"
BOOT_SIZE="1G"
SWAP_SIZE="8G"
ROOT_SIZE="50G"
HOSTNAME="void-fortress"
USERNAME="nx"
TIMEZONE="America/Sao_Paulo"
LOCALE="en_US.UTF-8"

# Security Configuration
LUKS1_ITER_TIME_MS=5000
PBKDF_ARGON2_MEMORY_KIB=$((1024*1024))
PBKDF_ARGON2_PARALLEL=4
PBKDF_ARGON2_TIME=3

# Feature Flags
ENABLE_TPM=true
ENABLE_GRUB_SIGNED=true
ENABLE_UEFI_SECURE_BOOT=true
ENABLE_SWAP_ENCRYPTION=true
ENABLE_2FA=true
ENABLE_INTEGRITY=true
ENABLE_AUTO_UPDATES=true
ENABLE_NET_ISOLATION=true
ENABLE_KERNEL_SECURITY=true
ENABLE_FIREWALL=true
ENABLE_ZFS=true

# ━━━━━━━━━━━━━━━━━━━━━━ SCRIPT

# ━━━━━━━━━━━━━━━━━━━━━━ COLOR PALETTE ━━━━━━━━━━━━━━━━━━━━━━
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ━━━━━━━━━━━━━━━━━━━━━━ LOGGING SYSTEM ━━━━━━━━━━━━━━━━━━━━━━
log() {
    local msg="[$(date +'%H:%M:%S')] [${FUNCNAME[1]:-main}] $*"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

warn() {
    local msg="[$(date +'%H:%M:%S')] [WARN] $*"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[$(date +'%H:%M:%S')] [ERROR] $*"
    echo -e "${RED}${msg}${NC}" >&2
    echo "$msg" >> "$LOG_FILE"
    save_state "ERROR" "$*"
    exit 1
}

info() {
    echo -e "${CYAN}ℹ $*${NC}"
    echo "[INFO] $*" >> "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓ $*${NC}"
    echo "[SUCCESS] $*" >> "$LOG_FILE"
}

# ━━━━━━━━━━━━━━━━━━━━━━ STATE MANAGEMENT ━━━━━━━━━━━━━━━━━━━━━━
save_state() {
    local phase="$1"
    local details="${2:-}"
    cat > "$STATE_FILE" << EOF
PHASE=$phase
TIMESTAMP=$(date +%s)
DISK=$DISK
DETAILS=$details
EOF
}

load_state() {
    [[ -f "$STATE_FILE" ]] && source "$STATE_FILE" || echo "NO_STATE"
}

# ━━━━━━━━━━━━━━━━━━━━━━ ENVIRONMENT DETECTION ━━━━━━━━━━━━━━━━━━━━━━
detect_environment() {
    log "Analyzing environment..."

    # Detect libc type
    if ldd --version 2>&1 | grep -q musl; then
        LIBC_TYPE="musl"
        REPO_URL="https://repo-default.voidlinux.org/current/musl"
        warn "Musl environment - some features will be adjusted"
    else
        LIBC_TYPE="glibc"
        REPO_URL="https://repo-default.voidlinux.org/current"
    fi

    # Detect if live environment
    IS_LIVE=false
    [[ -f /run/void-live ]] || grep -q "void-live" /proc/cmdline 2>/dev/null && IS_LIVE=true

    # Architecture
    ARCH=$(uname -m)

    # Partition naming scheme
    PART_SUFFIX=""
    [[ $DISK == *nvme* || $DISK == *mmcblk* ]] && PART_SUFFIX="p"

    info "Environment: $LIBC_TYPE on $ARCH, Live: $IS_LIVE"
    save_state "ENV_DETECTED" "LIBC=$LIBC_TYPE,ARCH=$ARCH"
}

# Helper for partition names
p() { echo "${DISK}${PART_SUFFIX}$1"; }

# Auto-select common disk devices (prefer vda for VMs, then sda, then nvme)
auto_select_disk() {
    # If DISK is already a real block device, keep it
    if [[ -b "$DISK" ]]; then
        return
    fi

    # Prefer typical VM disk names
    if [[ -b /dev/vda ]]; then
        DISK=/dev/vda
    elif [[ -b /dev/sda ]]; then
        DISK=/dev/sda
    elif [[ -b /dev/nvme0n1 ]]; then
        DISK=/dev/nvme0n1
    else
        # If multiple candidates, offer an interactive selection when run in a TTY
        if [[ -t 0 ]]; then
            choose_disk
        else
            warn "No common disk found and not interactive; using default $DISK"
        fi
    fi
}

# Interactive disk chooser (lists block devices and prompts for selection)
choose_disk() {
    echo "Available block devices:"
    mapfile -t _devs < <(lsblk -dn -o NAME,SIZE,MODEL | awk '{print "/dev/" $1"\t"$2"\t"substr($0,index($0,$3)) }')
    if [[ ${#_devs[@]} -eq 0 ]]; then
        error "No block devices found"
    fi

    for i in "${!_devs[@]}"; do
        printf "%3d) %s\n" $((i+1)) "${_devs[$i]}"
    done

    read -rp "Select disk number to use (or press Enter to keep default $DISK): " choice
    if [[ -z "$choice" ]]; then
        echo "Keeping default disk: $DISK"
        return
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#_devs[@]} ]]; then
        warn "Invalid selection, keeping default $DISK"
        return
    fi
    local entry=${_devs[$((choice-1))]}
    DISK=$(echo "$entry" | awk '{print $1}')
    echo "Selected disk: $DISK"
}

# Auto-detect disk size and suggest partition layout
detect_disk_size_and_adjust() {
    if [[ ! -b "$DISK" ]]; then
        warn "Disk $DISK not found, using default partition sizes"
        return
    fi

    # Get disk size in bytes
    local disk_size_bytes=$(blockdev --getsize64 "$DISK" 2>/dev/null || lsblk -bn "$DISK" 2>/dev/null | awk '{print $4}')
    if [[ -z "$disk_size_bytes" ]]; then
        warn "Could not determine disk size, using default partition sizes"
        return
    fi

    # Convert to GB for readability
    local disk_size_gb=$((disk_size_bytes / 1024 / 1024 / 1024))
    info "Detected disk size: ${disk_size_gb}GB"

    # Suggest partition layout based on available space
    log "Recommended partition layout for ${disk_size_gb}GB disk:"
    
    if [[ $disk_size_gb -lt 30 ]]; then
        # Small disk (VMs with 20GB)
        EFI_SIZE="512M"
        BOOT_SIZE="512M"
        SWAP_SIZE="2G"
        ROOT_SIZE="10G"
        log "  • EFI: 512M"
        log "  • BOOT: 512M"
        log "  • SWAP: 2G"
        log "  • ROOT: 10G"
        log "  • HOME: remainder (~${disk_size_gb}GB - 13GB)"
    elif [[ $disk_size_gb -lt 60 ]]; then
        # Medium disk (40-50GB)
        EFI_SIZE="512M"
        BOOT_SIZE="1G"
        SWAP_SIZE="4G"
        ROOT_SIZE="20G"
        log "  • EFI: 512M"
        log "  • BOOT: 1G"
        log "  • SWAP: 4G"
        log "  • ROOT: 20G"
        log "  • HOME: remainder (~${disk_size_gb}GB - 25.5GB)"
    else
        # Large disk (100GB+)
        EFI_SIZE="512M"
        BOOT_SIZE="1G"
        SWAP_SIZE="8G"
        ROOT_SIZE="50G"
        log "  • EFI: 512M"
        log "  • BOOT: 1G"
        log "  • SWAP: 8G"
        log "  • ROOT: 50G"
        log "  • HOME: remainder (~${disk_size_gb}GB - 59.5GB)"
    fi

    # Ask user to confirm or customize
    read -rp "Press Enter to accept suggested sizes, or type 'custom' to edit manually: " choice
    if [[ "$choice" == "custom" ]]; then
        customize_partition_sizes
    fi
}

# Interactive partition size customizer
customize_partition_sizes() {
    log "Customize partition sizes (format: size with M/G suffix, e.g., 512M or 20G)"
    
    read -rp "EFI size [$EFI_SIZE]: " input && [[ -n "$input" ]] && EFI_SIZE="$input"
    read -rp "BOOT size [$BOOT_SIZE]: " input && [[ -n "$input" ]] && BOOT_SIZE="$input"
    read -rp "SWAP size [$SWAP_SIZE]: " input && [[ -n "$input" ]] && SWAP_SIZE="$input"
    read -rp "ROOT size [$ROOT_SIZE]: " input && [[ -n "$input" ]] && ROOT_SIZE="$input"
    
    log "Final partition sizes:"
    log "  • EFI: $EFI_SIZE"
    log "  • BOOT: $BOOT_SIZE"
    log "  • SWAP: $SWAP_SIZE"
    log "  • ROOT: $ROOT_SIZE"
    log "  • HOME: remainder"
}

# ━━━━━━━━━━━━━━━━━━━━━━ INSTALLATION STATE DETECTION ━━━━━━━━━━━━━━━━━━━━━━
detect_installation_state() {
    local STATE="UNKNOWN"
    local DETAILS=""

    # Check disk
    if [[ ! -b "$DISK" ]]; then
        STATE="NO_DISK"
        DETAILS="Disk $DISK not found"

    # Check partitions
    elif [[ ! -b "$(p 5)" ]]; then
        STATE="NO_PARTITIONS"
        DETAILS="Partitions not created"

    # Check LUKS
    elif ! cryptsetup isLuks "$(p 4)" 2>/dev/null; then
        STATE="NOT_ENCRYPTED"
        DETAILS="Root partition not LUKS formatted"
    elif ! cryptsetup isLuks "$(p 5)" 2>/dev/null; then
        STATE="PARTIAL_ENCRYPTED"
        DETAILS="Home partition not LUKS formatted"

    # Check if LUKS is open
    elif [[ ! -e /dev/mapper/void_crypt ]]; then
        STATE="LUKS_CLOSED"
        DETAILS="LUKS devices not opened"
    elif [[ ! -e /dev/mapper/home_crypt ]]; then
        STATE="ROOT_OPEN_HOME_CLOSED"
        DETAILS="Home LUKS not opened"

    # Check LVM and filesystems
    elif ! vgs void-vg &>/dev/null; then
        STATE="NO_LVM"
        DETAILS="LVM volume group not created"
    elif ! blkid /dev/void-vg/root 2>/dev/null | grep -q 'TYPE='; then
        STATE="NO_ROOT_FS"
        DETAILS="Root filesystem not created"
    elif ! blkid /dev/mapper/home_crypt 2>/dev/null | grep -q 'TYPE='; then
        STATE="NO_HOME_FS"
        DETAILS="Home filesystem not created"

    # Check mounts
    elif ! mountpoint -q /mnt 2>/dev/null; then
        STATE="NOT_MOUNTED"
        DETAILS="Filesystems not mounted"
    elif ! mountpoint -q /mnt/boot 2>/dev/null; then
        STATE="PARTIAL_MOUNT"
        DETAILS="Boot/EFI not mounted"

    # Check installation
    elif [[ ! -d /mnt/usr || ! -d /mnt/etc ]]; then
        STATE="NO_SYSTEM"
        DETAILS="Base system not installed"
    elif [[ ! -f /mnt/etc/fstab ]]; then
        STATE="NOT_CONFIGURED"
        DETAILS="System not configured"
    else
        STATE="READY"
        DETAILS="Installation complete or nearly complete"
    fi

    echo "${STATE}|${DETAILS}"
}

# ━━━━━━━━━━━━━━━━━━━━━━ DISK OPERATIONS ━━━━━━━━━━━━━━━━━━━━━━
partition_disk() {
    log "Creating partition layout on $DISK"

    # Safety check
    warn "This will DESTROY all data on $DISK!"
    read -p "Type 'YES' to continue: " confirm
    [[ "$confirm" != "YES" ]] && error "Aborted by user"

    # Clear disk with wipefs for safety across all partition schemes
    wipefs -af "$DISK" || warn "Could not wipe filesystem signatures"

    # Use sfdisk for non-interactive automatic partitioning
    log "Automatically creating partition layout on $DISK"
    log "Partitions: EFI=${EFI_SIZE}, BOOT=${BOOT_SIZE}, SWAP=${SWAP_SIZE}, ROOT=${ROOT_SIZE}, HOME=remainder"
    
    sfdisk "$DISK" << SFDISK_EOF
label: gpt
label-id: $(uuidgen)
device: $DISK

# EFI partition
size=${EFI_SIZE}, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
# BOOT partition
size=${BOOT_SIZE}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="BOOT"
# SWAP partition
size=${SWAP_SIZE}, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name="SWAP"
# ROOT partition
size=${ROOT_SIZE}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="ROOT"
# HOME partition (remainder)
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="HOME"
SFDISK_EOF

    if [[ $? -ne 0 ]]; then
        error "sfdisk partitioning failed"
    fi

    # Rescan partition table (use blockdev if partprobe unavailable)
    if command -v partprobe &>/dev/null; then
        partprobe "$DISK"
    else
        blockdev --rereadpt "$DISK" 2>/dev/null || true
    fi
    sleep 2

    success "Partitioning complete"
    save_state "PARTITIONED"
}

setup_luks() {
    log "Setting up LUKS encryption"

    # Format EFI and BOOT
    mkfs.vfat -F32 -n EFI "$(p 1)"
    if ! blkid "$(p 2)" 2>/dev/null | grep -q 'TYPE='; then
        mkfs.ext4 -F -L BOOT "$(p 2)"
    fi

    # Check if already formatted
    if cryptsetup isLuks "$(p 4)" 2>/dev/null; then
        warn "Root already LUKS formatted, skipping"
    else
        info "Formatting root partition with LUKS1"
        cryptsetup luksFormat \
            --type luks1 \
            --cipher aes-xts-plain64 \
            --key-size 512 \
            --hash sha512 \
            --iter-time "$LUKS1_ITER_TIME_MS" \
            --verify-passphrase \
            "$(p 4)"
    fi

    # Home LUKS2
    if cryptsetup isLuks "$(p 5)" 2>/dev/null; then
        warn "Home already LUKS formatted, skipping"
    else
        # Calculate Argon2 memory
        local ram_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        local argon_mem=$(( ram_kb * 3 / 4 ))
        [[ $argon_mem -lt 1048576 ]] && argon_mem=1048576
        [[ $argon_mem -gt 4194304 ]] && argon_mem=4194304

        info "Formatting home partition with LUKS2 (Argon2id)"
        cryptsetup luksFormat \
            --type luks2 \
            --cipher aes-xts-plain64 \
            --key-size 512 \
            --hash sha512 \
            --pbkdf argon2id \
            --pbkdf-memory "$argon_mem" \
            --pbkdf-parallel "$PBKDF_ARGON2_PARALLEL" \
            --iter-time "$PBKDF_ARGON2_TIME" \
            --verify-passphrase \
            "$(p 5)"
    fi

    success "LUKS setup complete"
    save_state "LUKS_FORMATTED"
}

open_luks() {
    log "Opening LUKS devices"

    if [[ ! -e /dev/mapper/root_crypt ]]; then
        cryptsetup open "$(p 4)" root_crypt || error "Failed to open root"
    else
        info "Root already open"
    fi

    if [[ ! -e /dev/mapper/home_crypt ]]; then
        cryptsetup open "$(p 5)" home_crypt || error "Failed to open home"
    else
        info "Home already open"
    fi

    # Create filesystems if needed
    if ! blkid /dev/mapper/root_crypt 2>/dev/null | grep -q 'TYPE='; then
        mkfs.ext4 -F -L ROOT /dev/mapper/root_crypt
    fi

    if ! blkid /dev/mapper/home_crypt 2>/dev/null | grep -q 'TYPE='; then
        mkfs.ext4 -F -L HOME /dev/mapper/home_crypt
    fi

    success "LUKS devices ready"
    save_state "LUKS_OPEN"
}

# ━━━━━━━━━━━━━━━━━━━━━━ MOUNT OPERATIONS ━━━━━━━━━━━━━━━━━━━━━━
# Em mount_filesystems() (corrige EFI mount)
mount_filesystems() {
    log "Mounting filesystems"
    if ! mountpoint -q /mnt; then
        mount /dev/mapper/root_crypt /mnt || error "Failed to mount root"
    fi
    mkdir -p /mnt/{boot,home}
    if ! mountpoint -q /mnt/boot; then
        mount "$(p 2)" /mnt/boot || error "Failed to mount boot"
    fi
    mkdir -p /mnt/boot/efi
    if ! mountpoint -q /mnt/boot/efi; then
        mount "$(p 1)" /mnt/boot/efi || error "Failed to mount EFI"
    fi
    mkdir -p /mnt/{dev,proc,sys,run,tmp}
    if ! mountpoint -q /mnt/home; then
        mount /dev/mapper/home_crypt /mnt/home || error "Failed to mount home"
    fi

    # Activate swap
    if ! swapon --show | grep -q "$(p 3)"; then
        swapon "$(p 3)" || warn "Failed to activate swap"
    fi

    success "All filesystems mounted"
    save_state "MOUNTED"
}

prepare_chroot() {
    log "Preparing chroot environment"

    # Mount pseudo filesystems (safe to repeat)
    for dir in dev proc sys; do
        if ! mountpoint -q "/mnt/$dir"; then
            mount --rbind "/$dir" "/mnt/$dir"
            mount --make-rslave "/mnt/$dir"
        fi
    done

    # Mount run as tmpfs
    if ! mountpoint -q /mnt/run; then
        mount -t tmpfs tmpfs /mnt/run
    fi

    # Copy network config
    cp -L /etc/resolv.conf /mnt/etc/ 2>/dev/null || true

    success "Chroot environment ready"
}

cleanup_chroot() {
    log "Cleaning chroot mounts"

    # Kill processes using /mnt
    fuser -km /mnt 2>/dev/null || true
    sleep 1

    # Unmount pseudo filesystems
    for dir in run sys proc dev/pts dev; do
        umount -l "/mnt/$dir" 2>/dev/null || true
    done
}

# ━━━━━━━━━━━━━━━━━━━━━━ INSTALLATION ━━━━━━━━━━━━━━━━━━━━━━
bootstrap_system() {
    log "Starting bootstrap phase with FDE support"

    # Copy XBPS keys first for package trust
    mkdir -p /mnt/var/db/xbps/keys
    cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/ || warn "Could not copy XBPS keys"

    # Choose base packages depending on libc implementation
    local BASE_PKGS=(
        base-system
        cryptsetup
        grub-x86_64-efi
        efibootmgr
        dracut
        lvm2
        void-repo-nonfree
        arch-install-scripts
    )

    if [[ "${LIBC_TYPE:-glibc}" == "musl" ]]; then
        info "Detected musl host; adjusting base packages for musl environment"
        # musl systems don't need glibc-locales; add musl-locales if available
        BASE_PKGS+=(musl-locales)
    else
        # glibc systems can install glibc locales support
        BASE_PKGS+=(glibc-locales)
    fi

    # Bootstrap core system with crypto support
    log "Installing base system with crypto support"
    xbps-install -Sy -r /mnt -R "$REPO_URL" "${BASE_PKGS[@]}" || error "Bootstrap failed"

    # Copy network config
    cp -L /etc/resolv.conf /mnt/etc/ 2>/dev/null || warn "Could not copy resolv.conf"

    success "Bootstrap phase complete"
    save_state "BOOTSTRAPPED"
}

generate_fstab() {
    log "Generating fstab with proper UUIDs"

    # Get UUIDs for all devices
    local EFI_UUID=$(blkid -s UUID -o value "$(p 1)")
    local BOOT_UUID=$(blkid -s UUID -o value "$(p 2)")
    local ROOT_CRYPT_UUID=$(blkid -s UUID -o value /dev/mapper/root_crypt)
    local HOME_CRYPT_UUID=$(blkid -s UUID -o value /dev/mapper/home_crypt)
    local SWAP_UUID=$(blkid -s UUID -o value "$(p 3)")

    # Generate fstab
    cat > /mnt/etc/fstab << EOF
# <device>                                    <dir>       <type>  <options>               <dump> <pass>
UUID=${ROOT_CRYPT_UUID}                      /           ext4    defaults,noatime        0      1
UUID=${BOOT_UUID}                            /boot       ext4    defaults,noatime,nodev  0      2
UUID=${EFI_UUID}                             /boot/efi   vfat    defaults,umask=0077     0      2
UUID=${HOME_CRYPT_UUID}                      /home       ext4    defaults,noatime,nodev  0      2
UUID=${SWAP_UUID}                            none        swap    sw                      0      0
tmpfs                                        /tmp        tmpfs   defaults,nosuid,nodev   0      0
EOF

    success "fstab generated"
}

generate_chroot_script() {
    log "Generating configuration script"

    # Get device UUIDs for crypttab (UUIDs of the physical LUKS partitions)
    local ROOT_LUKS_UUID=$(blkid -s UUID -o value "$(p 4)")
    local HOME_LUKS_UUID=$(blkid -s UUID -o value "$(p 5)")
    local SWAP_UUID=$(blkid -s UUID -o value "$(p 3)")

    # Prepare GRUB root device mapper path
    local GRUB_ROOT_DEVICE="/dev/mapper/root_crypt"

    cat > /mnt/configure.sh << SCRIPT_EOF
#!/bin/bash
set -euo pipefail
log() { echo -e "\033[0;32m[CONFIG] \$*\033[0m"; }

# Ensure passwd/shadow exist
touch /etc/passwd /etc/shadow
chmod 644 /etc/passwd
chmod 600 /etc/shadow
pwconv

    # Configuration variables
HOSTNAME="${HOSTNAME}"
USERNAME="${USERNAME}"
TIMEZONE="${TIMEZONE}"
ROOT_LUKS_UUID="${ROOT_LUKS_UUID}"
HOME_LUKS_UUID="${HOME_LUKS_UUID}"
SWAP_UUID="${SWAP_UUID}"
LIBC_TYPE="${LIBC_TYPE:-glibc}"

log "Setting hostname"
echo "\${HOSTNAME}" > /etc/hostname

cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HOSTNAME}.localdomain \${HOSTNAME}
EOF

log "Setting timezone"
ln -sf "/usr/share/zoneinfo/\${TIMEZONE}" /etc/localtime

log "Creating user"
useradd -m -G wheel,audio,video,input,kvm -s /bin/bash "\${USERNAME}" || log "User exists"

log "Setting root password"
echo "Please set password for root user:"
until passwd root; do
    log "Root password setting failed, trying again..."
    sleep 1
done

log "Setting password for user \${USERNAME}"
echo "Please set password for user \${USERNAME}:"
until passwd "\${USERNAME}"; do
    log "User password setting failed, trying again..."
    sleep 1
done

log "Configuring sudo"
mkdir -p /etc/sudoers.d
cat > /etc/sudoers.d/wheel << EOF
%wheel ALL=(ALL:ALL) ALL
Defaults timestamp_timeout=0
EOF
chmod 440 /etc/sudoers.d/wheel

# Create LUKS key file for automatic unlock via Dracut
log "Creating LUKS key file"
dd bs=1 count=64 if=/dev/urandom of=/boot/volume.key
chmod 000 /boot/volume.key
# Note: adding this key to LUKS MUST be done from the host (outside chroot) so
# we will add the key after writing this script.

log "Configuring crypttab"
# Standardized to root_crypt to match initial setup
cat > /etc/crypttab << EOF
root_crypt  UUID=\${ROOT_LUKS_UUID}  /boot/volume.key  luks
home_crypt  UUID=\${HOME_LUKS_UUID}  none              luks
swap        UUID=\${SWAP_UUID}       /dev/urandom      swap,cipher=aes-xts-plain64,size=512
EOF

log "Configuring dracut for LUKS (NO LVM)"
cat > /etc/dracut.conf.d/10-crypt.conf << EOF
hostonly=yes
hostonly_cmdline=no
compress="zstd"
# Removed 'lvm' which caused issues; include key and crypttab
add_dracutmodules+=" crypt rootfs-block "
install_items+=" /boot/volume.key /etc/crypttab "
EOF

log "Configuring GRUB"
# Fix: removed rd.lvm.vg=void-vg and point root to mapper
cat > /etc/default/grub << EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Void"
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 mitigations=auto lockdown=confidentiality init_on_alloc=1 init_on_free=1 page_poison=1 vsyscall=none slab_nomerge pti=on apparmor=1 security=apparmor"
GRUB_CMDLINE_LINUX="rd.luks.uuid=\${ROOT_LUKS_UUID} root=/dev/mapper/root_crypt"
GRUB_ENABLE_CRYPTODISK=y
EOF

log "Installing GRUB to EFI"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=void
# grub-install --removable # Optional
grub-mkconfig -o /boot/grub/grub.cfg

log "Regenerating initramfs"
xbps-reconfigure -fa

log "System configuration complete!"
SCRIPT_EOF

    chmod +x /mnt/configure.sh

    # We must add the LUKS key from the host, because /dev/by-uuid may not be
    # consistent inside the chroot. The key lives at /mnt/boot/volume.key on host.
    log "Adding internal key to LUKS slots (host side)"
    echo -n "Adding volume.key to LUKS. You need to enter the partition password one more time:"
    cryptsetup luksAddKey "$(p 4)" /mnt/boot/volume.key || warn "Failed to add LUKS key; boot will prompt for passphrase"

    success "Configuration script ready"
}

run_chroot_config() {
    log "Running system configuration in chroot"

    prepare_chroot
    chroot /mnt /configure.sh || error "Configuration failed"
    cleanup_chroot

    success "System configured"
    save_state "CONFIGURED"
}

# ━━━━━━━━━━━━━━━━━━━━━━ RECOVERY & STATE HANDLERS ━━━━━━━━━━━━━━━━━━━━━━
handle_state() {
    local state="$1"
    local details="$2"

    info "Current state: $state"
    info "Details: $details"

    case "$state" in
        NO_DISK)
            error "Disk $DISK not found"
            ;;
        NO_PARTITIONS)
            partition_disk
            setup_luks
            open_luks
            mount_filesystems
            bootstrap_system
            generate_fstab
            generate_chroot_script
            run_chroot_config
            ;;
        NOT_ENCRYPTED|PARTIAL_ENCRYPTED)
            setup_luks
            open_luks
            mount_filesystems
            bootstrap_system
            generate_fstab
            generate_chroot_script
            run_chroot_config
            ;;
        LUKS_CLOSED|ROOT_OPEN_HOME_CLOSED)
            open_luks
            mount_filesystems
            # Verify if base system exists before installing
            if [[ ! -f /mnt/bin/bash ]]; then
                bootstrap_system
                generate_fstab
            fi
            generate_chroot_script
            run_chroot_config
            ;;
        NO_LVM|NO_ROOT_FS|NO_HOME_FS)
            open_luks
            mount_filesystems
            bootstrap_system
            generate_fstab
            generate_chroot_script
            run_chroot_config
            ;;
        NOT_MOUNTED|PARTIAL_MOUNT)
            mount_filesystems
            if [[ ! -f /mnt/bin/bash ]]; then
                bootstrap_system
                generate_fstab
            fi
            generate_chroot_script
            run_chroot_config
            ;;
        NO_SYSTEM)
            bootstrap_system
            generate_fstab
            generate_chroot_script
            run_chroot_config
            ;;
        NOT_CONFIGURED)
            generate_chroot_script
            run_chroot_config
            ;;
        READY)
            success "System appears ready!"
            show_final_status
            ;;
        *)
            error "Unknown state: $state"
            ;;
    esac
}

# ━━━━━━━━━━━━━━━━━━━━━━ STATUS DISPLAY ━━━━━━━━━━━━━━━━━━━━━━
show_banner() {
    clear
    cat << 'BANNER'
╔════════════════════════════════════════════════════════════════╗
║               VOID FORTRESS INSTALLER v3.0                     ║
║         Integrated State-Aware Installation System             ║
╚════════════════════════════════════════════════════════════════╝
BANNER
}

show_final_status() {
    echo
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}     Installation Complete!              ${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo
    echo "Next steps:"
    echo "1. Reboot system"
    echo "2. Remove installation media"
    echo "3. First boot tasks:"
    echo "   - Test LUKS unlock"
    echo "   - Initialize AIDE: aide --init"
    echo "   - Setup 2FA tokens if enabled"
    echo
    lsblk -f "$DISK"
}

show_status() {
    echo
    echo -e "${CYAN}Current Status:${NC}"
    lsblk -f "$DISK" 2>/dev/null || lsblk
    echo
    if [[ -e /dev/mapper/root_crypt ]]; then
        echo -e "${GREEN}✓ LUKS devices open${NC}"
    else
        echo -e "${YELLOW}○ LUKS devices closed${NC}"
    fi

    if mountpoint -q /mnt; then
        echo -e "${GREEN}✓ Filesystems mounted${NC}"
    else
        echo -e "${YELLOW}○ Filesystems not mounted${NC}"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━ CLEANUP ━━━━━━━━━━━━━━━━━━━━━━
cleanup() {
    log "Running cleanup..."

    cleanup_chroot

    # Unmount filesystems
    for mount in /mnt/home /mnt/var /mnt/boot/efi /mnt/boot /mnt; do
        umount "$mount" 2>/dev/null || true
    done

    # Deactivate LVM
    vgchange -an void-vg 2>/dev/null || true

    # Close LUKS (prefer standardized names, keep fallback)
    cryptsetup close home_crypt 2>/dev/null || true
    cryptsetup close root_crypt 2>/dev/null || true
    cryptsetup close void_crypt 2>/dev/null || true

    log "Cleanup complete"
}

# ━━━━━━━━━━━━━━━━━━━━━━ MAIN EXECUTION ━━━━━━━━━━━━━━━━━━━━━━
main() {
    show_banner

    # Setup
    detect_environment
    
    # Auto-detect disk size and adjust partition layout
    detect_disk_size_and_adjust

    # Safety check
    [[ $EUID -eq 0 ]] || error "Must run as root"
    [[ -d /sys/firmware/efi ]] || error "Boot in UEFI mode required"

    # Check current state
    IFS='|' read -r STATE DETAILS <<< "$(detect_installation_state)"

    # Handle based on state
    handle_state "$STATE" "$DETAILS"

    success "Process complete!"
}

# ━━━━━━━━━━━━━━━━━━━━━━ COMMAND HANDLERS ━━━━━━━━━━━━━━━━━━━━━━
case "${1:-}" in
    status)
        show_status
        ;;
    open)
        open_luks
        ;;
    mount)
        open_luks
        mount_filesystems
        ;;
    chroot)
        open_luks
        mount_filesystems
        prepare_chroot
        chroot /mnt /bin/bash
        cleanup_chroot
        ;;
    shell)
        log "Opening interactive debug shell"
        open_luks
        mount_filesystems
        prepare_chroot
        log "You are now in an interactive shell; type 'exit' to return"
        chroot /mnt /bin/bash -i
        cleanup_chroot
        ;;
    debug)
        log "Running system detection and showing current state"
        detect_environment
        IFS='|' read -r STATE DETAILS <<< "$(detect_installation_state)"
        info "Detected State: $STATE"
        info "Details: $DETAILS"
        show_status
        ;;
    clean)
        cleanup
        ;;
    resume)
        main
        ;;
    *)
        main
        ;;
esac

# Trap cleanup on exit
trap cleanup EXIT


