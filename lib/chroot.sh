# lib/chroot-safe.sh

# Chroot seguro com bind mounts e cleanup garantido
safe_chroot() {
    local rootfs="/mnt/void"
    local cmd=("$@")

    # Bind mounts necessários
    mount --bind /proc "${rootfs}/proc" 2>/dev/null || true
    mount --bind /sys  "${rootfs}/sys"  2>/dev/null || true
    mount --bind /dev  "${rootfs}/dev"  2>/dev/null || true
    mount --bind /dev/pts "${rootfs}/dev/pts" 2>/dev/null || true

    # Resolve DNS dentro do chroot
    cp -L /etc/resolv.conf "${rootfs}/etc/resolv.conf" 2>/dev/null || true

    log "CHROOT" "Executando: ${cmd[*]}"

    # Executa com captura de erro
    local exit_code=0
    chroot "${rootfs}" "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE" || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log "FAIL" "Chroot command falhou (exit: ${exit_code}): ${cmd[*]}"
    fi

    return $exit_code
}

# Cleanup de chroot mounts (chamado no rollback)
cleanup_chroot_mounts() {
    local rootfs="/mnt/void"
    for m in dev/pts dev sys proc; do
        umount -l "${rootfs}/${m}" 2>/dev/null || true
    done
}

# ══════════════════════════════════════════════
# Validação GRUB+LUKS (o ponto mais crítico)
# ══════════════════════════════════════════════
validate_boot_chain() {
    local rootfs="/mnt/void"
    local errors=0

    echo "═══ BOOT CHAIN VALIDATION ═══"

    # 1. GRUB instalado no EFI?
    local efi_grub="${rootfs}/boot/efi/EFI/void/grubx64.efi"
    if [[ ! -f "$efi_grub" ]]; then
        # Tenta path alternativo
        efi_grub=$(find "${rootfs}/boot/efi" -name "grub*.efi" 2>/dev/null | head -1)
        if [[ -z "$efi_grub" ]]; then
            log "FAIL" "GRUB EFI binary não encontrado!"
            ((errors++))
        fi
    fi
    [[ -f "${efi_grub:-}" ]] && log "OK" "GRUB EFI: ${efi_grub}"

    # 2. grub.cfg referencia LUKS UUID correto?
    local root_part="${DISK}${P_PREFIX}4"
    local root_uuid
    root_uuid=$(blkid -s UUID -o value "$root_part" 2>/dev/null)

    if [[ -n "$root_uuid" ]]; then
        local grub_cfg="${rootfs}/boot/grub/grub.cfg"
        if [[ -f "$grub_cfg" ]] && ! grep -q "$root_uuid" "$grub_cfg"; then
            log "FAIL" "grub.cfg NÃO contém UUID do root LUKS: ${root_uuid}"
            log "FAIL" "O sistema NÃO vai conseguir desencriptar no boot!"
            ((errors++))
        else
            log "OK" "GRUB referencia root UUID: ${root_uuid}"
        fi
    fi

    # 3. Dracut incluiu módulo crypt?
    local initramfs
    initramfs=$(ls "${rootfs}/boot"/initramfs-*.img 2>/dev/null | head -1)
    if [[ -n "$initramfs" ]]; then
        # Verifica módulos dentro do initramfs
        if command -v lsinitrd &>/dev/null; then
            if ! lsinitrd "$initramfs" 2>/dev/null | grep -q "crypt"; then
                log "FAIL" "initramfs NÃO contém módulo crypt!"
                log "FAIL" "Dracut precisa de: add_dracutmodules+=' crypt dm '"
                ((errors++))
            else
                log "OK" "initramfs contém módulo crypt"
            fi
        fi

        # Tamanho sanity check
        local img_size
        img_size=$(stat -c %s "$initramfs")
        if [[ $img_size -lt 5000000 ]]; then  # < 5MB é suspeito
            log "WARN" "initramfs muito pequeno ($(( img_size / 1024 ))KB) — pode estar incompleto"
        else
            log "OK" "initramfs size: $(( img_size / 1048576 ))MB"
        fi
    fi

    # 4. /etc/default/grub tem CMDLINE correto?
    local default_grub="${rootfs}/etc/default/grub"
    if [[ -f "$default_grub" ]]; then
        local cmdline
        cmdline=$(grep "^GRUB_CMDLINE_LINUX=" "$default_grub")
        log "DEBUG" "GRUB_CMDLINE: ${cmdline}"

        # Deve conter referência ao LUKS
        if ! echo "$cmdline" | grep -qE "rd\.luks|cryptdevice"; then
            log "FAIL" "GRUB_CMDLINE não tem rd.luks/cryptdevice"
            ((errors++))
        fi

        # Security params
        for param in "pti=on" "vsyscall=none"; do
            echo "$cmdline" | grep -q "$param" || \
                log "WARN" "Faltando kernel param: ${param}"
        done
    fi

    echo ""
    if [[ $errors -gt 0 ]]; then
        log "FATAL" "Boot chain tem ${errors} problema(s) CRÍTICO(s)"
        log "FATAL" "O sistema PROVAVELMENTE não vai bootar!"
        return 1
    else
        log "OK" "Boot chain validada — sistema deve bootar ✓"
        return 0
    fi
}
