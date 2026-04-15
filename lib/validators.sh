# lib/validators.sh
# Cada fase tem um validator que roda ANTES e DEPOIS

# ══════════════════════════════════════════════
# PHASE 1: Partitioning & Encryption
# ══════════════════════════════════════════════
validate_pre_partition() {
    local errors=0
    local disk=${DISK:?}

    # Disco existe?
    if [[ ! -b "$disk" ]]; then
        log "FAIL" "Disco não encontrado: ${disk}"
        ((errors++))
    fi

    # Disco não está montado?
    if mount | grep -q "^${disk}"; then
        log "FAIL" "Disco ${disk} tem partições montadas!"
        mount | grep "^${disk}" | while read -r line; do
            log "DETAIL" "  Montado: ${line}"
        done
        ((errors++))
    fi

    # Tamanho mínimo
    local disk_size_bytes
    disk_size_bytes=$(blockdev --getsize64 "$disk" 2>/dev/null || echo 0)
    local disk_size_gb=$(( disk_size_bytes / 1073741824 ))

    if [[ $disk_size_gb -lt 20 ]]; then
        log "FAIL" "Disco muito pequeno: ${disk_size_gb}GB (mínimo: 20GB)"
        ((errors++))
    fi

    log "INFO" "Disco: ${disk} — ${disk_size_gb}GB"

    # UEFI?
    if [[ ! -d /sys/firmware/efi ]]; then
        log "FAIL" "Sistema não está em modo UEFI"
        ((errors++))
    fi

    # cryptsetup disponível?
    if ! command -v cryptsetup &>/dev/null; then
        log "FAIL" "cryptsetup não encontrado"
        ((errors++))
    fi

    # sfdisk disponível?
    if ! command -v sfdisk &>/dev/null; then
        log "FAIL" "sfdisk não encontrado"
        ((errors++))
    fi

    return $errors
}

validate_post_partition() {
    local disk=${DISK:?}
    local errors=0
    local p_prefix=""

    # NVMe usa p1, p2... — SATA/VDA usa 1, 2...
    [[ "$disk" == *"nvme"* || "$disk" == *"loop"* ]] && p_prefix="p"

    # Verifica se todas as 5 partições existem
    for i in 1 2 3 4 5; do
        local part="${disk}${p_prefix}${i}"
        if [[ ! -b "$part" ]]; then
            log "FAIL" "Partição não criada: ${part}"
            ((errors++))
        else
            local size
            size=$(blockdev --getsize64 "$part" 2>/dev/null)
            log "OK" "Partição ${part}: $(( size / 1048576 ))MB"
        fi
    done

    # Verifica GPT label
    local pttype
    pttype=$(blkid -o value -s PTTYPE "$disk" 2>/dev/null)
    if [[ "$pttype" != "gpt" ]]; then
        log "FAIL" "Tabela de partição não é GPT: ${pttype}"
        ((errors++))
    fi

    return $errors
}

# ══════════════════════════════════════════════
# PHASE 1b: LUKS validation
# ══════════════════════════════════════════════
validate_post_encryption() {
    local errors=0

    # Root LUKS1
    local root_part="${DISK}${P_PREFIX}4"
    local luks_version
    luks_version=$(cryptsetup luksDump "$root_part" 2>/dev/null |
                   grep "Version:" | awk '{print \$2}')

    if [[ "$luks_version" != "1" ]]; then
        log "FAIL" "Root não é LUKS1 (encontrado: ${luks_version:-nada})"
        ((errors++))
    else
        log "OK" "Root: LUKS${luks_version} ✓"
    fi

    # Home LUKS2 com Argon2id
    local home_part="${DISK}${P_PREFIX}5"
    luks_version=$(cryptsetup luksDump "$home_part" 2>/dev/null |
                   grep "Version:" | awk '{print \$2}')
    local kdf
    kdf=$(cryptsetup luksDump "$home_part" 2>/dev/null |
          grep -i "kdf:" | head -1 | awk '{print \$2}')

    if [[ "$luks_version" != "2" ]]; then
        log "FAIL" "Home não é LUKS2 (encontrado: ${luks_version:-nada})"
        ((errors++))
    elif [[ "$kdf" != "argon2id" ]]; then
        log "WARN" "Home LUKS2 mas KDF não é argon2id: ${kdf}"
    else
        log "OK" "Home: LUKS${luks_version} + ${kdf} ✓"
    fi

    return $errors
}

# ══════════════════════════════════════════════
# PHASE 2: Bootstrap
# ══════════════════════════════════════════════
validate_pre_bootstrap() {
    local errors=0

    # Mapper devices existem?
    for mapper in root_crypt home_crypt; do
        if [[ ! -b "/dev/mapper/${mapper}" ]]; then
            log "FAIL" "/dev/mapper/${mapper} não existe"
            ((errors++))
        fi
    done

    # Mounts corretos?
    local expected_mounts=(
        "/mnt/void"
        "/mnt/void/boot"
        "/mnt/void/boot/efi"
        "/mnt/void/home"
    )
    for mnt in "${expected_mounts[@]}"; do
        if ! mountpoint -q "$mnt" 2>/dev/null; then
            log "FAIL" "${mnt} não está montado"
            ((errors++))
        else
            log "OK" "Mount: ${mnt} ✓"
        fi
    done

    # Rede funciona? (precisa pra xbps)
    if ! ping -c1 -W5 repo-default.voidlinux.org &>/dev/null; then
        log "FAIL" "Sem acesso ao repo Void Linux"
        ((errors++))
    fi

    return $errors
}

