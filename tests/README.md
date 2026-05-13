# Void Fortress — Suite de Testes

Quatro camadas de teste, do mais barato (estático) ao mais caro (boot real em VM).

## Layout

```
tests/
├── lib.sh                  # helpers (assert, mock, cores)
├── 01-lint.sh              # bash -n + shellcheck + checagens de regressão
├── 02-unit.sh              # funções puras com mocks (sem efeitos colaterais)
├── 03-vm-bootstrap.sh      # qemu + OVMF + ISO Void → roda voidnx.sh em disco virtual
├── 04-post-install.sh      # roda DENTRO da VM após primeiro boot, valida o sistema
├── run-all.sh              # roda 01 + 02 (offline, automatizado)
└── README.md               # este arquivo
```

## Quick start

### 1. Suíte offline (rápida, sem VM)

```bash
chmod +x tests/*.sh
./tests/run-all.sh
```

Roda **lint** (`01`) e **unit** (`02`). Cada teste tem checagens específicas
para regressão dos 7 fixes críticos do `roadmap_fixes.md`.

### 2. Bootstrap em VM (manual, interativo)

Pré-requisitos no host:
- `qemu-system-x86_64` (já tem em NixOS)
- OVMF (firmware UEFI) — autodetect; override via `OVMF_CODE`/`OVMF_VARS_TEMPLATE`
- ~25 GB livres em `tests/.vm/`
- ISO da live do Void (auto-download se não existir, ou aponte com `VOID_ISO=`)

```bash
./tests/03-vm-bootstrap.sh
```

O script:
1. Cria `tests/.vm/void-fortress.qcow2` (20G por padrão; override com `DISK_SIZE=40G`)
2. Baixa a ISO se necessário
3. Copia `voidnx.sh` + scripts de teste para `tests/.vm/shared/`
4. Boota a VM via qemu com a ISO + disco em branco
5. Te dá instruções na tela do que fazer dentro da VM

#### Dentro da VM (live ISO):

```bash
# 1. login: root / voidlinux
mkdir -p /mnt/host
mount -t 9p -o trans=virtio,version=9p2000.L hostshare /mnt/host

# 2. roda o installer
cd /mnt/host
DISK=/dev/vda bash ./voidnx.sh
```

Depois que terminar:

```bash
# desliga a VM
poweroff
```

### 3. Boot do sistema instalado (sem ISO)

```bash
BOOT_INSTALLED=1 ./tests/03-vm-bootstrap.sh
```

Boota apenas o disco — testa o caminho real de boot (LUKS unlock, GRUB, initramfs).

### 4. Validação pós-instalação

Dentro da VM, no sistema instalado:

```bash
# remontar a pasta compartilhada
mkdir -p /mnt/host
mount -t 9p -o trans=virtio,version=9p2000.L hostshare /mnt/host

sudo bash /mnt/host/04-post-install.sh
```

Checa ~30 invariantes: mounts, fstab, crypttab, GRUB, initramfs (versão correta!),
swap encriptado, volume.key presente, usuário+sudo, versões LUKS1/LUKS2 corretas.

## O que cada suíte cobre

### 01-lint.sh — análise estática

- `bash -n` em todo `*.sh` do projeto
- `shellcheck` (se instalado)
- Funções obrigatórias definidas (`detect_environment`, `partition_disk`, etc.)
- **Regressão de fixes:**
  - #1: nenhuma referência sobrando a `void_crypt`/`void-vg`
  - #3: `dracut --kver` não usa `$(uname -r)`
  - #5: `warn()` definido no chroot script
  - #6: fstab swap usa `/dev/mapper/swap`
  - #7: `trap exit_trap EXIT` antes do `case`

### 02-unit.sh — funções isoladas

Faz `source` do `voidnx.sh` (com `case` neutralizado) e testa funções:

- `p()` para nvme/sda/vda
- `detect_installation_state` com mocks de `cryptsetup`/`blkid`/`mountpoint`
- Ausência de estados removidos (`NO_LVM`)
- Ordem de operações no `generate_chroot_script` (key antes do luksAddKey)
- Detecção de KVER no chroot script
- Flag `RUN_CLEANUP_ON_EXIT` presente

### 03-vm-bootstrap.sh — integração real

- Preflight de qemu/OVMF/KVM
- Cria disco qcow2 limpo
- Boota live ISO + disco virtual
- Compartilha pasta com host (9p) → expõe `voidnx.sh` à VM
- **Você** roda o installer e desliga a VM
- Re-execute com `BOOT_INSTALLED=1` pra testar boot real

### 04-post-install.sh — validação dentro do sistema

Roda dentro da VM após primeiro boot. Checa:

- Boot UEFI ativo
- `/`, `/boot`, `/boot/efi`, `/home` montados
- `/` em `root_crypt`, `/home` em `home_crypt`
- **Swap em `/dev/mapper/swap`** (regressão fix #6)
- fstab e crypttab consistentes
- `/boot/volume.key` presente e com perm 000 (regressão fix #4)
- GRUB + EFI bootloader instalados
- **Initramfs casa com kernel rodando** (regressão fix #3)
- Initramfs contém `crypttab` + `volume.key`
- Usuário criado, no `wheel`, sudoers configurado
- Root LUKS1, Home LUKS2 (design original)

## Variáveis de ambiente úteis

| Var | Default | Descrição |
|-----|---------|-----------|
| `VM_DIR` | `tests/.vm` | Onde guardar disco/ISO |
| `DISK_IMG` | `$VM_DIR/void-fortress.qcow2` | Imagem do disco virtual |
| `DISK_SIZE` | `20G` | Tamanho do disco virtual |
| `VM_RAM` | `4096` | RAM da VM em MiB |
| `VM_CPUS` | `2` | vCPUs |
| `VOID_ISO` | `$VM_DIR/void-live.iso` | Caminho da ISO |
| `VOID_ISO_URL` | repo Void | URL pra download automático |
| `OVMF_CODE` | autodetect | Path do `OVMF_CODE.fd` |
| `OVMF_VARS_TEMPLATE` | autodetect | Path do `OVMF_VARS.fd` |
| `BOOT_INSTALLED` | `0` | Se `1`, boota só o disco (sem ISO) |
| `SKIP_DOWNLOAD` | `0` | Se `1`, falha em vez de baixar ISO |
| `VOIDNX_USER` | `nx` | Username esperado no `04-post-install.sh` |

## Fluxo recomendado de teste

```bash
# 1. Sempre antes de subir mudanças
./tests/run-all.sh

# 2. Bootstrap fresh em VM (interativo, ~30 min)
./tests/03-vm-bootstrap.sh
# (segue instruções na tela)

# 3. Reboot da VM, sem ISO
BOOT_INSTALLED=1 ./tests/03-vm-bootstrap.sh

# 4. Dentro da VM
sudo bash /mnt/host/04-post-install.sh

# 5. Se 04 ficou verde, pode commitar
```

## Troubleshooting

- **`/dev/kvm not readable`**: rode com `sudo` ou adicione seu user ao grupo `kvm`
- **OVMF não encontrado**: instale `edk2-ovmf` (Arch), `ovmf` (Debian) ou
  `nix profile install nixpkgs#OVMF`, depois exporte `OVMF_CODE=/path`
- **9p mount falha na VM**: o módulo `9p_virtio` precisa estar no kernel da live
  (Void live tem por padrão)
- **Bootstrap trava em `passwd`**: é interativo — entre as senhas no terminal qemu
- **VM lenta sem KVM**: TCG é 10–50x mais lento; espere ~3h em vez de ~30min
