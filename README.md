# VOID FORTRESS - Full Disk Encryption Installer

Complete automated installation system for Void Linux with full disk encryption (LUKS1 + LUKS2).

## Features

- 🔒 **Full Disk Encryption**
  - LUKS1 for root partition (AES-XTS-Plain64, SHA512)
  - LUKS2 for home partition (Argon2id)
  
- 🐧 **Void Linux Compatible**
  - Musl/glibc auto-detection
  - Automatic package repository selection
  - Void-native tools (sfdisk, xbps-install, dracut)

- 🛡️ **Security Hardened**
  - AppArmor integration
  - Kernel security parameters (pti, vsyscall=none, slab_nomerge)
  - Memory protection (init_on_alloc, init_on_free, page_poison)
  - Firewall-ready

- 🖥️ **Desktop Environments**
  - **Branch: main** - CLI-only (lightweight)
  - **Branch: gui-hyprland** - Hyprland + Wayland
  - **Branch: dev** - Development with TUI

- 💾 **Smart Disk Detection**
  - Auto-detects NVMe, VDA (VM), SDA (HDD)
  - Interactive disk size detection
  - Automatic partition sizing for 20GB VMs to 500GB+ drives
  - Customizable partition layout

## System Requirements

- **UEFI firmware** (required)
- **Void Linux live environment** or existing Void installation
- **Root access** (required for installation)
- **At least 20GB disk space** (for minimal setup)

### For TUI Development
- GCC compiler
- ncurses development libraries (`ncurses-devel` on Void)

## Installation Methods

### 1. CLI Installer (Main Branch)

```bash
# Switch to main branch
git checkout main

# Run the installer
sudo bash voidnx.sh
```

**Interactive prompts for:**
- Disk selection
- Partition sizing
- Hostname, username, timezone
- Root and user passwords

### 2. GUI + Hyprland (gui-hyprland Branch)

```bash
# Switch to GUI branch
git checkout gui-hyprland

# Run the installer
sudo bash voidnx.sh
```

Includes Hyprland window manager, Waybar, Wofi, and all desktop environment packages.

### 3. TUI Interactive (dev Branch)

```bash
# Switch to dev branch
git checkout dev

# Option A: Bash TUI
sudo bash voidnx-tui.sh

# Option B: Compiled C TUI (requires ncurses)
make
sudo ./voidnx-tui
```

## Usage Examples

### Quick Start (Default 20GB VM)

```bash
sudo bash voidnx.sh
```

- Auto-detects 20GB disk
- Suggests: 512M EFI, 512M BOOT, 1G SWAP, 8G ROOT, remainder HOME
- Interactive confirmation at each step

### Custom Disk Setup

```bash
# Set specific disk before running
export DISK=/dev/sda

# Run installer
sudo bash voidnx.sh
```

### Advanced Commands

```bash
# Check current installation state
sudo bash voidnx.sh debug

# Open LUKS devices without full installation
sudo bash voidnx.sh open

# Mount filesystems
sudo bash voidnx.sh mount

# Interactive chroot shell
sudo bash voidnx.sh shell

# Clean up and unmount
sudo bash voidnx.sh clean
```

## Installation Process

### Phase 1: Partitioning & Encryption
1. Disk selection and validation
2. Automatic partition sizing
3. sfdisk creates GPT partitions
4. LUKS1 formatting (root)
5. LUKS2 formatting (home, Argon2id)

### Phase 2: Bootstrap
1. LUKS device opening
2. Filesystem creation (ext4)
3. Mount all filesystems
4. Base system installation (xbps)
5. Network configuration copy

### Phase 3: System Configuration (Chroot)
1. fstab generation with UUIDs
2. Hostname and network setup
3. User creation with sudoers config
4. LUKS key file generation and addition
5. Crypttab configuration
6. Dracut initramfs setup
7. GRUB configuration and installation
8. Desktop environment setup (if selected branch)

### Phase 4: Finalization
1. Initramfs regeneration
2. System readiness check
3. Reboot-ready state

## Partition Layout