validate_post_bootstrap() {
    local errors=0
    local rootfs="/mnt/void"

    # Diretórios essenciais existem?
    local critical_dirs=(
        "${rootfs}/bin"
        "${rootfs}/etc"
        "${rootfs}/usr"
        "${rootfs}/var"
        "${rootfs}/proc"
        "${rootfs}/sys"
        "${rootfs}/dev"
    )
    for dir in "${critical_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log "FAIL" "Diretório faltando: ${dir}"
            ((errors++))
        fi
    done

    # xbps funciona dentro do chroot?
    if [[ ! -x "${rootfs}/usr/bin/xbps-install" ]]; then
        log "FAIL" "xbps-install não encontrado no target"
        ((errors++))
    fi

    # resolv.conf copiado?
    if [[ ! -f "${rootfs}/etc/resolv.conf" ]]; then
        log "WARN" "resolv.conf não copiado — DNS vai falhar no chroot"
    fi

    return $errors
}

# ══════════════════════════════════════════════
# PHASE 3: Chroot Config
# ══════════════════════════════════════════════
validate_post_chroot() {
    local errors=0
    local rootfs="/mnt/void"

    # fstab tem todas as entradas?
    local fstab="${rootfs}/etc/fstab"
    if [[ ! -f "$fstab" ]]; then
        log "FAIL" "fstab não existe"
        ((errors++))
    else
        for entry in "/boot" "/boot/efi" "/home" "swap"; do
            if ! grep -q "$entry" "$fstab"; then
                log "FAIL" "fstab: entrada '${entry}' faltando"
                ((errors++))
            fi
        done
        log "DEBUG" "=== fstab ==="
        cat "$fstab" | while read -r line; do log "DEBUG" "  $line"; done
    fi

    # crypttab
    local crypttab="${rootfs}/etc/crypttab"
    if [[ ! -f "$crypttab" ]]; then
        log "FAIL" "crypttab não existe"
        ((errors++))
    else
        for entry in root_crypt home_crypt; do
            if ! grep -q "$entry" "$crypttab"; then
                log "FAIL" "crypttab: entrada '${entry}' faltando"
                ((errors++))
            fi
        done
    fi

    # Dracut config
    local dracut_conf="${rootfs}/etc/dracut.conf.d"
    if [[ ! -d "$dracut_conf" ]]; then
        log "WARN" "Dracut conf.d não existe"
    fi

    # GRUB
    local grub_cfg="${rootfs}/boot/grub/grub.cfg"
    if [[ ! -f "$grub_cfg" ]]; then
        log "FAIL" "grub.cfg não gerado"
        ((errors++))
    else
        # Verifica se GRUB tem referência ao LUKS
        if ! grep -q "cryptdevice\|rd.luks\|luks.uuid" "$grub_cfg"; then
            log "FAIL" "grub.cfg não referencia LUKS — boot vai falhar!"
            ((errors++))
        fi
        # Verifica kernel params de segurança
        for param in "pti=on" "vsyscall=none" "slab_nomerge"; do
            if ! grep -q "$param" "$grub_cfg" && \
               ! grep -q "$param" "${rootfs}/etc/default/grub"; then
                log "WARN" "Kernel param '${param}' não encontrado"
            fi
        done
    fi

    # User existe?
    if [[ -n "${USERNAME:-}" ]]; then
        if ! grep -q "^${USERNAME}:" "${rootfs}/etc/passwd"; then
            log "FAIL" "Usuário '${USERNAME}' não criado"
            ((errors++))
        fi
        if ! grep -q "${USERNAME}" "${rootfs}/etc/sudoers.d/"* 2>/dev/null && \
           ! grep -q "${USERNAME}" "${rootfs}/etc/sudoers" 2>/dev/null; then
            log "WARN" "Usuário '${USERNAME}' pode não ter sudo"
        fi
    fi

    # Key file
    local keyfile="${rootfs}/boot/volume.key"
    if [[ ! -f "$keyfile" ]]; then
        log "WARN" "Key file não encontrado: ${keyfile}"
    else
        local perms
        perms=$(stat -c "%a" "$keyfile")
        if [[ "$perms" != "000" && "$perms" != "400" ]]; then
            log "FAIL" "Key file com permissões inseguras: ${perms} (esperado: 000 ou 400)"
            ((errors++))
        fi
    fi

    # initramfs existe?
    local initramfs_count
    initramfs_count=$(ls "${rootfs}/boot"/initramfs-*.img 2>/dev/null | wc -l)
    if [[ $initramfs_count -eq 0 ]]; then
        log "FAIL" "Nenhum initramfs encontrado em /boot"
        ((errors++))
    else
        log "OK" "Initramfs encontrado (${initramfs_count} imagem(ns))"
    fi

    return $errors
}
