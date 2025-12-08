# VOID FORTRESS - Changelog

## v3.0 (Current)

### Bootstrap Enhancements
- ✅ **Expanded package selection** - Added 30+ essential packages
  - Base system: base-system-essentials, linux, linux-headers
  - Security: libfido2, tpm2-tools, libsodium
  - Network: openssh, curl, wget, dhcpcd
  - Build tools: base-devel, pkg-config
  - Utils: vim, nano, git, pciutils, hwinfo

- ✅ **Locale configuration** - Proper UTF-8 and i18n setup
  - Locale environment variables
  - Profile.d configuration
  - Libc-specific locale packages

- ✅ **Improved GRUB installation**
  - Fallback to removable if EFI fails
  - EFI mount before installation
  - Proper error handling

- ✅ **Enhanced initramfs generation**
  - Dracut configuration with proper modules
  - Kernel reconfiguration
  - Boot validation

### System Validation
- ✅ **System requirements check** (`validate_system_requirements`)
  - Root privilege verification
  - UEFI firmware detection
  - Required tools availability
  - Kernel version check (5.4+)
  - Memory availability check
  - Network connectivity test

- ✅ **Disk auto-selection** (`auto_select_disk`)
  - Priority: /dev/vda (VMs) > /dev/sda (HDD) > /dev/nvme0n1
  - Interactive selection if multiple disks
  - TTY detection for automation

### Package Improvements
- **Added critical packages:**
  - `base-system-essentials` - Essential system utilities
  - `linux` + `linux-headers` - Kernel and development
  - `openssh` - Remote access capability
  - `git` + `curl` + `wget` - Development and downloads
  - `base-devel` + `pkg-config` - Build environment
  - `tpm2-tools` - TPM support for secure boot
  - `libfido2` - Hardware token support
  - `void-repo-multilib` - 32-bit library support

### Configuration Improvements
- **Dracut enhancements:**
  - Removed problematic LVM module
  - Added proper crypt and rootfs-block modules
  - Automatic kernel version detection
  - Key file installation in initramfs

- **Network configuration:**
  - DHCP service enabled
  - Persistent DNS settings
  - SSH access (disabled by default)

- **Locale configuration:**
  - Proper UTF-8 environment
  - Timezone automatic setup
  - glibc/musl locale handling

### Error Recovery
- ✅ **Better error messages** - Clear guidance on each failure point
- ✅ **State persistence** - Installation can resume from last checkpoint
- ✅ **Validation at each step** - Early detection of issues

### Logging
- Enhanced logging with timestamps
- Log file at `/tmp/void-fortress.log`
- Tool availability logging
- Kernel version logging

## v2.x (Previous)

### Features
- Basic partition creation with sfdisk
- LUKS1 root + LUKS2 home encryption
- Musl/glibc detection
- Disk size auto-detection
- Customizable partition layout
- State machine with recovery
- Basic cryptsetup configuration
- Dracut initramfs setup

### Known Limitations
- Minimal package set (only core)
- Limited system validation
- No TPM/FIDO2 support
- Manual locale configuration needed

## Known Issues

### Resolved
- ✅ `arch-install-scripts` package not in Void repos
- ✅ `partprobe` missing on minimal systems (replaced with blockdev)
- ✅ sfdisk offset errors on small VMs (conservative sizing)
- ✅ LUKS mapper name inconsistencies (standardized to root_crypt)
- ✅ Missing HOME partition handling (optional now)

### Open
- None currently reported

## Next Release (v3.1)

### Planned Features
- [ ] TPM unlock support (no password needed if TPM present)
- [ ] Additional LUKS2 key slots for recovery
- [ ] Automated SELinux/AppArmor configuration
- [ ] Firewall (ufw/firewalld) setup
- [ ] Automatic system hardening script
- [ ] ZFS support option
- [ ] AIDE/RKHUNTER integration
- [ ] Custom kernel compilation option

### Under Consideration
- Secure boot signing support
- RAID configuration
- LVM snapshots
- Btrfs subvolume layout
- Cloud-init support
- Automated updates configuration

## Version History

| Version | Date | Status | Notes |
|---------|------|--------|-------|
| 3.0 | 2025-12 | Current | Bootstrap enhancements, system validation |
| 2.9 | 2025-12 | Stable | Fixed partition issues, added musl support |
| 2.8 | 2025-12 | Archive | Initial VM testing version |
| 2.0 | 2025-12 | Archive | State machine implementation |
| 1.0 | 2025-12 | Archive | Initial release |

## Testing

### Validated Environments
- ✅ Void Linux glibc (main repos)
- ✅ Void Linux musl (alternative repos)
- ✅ 20GB VM disk (QEMU/KVM)
- ✅ 50GB+ physical disk
- ✅ NVMe, SDA, VDA disk types
- ✅ UEFI firmware

### Test Coverage
- Bootstrap: Packages, locale, network
- Encryption: LUKS1/2, key management
- Boot: GRUB, dracut, kernel parameters
- Filesystem: Mount, UUID, fstab

## Contributing

To contribute improvements:

1. Test on minimal Void Linux ISO
2. Document any new dependencies
3. Add test cases for edge cases
4. Update changelog with version bump
5. Submit PR with clear description

## Support

For issues:
- Check `/tmp/void-fortress.log` for detailed errors
- Run `voidnx.sh debug` to show current state
- Review README.md troubleshooting section
- Check Void Linux documentation: https://docs.voidlinux.org/

## License

MIT License - See LICENSE file
