#!/bin/bash
# modules/01-partitioning.sh

log_phase "partitioning"
log_system_snapshot "pre-partition"

log_info "Detectando disco..." "\"disk\":\"${DISK}\""

# Cada comando gera JSON estruturado com timing + output
log_cmd "Wipando assinaturas" wipefs -a "$DISK"

log_cmd "Criando tabela GPT" sfdisk "$DISK" <<EOF
label: gpt
${DISK}1 : size=${EFI_SIZE},  type=uefi
${DISK}2 : size=${BOOT_SIZE}, type=linux
${DISK}3 : size=${SWAP_SIZE}, type=swap
${DISK}4 : size=${ROOT_SIZE}, type=linux
${DISK}5 :                    type=linux
EOF

log_cmd "Formatando EFI" mkfs.fat -F32 "${DISK}${P}1"
log_cmd "Formatando BOOT" mkfs.ext4 -L boot "${DISK}${P}2"

log_phase "encryption"

log_info "LUKS1 no root (AES-XTS-Plain64, SHA512)"
log_cmd "LUKS1 format root" \
    cryptsetup luksFormat --type luks1 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --iter-time 5000 \
    "${DISK}${P}4"

log_info "LUKS2 no home (Argon2id)"
log_cmd "LUKS2 format home" \
    cryptsetup luksFormat --type luks2 \
    --pbkdf argon2id \
    "${DISK}${P}5"

log_system_snapshot "post-encryption"
log_ok "Partitioning + encryption completo"
