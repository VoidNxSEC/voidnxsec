Phase 1: Partitioning & Encryption  ← MAIS PERIGOSO (destrutivo)
    │  sfdisk, cryptsetup luksFormat
    ▼
Phase 2: Bootstrap                  ← MAIS FRÁGIL (rede, repos)
    │  xbps-install, mount, network
    ▼
Phase 3: Chroot Config             ← MAIS COMPLEXO (estado invisível)
    │  fstab, dracut, GRUB, users
    ▼
Phase 4: Finalization              ← MAIS SILENCIOSO (falhas tardias)
       initramfs, grub-install
