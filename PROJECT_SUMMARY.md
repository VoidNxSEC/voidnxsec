# VOID FORTRESS - Project Summary

## 📋 Overview

**VOID FORTRESS** é um sistema de instalação completamente integrado para Void Linux com criptografia de disco completo (Full Disk Encryption). O projeto foi desenvolvido em múltiplos estágios com melhorias iterativas baseadas em testes reais em VMs e feedback de validação de sistema.

## 🎯 Objetivos Alcançados

### ✅ Fase 1: Correções Fundamentais (v1.0-2.0)
- Padronização de nomes de mapper LUKS (`void_crypt` → `root_crypt`)
- Correção da máquina de estados (remoção de funções não-existent)
- Limpeza de lógica de chroot

### ✅ Fase 2: Suporte para VMs e Múltiplas Arquiteturas (v2.5-2.8)
- Detecção automática de discos (vda/sda/nvme)
- Suporte para musl e glibc
- Detecção de tamanho de disco com redimensionamento adaptativo
- Substituição de cfdisk interativo por sfdisk automático

### ✅ Fase 3: Correção de Particionamento (v2.9)
- Resolução de erros de offset sfdisk
- Validação de existência de partições antes de operações LUKS
- Tratamento de instalações parciais

### ✅ Fase 4: Remodelagem de Arquitetura (v3.0)
- Validação completa de requisitos do sistema
- Pacotes de bootstrap expandidos
- Configuração de locale e inicialização adequada
- Melhor tratamento de erros com mensagens úteis
- Suporte para TPM, FIDO2 e outras tecnologias modernas

### ✅ Fase 5: Ferramentas Auxiliares e Documentação
- Interface de menu interativa (quickstart.sh)
- Instalação automatizada para CI/CD (install-auto.sh)
- Interface TUI em C com ncurses (voidnx-tui.c)
- Documentação completa (README, CHANGELOG, QUICKREF)

## 📁 Arquitetura do Projeto

```
VoidSEC/
├── voidnx.sh                 # 🔵 Instalador principal em bash (1150+ linhas)
├── voidnx-tui.sh             # 🔵 Interface TUI em bash (wrapper)
├── voidnx-tui.c              # 🟡 Interface TUI em C (ncurses)
├── Makefile                  # 🟢 Sistema de compilação
├── quickstart.sh             # 🟢 Menu interativo
├── install-auto.sh           # 🟢 Instalação automatizada
├── README.md                 # 📘 Documentação principal
├── CHANGELOG.md              # 📘 Histórico de versões
└── QUICKREF.md               # 📘 Guia rápido
```

## 🔧 Componentes Técnicos

### Instalador Principal (voidnx.sh)

**Funcionalidades:**
- Máquina de estados com 12+ estados de detecção
- Particionamento GPT automático com sfdisk
- LUKS1 (root) + LUKS2 (home) com Argon2id
- Detecção e configuração automática de libc
- Bootstrap com 30+ pacotes essenciais
- Configuração de chroot com kernel, GRUB e dracut
- Sistema de recuperação e retomada

**Funcionalidades Principais:**
```bash
# Função de Detecção
detect_installation_state()       # Máquina de estados
detect_environment()              # Libc, arch, live mode
detect_disk_size_and_adjust()     # Tamanho disco e sugestões
validate_system_requirements()    # UEFI, ferramentas, network

# Funções de Instalação
partition_disk()                  # GPT com sfdisk
setup_luks()                      # Criptografia
open_luks()                       # Abertura LUKS
mount_filesystems()               # Montagem com validação
bootstrap_system()                # Instalação xbps
generate_chroot_script()          # Configuração pós-bootstrap
run_chroot_config()               # Execução em chroot

# Funções Auxiliares
save_state() / load_state()       # Persistência
prepare_chroot() / cleanup_chroot()  # Ambiente chroot
show_status() / show_banner()     # Interface
cleanup()                         # Limpeza segura
```

### Layout de Partições

**Disco 20GB (VM):**
```
/dev/vda1 (512M)  → EFI System (vfat)
/dev/vda2 (512M)  → BOOT (ext4)
/dev/vda3 (1G)    → SWAP (LUKS1 + swap)
/dev/vda4 (8G)    → ROOT (LUKS1 + ext4)
/dev/vda5 (≈9.5G) → HOME (LUKS2 + ext4)
```

**Disco 50GB+ (SSD):**
```
/dev/xxx1 (512M)  → EFI System
/dev/xxx2 (1G)    → BOOT
/dev/xxx3 (2-4G)  → SWAP
/dev/xxx4 (15-30G)→ ROOT
/dev/xxx5 (rest)  → HOME
```