### For 20GB VM
```
/dev/vda1 (512M)  → EFI System
/dev/vda2 (512M)  → BOOT (ext4)
/dev/vda3 (1G)    → SWAP (encrypted)
/dev/vda4 (8G)    → ROOT (LUKS1)
/dev/vda5 (≈9.5G) → HOME (LUKS2)
```

### For 50GB+ Disk
```
/dev/xxx1 (512M)  → EFI System
/dev/xxx2 (1G)    → BOOT (ext4)
/dev/xxx3 (2-4G)  → SWAP (encrypted)
/dev/xxx4 (15-30G)→ ROOT (LUKS1)
/dev/xxx5 (rest)  → HOME (LUKS2)
```

## Configuration Files

### Environment Variables

```bash
DISK              # Block device (auto-detected)
HOSTNAME          # System hostname
USERNAME          # Primary user
TIMEZONE          # System timezone
LIBC_TYPE         # Auto-detected (musl/glibc)
EFI_SIZE          # EFI partition size
BOOT_SIZE         # Boot partition size
SWAP_SIZE         # Swap partition size
ROOT_SIZE         # Root partition size
```

### State Files

- `/tmp/void-fortress.state` - Installation state and progress
- `/tmp/void-fortress.log` - Detailed installation log
- `/tmp/void-fortress-tui.log` - TUI-specific logs

## Troubleshooting

### Partition Offset Error

**Problem:** "Requested offset is beyond the real size"

**Solution:** Reduce partition sizes. Auto-detection should handle this.

```bash
export ROOT_SIZE="6G"
export SWAP_SIZE="512M"
sudo bash voidnx.sh
```

### LUKS Mapper Not Found

**Problem:** `/dev/mapper/root_crypt` doesn't exist

**Solution:** Run LUKS device opening:

```bash
sudo bash voidnx.sh open
```

### Mount Failures

**Problem:** Filesystems won't mount

**Solution:** Check partition existence:

```bash
sudo bash voidnx.sh debug
```

### Bootstrap Package Failures

**Problem:** xbps-install fails

**Check repository:**

```bash
# View current repository
grep "REPO_URL" /tmp/void-fortress.log

# Force specific repository
export REPO_URL="https://repo-default.voidlinux.org/current"
sudo bash voidnx.sh
```

## Building TUI from Source

### Prerequisites

```bash
# On Void Linux
sudo xbps-install -S gcc ncurses-devel

# On other distros
# Ubuntu/Debian: sudo apt install build-essential libncurses-dev
# Fedora: sudo dnf install gcc ncurses-devel
```

### Compile

```bash
cd /path/to/void-fortress
make clean
make
```

### Install

```bash
sudo make install
sudo voidnx-tui
```

## Project Structure

```
voidnx.sh              # Main CLI installer (bash)
voidnx-tui.sh          # TUI wrapper (bash) - dev branch
voidnx-tui.c           # C implementation of TUI - dev branch
voidnx-tui-hyprland.c  # Enhanced TUI with GUI preview - dev branch
Makefile               # Build system
README.md              # This file
```

## Branches

| Branch | Purpose | Interface |
|--------|---------|-----------|
| **main** | Stable CLI installer | Pure CLI (bash) |
| **dev** | Development & testing | TUI (ncurses) |
| **gui-hyprland** | GUI desktop environment | Hyprland + Wayland |

## Security Notes

⚠️ **Important Security Considerations:**

1. **LUKS Passwords:** Use strong, unique passphrases (16+ characters)
2. **Key File:** `/boot/volume.key` is stored unencrypted on boot partition
3. **Dracut Key:** Edit dracut config to remove key from initramfs if security-critical
4. **Firewall:** Install and configure firewall post-installation (not automated)
5. **Updates:** Run `xbps-install -Su` regularly for security patches

## Contributing

Report issues or suggest improvements via GitHub issues.

## License

MIT License - See LICENSE file for details

## Support

For help with Void Linux installation: https://docs.voidlinux.org/
For LUKS/cryptsetup: https://man7.org/linux/man-pages/man8/cryptsetup.8.html
For Hyprland: https://hyprland.org/
