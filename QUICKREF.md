# VOID FORTRESS - Quick Reference

## Installation Methods

### 1. Interactive Installation (Recommended)
```bash
git clone https://github.com/VoidNxSEC/VoidSEC.git
cd VoidSEC
sudo bash voidnx.sh
```

### 2. Quick Menu (All Options)
```bash
bash quickstart.sh
```

### 3. Automated Installation (CI/CD)
```bash
export DISK=/dev/sda
export HOSTNAME=mypc
export USERNAME=user
export ROOT_PASS=pass
export USER_PASS=pass
export LUKS_PASS=pass
sudo bash install-auto.sh
```

### 4. Command Line Arguments
```bash
# Resume interrupted installation
sudo bash voidnx.sh resume

# Check current state
sudo bash voidnx.sh debug

# Just open LUKS and mount
sudo bash voidnx.sh mount

# Open LUKS and drop to shell
sudo bash voidnx.sh shell

# Clean up everything
sudo bash voidnx.sh clean

# Show status
sudo bash voidnx.sh status
```

## Common Scenarios

### Fresh VM Installation (20GB)
```bash
export DISK=/dev/vda
sudo bash voidnx.sh
```

### Fresh Server Installation (50GB+ SSD)
```bash
export DISK=/dev/nvme0n1
sudo bash voidnx.sh
```

### Custom Partition Sizes
```bash
# During installation, select "custom" when prompted
# Then enter sizes:
# • EFI: 512M
# • BOOT: 1G
# • SWAP: 4G
# • ROOT: 30G
# • HOME: (remainder)
```

### Resume Failed Installation
```bash
sudo bash voidnx.sh resume
# or
sudo bash voidnx.sh
```

### Manual LUKS Open
```bash
sudo bash voidnx.sh open
# Then manually:
mount /dev/mapper/root_crypt /mnt
mount /dev/mapper/home_crypt /mnt/home
mount /dev/xxx1 /mnt/boot/efi
mount /dev/xxx2 /mnt/boot
```

### Chroot Into Installation
```bash
sudo bash voidnx.sh mount
sudo bash voidnx.sh shell
# You're now in the installed system
exit
```

### Check Logs
```bash
tail -f /tmp/void-fortress.log
less /tmp/void-fortress.log
```

## Troubleshooting Commands

### Verify LUKS Setup
```bash
# List LUKS containers
sudo cryptsetup luksDump /dev/xxx4
sudo cryptsetup luksDump /dev/xxx5

# Open manually
sudo cryptsetup luksOpen /dev/xxx4 root_crypt
sudo cryptsetup luksOpen /dev/xxx5 home_crypt
```

### Check Filesystem
```bash
# List all block devices
lsblk -f

# Check specific partition
sudo fsck -n /dev/mapper/root_crypt

# Verify EFI
mount | grep efi
ls -la /boot/efi/EFI/
```

### Verify Bootloader
```bash
# Check GRUB installation
ls -la /boot/grub/
ls -la /boot/efi/EFI/void/

# List GRUB menu entries
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Check Dracut Initramfs
```bash
# List modules in initramfs
lsinitrd /boot/initramfs-*.img | head -20

# Regenerate
sudo dracut -f
```

### Manual Bootloader Repair (in chroot)
```bash
sudo bash voidnx.sh shell
# Inside chroot:
grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg
exit
```

## Development Commands

### Syntax Validation
```bash
bash -n voidnx.sh
bash -n voidnx-tui.sh
bash -n install-auto.sh
```

### Compile C TUI (if ncurses available)
```bash
make clean
make
sudo make install
voidnx-tui
```

### View Installation State
```bash
cat /tmp/void-fortress.state
```

### Reset Installation
```bash
# WARNING: This will unmount and close LUKS!
sudo bash voidnx.sh clean
```

## Security Tips

### After Installation
1. Change root and user passwords
2. Test LUKS unlock at reboot
3. Verify secure boot status
4. Enable firewall:
   ```bash
   sudo xbps-install ufw
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow ssh
   sudo ufw enable
   ```

### LUKS Key Management
```bash
# Check key slots
sudo cryptsetup luksDump /dev/xxx4

# Add recovery key
sudo cryptsetup luksAddKey /dev/xxx4 -S 1

# Remove key slot (careful!)
sudo cryptsetup luksKillSlot /dev/xxx4 0
```

### Initramfs Keys
```bash
# List keys in initramfs
lsinitrd /boot/initramfs-*.img | grep volume.key

# Regenerate without key (requires password at boot)
sudo sed -i 's|install_items.*||' /etc/dracut.conf.d/10-crypt.conf
sudo dracut -f
```

## File Locations

### Host System
```
/tmp/void-fortress.log          # Installation log
/tmp/void-fortress.state        # Current state
/tmp/void-fortress-tui.log      # TUI log (if using)
```

### Mounted Installation
```
/mnt/                           # Root filesystem
/mnt/boot                       # Boot partition
/mnt/boot/efi                   # EFI partition
/mnt/boot/volume.key            # LUKS key
/mnt/etc/crypttab              # LUKS configuration
/mnt/etc/dracut.conf.d/        # Initramfs config
/mnt/etc/default/grub          # GRUB config
/mnt/etc/fstab                 # Filesystem table
```

## Performance Tips

### During Installation
- Use wired connection (faster than WiFi)
- Increase disk I/O priority: `ionice -c2 -n0 sudo bash voidnx.sh`
- Use faster repository mirror (edit REPO_URL)

### After Installation
- Update packages: `sudo xbps-install -Su`
- Clean package cache: `sudo xbps-remove -O`
- Enable ccache for builds: `sudo xbps-install ccache`

## Reference Links

- **Void Linux Docs**: https://docs.voidlinux.org/
- **Cryptsetup Manual**: https://man7.org/linux/man-pages/man8/cryptsetup.8.html
- **Dracut Manual**: https://man7.org/linux/man-pages/man8/dracut.8.html
- **GRUB Manual**: https://www.gnu.org/software/grub/manual/
- **Linux Hardening**: https://madaidans-insecurities.github.io/linux.html

## Quick Support

**Script doesn't run:**
```bash
bash -n voidnx.sh           # Check syntax
echo $?                     # Show last error code
sudo bash voidnx.sh debug   # Show diagnostics
```

**Installation stuck:**
- Check `tail -f /tmp/void-fortress.log`
- Press `Ctrl+C` to stop
- Run `sudo bash voidnx.sh resume` to continue

**Can't boot after installation:**
1. Boot from live ISO again
2. Run `sudo bash voidnx.sh shell`
3. Troubleshoot in chroot
4. Check logs: `cat /var/log/xbps.log`

**LUKS password not working:**
1. Use recovery key from slot 1
2. Or boot from live ISO and run `sudo bash voidnx.sh open`
3. Then mount and chroot for repairs

---

**Last Updated:** 2025-12-08  
**Version:** 3.0  
**Project:** https://github.com/VoidNxSEC/VoidSEC