### Configuração de Criptografia

**LUKS1 (Root):**
- Cipher: AES-XTS-Plain64
- Hash: SHA512
- Iter time: 5000ms (PBKDF2)
- Key size: 512 bits

**LUKS2 (Home):**
- PBKDF: Argon2id
- Memory: 1GB
- Parallelism: 4
- Time: 3

**LUKS Key File:**
- Gerado: `/boot/volume.key` (64 bytes random)
- Adicionado ao crypttab para boot automático
- Integrado ao initramfs via dracut

### Sistema de Pacotes

**Pacotes Base (30+):**
```
Essenciais: base-system, base-system-essentials, linux, linux-headers
Criptografia: cryptsetup, libfido2, tpm2-tools, libsodium
Boot: grub-x86_64-efi, efibootmgr, dracut
Sistema: lvm2, e2fsprogs, dosfstools, parted
Rede: openssh, curl, wget, dhcpcd
Dev: base-devel, pkg-config, git
Utils: vim, nano, pciutils, hwinfo, tzdata
Repos: void-repo-nonfree, void-repo-multilib
Locale: musl-locales ou glibc-locales
```

**Detecção de Libc:**
```bash
# Teste via ldd
ldd --version | grep musl  → musl
else                       → glibc

# Repositories
musl → https://repo-default.voidlinux.org/current/musl
glibc → https://repo-default.voidlinux.org/current
```

## 🛠️ Ferramentas Auxiliares

### quickstart.sh - Menu Interativo
```bash
Menu options:
  1) Fresh Installation (interactive)
  2) Fresh Installation (express VM)
  3) Fresh Installation (large disk)
  4) Resume Interrupted Installation
  5) Check Installation Status
  6) Open LUKS and Mount Only
  7) Interactive Shell (debug)
  8) Clean Up and Unmount
  9) View Installation Log
```

### install-auto.sh - Automação CI/CD
```bash
Variáveis de Ambiente:
  DISK / HOSTNAME / USERNAME / TIMEZONE / LOCALE
  ROOT_PASS / USER_PASS / LUKS_PASS

Opções:
  DRY_RUN=true              # Sem mudanças
  SKIP_VALIDATION=true      # Pular validação
  AUTO_REBOOT=true          # Reinicializar após
  LOG_FILE=...              # Log customizado
```

## 📊 Estatísticas do Projeto

| Componente | Linhas | Tipo | Status |
|-----------|--------|------|--------|
| voidnx.sh | 1,150 | Bash | ✅ Funcional |
| voidnx-tui.sh | 250 | Bash | ✅ Funcional |
| voidnx-tui.c | 500 | C | ✅ Código pronto |
| install-auto.sh | 200 | Bash | ✅ Funcional |
| quickstart.sh | 180 | Bash | ✅ Funcional |
| Documentação | 1,200 | Markdown | ✅ Completa |
| **Total** | **3,480** | **Multi-lang** | **✅ Completo** |

## 🔐 Recursos de Segurança

### Criptografia
- ✅ LUKS1 + LUKS2 com Argon2id
- ✅ Chaves de 512 bits AES-XTS
- ✅ Key file com 64 bytes entropy
- ✅ Suporte a múltiplos key slots

### Boot
- ✅ UEFI obrigatório (sem BIOS)
- ✅ GRUB com cryptodisk
- ✅ Dracut initramfs
- ✅ Kernel hardening parameters

### Sistema
- ✅ AppArmor pronto
- ✅ TPM2 tools
- ✅ FIDO2/libfido2
- ✅ SELinux compatibility

### Kernel Hardening
```bash
# Parâmetros ativos
pti=on                    # Page Table Isolation
vsyscall=none             # VSYSCALL desabilitado
slab_nomerge              # Slab merging off
page_poison=1             # Page poisoning
init_on_alloc=1           # Init allocation
init_on_free=1            # Init on free
lockdown=confidentiality  # Lockdown mode
apparmor=1                # AppArmor enabled
```

## 🧪 Testes Realizados

### Ambientes Validados
- ✅ Void Linux glibc (main repos)
- ✅ Void Linux musl (alternative repos)
- ✅ QEMU/KVM VM (20GB vda)
- ✅ 50GB+ SSD (nvme/sda)
- ✅ UEFI firmware

### Casos de Teste
| Caso | Status | Notas |
|------|--------|-------|
| Bootstrap glibc | ✅ Pass | Pacotes instalados |
| Bootstrap musl | ✅ Pass | Locale ajustado |
| Particionamento 20GB | ✅ Pass | Tamanhos conservadores |
| Particionamento 50GB+ | ✅ Pass | Layout otimizado |
| LUKS setup | ✅ Pass | Keys funcionando |
| Mount/chroot | ✅ Pass | Sistema operacional |
| GRUB install | ✅ Pass | Boot testado |
| Resume recovery | ✅ Pass | Estado persistido |

### Bugs Encontrados e Resolvidos

| Bug | Causa | Solução | Versão |
|-----|-------|---------|--------|
| arch-install-scripts not found | Package não existe | Removido | 2.5 |
| partprobe missing | Ferramenta não em Void mínimo | blockdev fallback | 2.7 |
| sfdisk offset error | ROOT_SIZE muito grande | Tamanho conservador | 2.9 |
| LUKS mapper missing | Partição não existia | Validação antes | 2.9 |
| Mount failure | Paths não existem | Checks adicionais | 3.0 |

## 📚 Documentação

### README.md (360 linhas)
- Características e requisitos
- Métodos de instalação (CLI, GUI, TUI)
- Layout de partições
- Troubleshooting detalhado
- Referências de segurança

### CHANGELOG.md (240 linhas)
- Histórico de versões
- Melhorias por release
- Issues resolvidas
- Roadmap futuro

### QUICKREF.md (300 linhas)
- Comandos rápidos
- Cenários comuns
- Troubleshooting
- Dicas de performance

## 🚀 Como Usar

### Instalação Rápida
```bash
git clone https://github.com/VoidNxSEC/VoidSEC.git
cd VoidSEC
sudo bash voidnx.sh
```

### Menu Interativo
```bash
bash quickstart.sh
```

### Automação
```bash
export DISK=/dev/sda HOSTNAME=pc USERNAME=user
export ROOT_PASS=... USER_PASS=... LUKS_PASS=...
sudo bash install-auto.sh
```

## 🔄 Fluxo de Instalação

```
START
  ↓
[Validar Sistema] → UEFI, ferramentas, network
  ↓
[Selecionar Disco] → Auto-detect ou choose
  ↓
[Detectar Tamanho] → Sugerir partições
  ↓
[Particionar] → sfdisk GPT
  ↓
[Criptografia] → LUKS1 + LUKS2
  ↓
[Abrir LUKS] → Mappers criados
  ↓
[Montar FS] → /mnt estruturado
  ↓
[Bootstrap] → xbps-install pacotes
  ↓
[Chroot Config] → locale, users, boot
  ↓
[GRUB Install] → EFI bootloader
  ↓
[Dracut Setup] → initramfs
  ↓
READY
  ↓
[Reboot]
```

## 🎓 Lições Aprendidas

1. **sfdisk é mais confiável que sgdisk** para instalação não-interativa
2. **Tamanhos conservadores de partição** evitam erros em VMs pequenas
3. **Validação prévia de block devices** previne falhas em stage 2
4. **Estado persistido** permite recuperação de falhas
5. **Multilib repositories** necessárias para compatibilidade
6. **Dracut sem LVM** é mais simples e confiável para FDE simples

## 🔮 Próximas Melhorias (Roadmap)

### v3.1 (Próximo)
- [ ] TPM unlock automático
- [ ] Automated system hardening
- [ ] Additional LUKS key slots
- [ ] SELinux/AppArmor enforcement

### v4.0 (Futuro)
- [ ] ZFS support
- [ ] Btrfs subvolumes
- [ ] Multi-OS boot (Grub menu)
- [ ] Cloud-init integration

### Experimental (dev branch)
- [ ] C TUI compilation
- [ ] GUI installer preview
- [ ] Network boot support

## 📖 Referências

- **Void Linux**: https://voidlinux.org/
- **Cryptsetup**: https://gitlab.com/cryptsetup/cryptsetup
- **Dracut**: https://dracut.wiki.kernel.org/
- **GRUB**: https://www.gnu.org/software/grub/
- **Linux Hardening**: https://madaidans-insecurities.github.io/linux.html

## 📄 Licença

MIT License - Veja LICENSE para detalhes

## 👥 Contribuindo

1. Faça fork do repositório
2. Crie feature branch
3. Teste em VM antes de PR
4. Documente mudanças
5. Submit pull request

## 📞 Suporte

- GitHub Issues: https://github.com/VoidNxSEC/VoidSEC/issues
- Logs: `/tmp/void-fortress.log`
- Debug: `sudo bash voidnx.sh debug`

---

**Versão**: 3.0  
**Data**: 2025-12-08  
**Status**: ✅ Production Ready  
**Linhas de Código**: 3,480+  
**Documentação**: Completa
