# VoidNxSEC — Arquitetura Real (escrita pra mim mesmo)

> Documento honesto. Descreve o que **existe**, o que **está conectado de verdade**, e o que **é visão mas ainda não funciona junto**.

---

## O que é isso

Um sistema unificado de bootstrap e deploy de OS com dois alvos principais:

1. **Void Linux** — instalação bare metal com FDE (Full Disk Encryption)
2. **NixOS** — deploy declarativo via nixos-anywhere + flakes

A ideia maior (Big Picture) é que cada fase da instalação emita eventos JSONL estruturados, formando um **ledger criptográfico** do estado do sistema. Cada fase só avança se o hash da fase anterior foi verificado. É uma supply chain para o OS. Isso está no papel e em partes do código — ainda não está integrado de ponta a ponta.

---

## Estrutura de arquivos

```
voidnxsec/
├── voidnx.sh              ← Instalador principal Void Linux (1283 linhas)
├── voidnx-tui.sh          ← Wrapper TUI menu-driven (323 linhas)
├── voidnx-tui.c           ← TUI em C (ncurses) — existe mas não integrado
├── install-auto.sh        ← Wrapper CI/CD não-interativo (235 linhas)
├── quickstart.sh          ← Entry point rápido
│
├── lib/
│   ├── chroot.sh          ← safe_chroot + validate_boot_chain
│   ├── state.sh           ← Máquina de estados NixOS (6 estados)
│   ├── validators.sh      ← Pre/post validators por fase
│   ├── logger.sh          ← Logger v1
│   ├── logger_v2.sh       ← Logger v2 (JSONL)
│   └── rollback.sh        ← Rollback handler
│
├── modules/
│   └── 01-partitioning.sh ← Módulo de particionamento (logging estruturado)
│
├── scripts/
│   ├── bootstrap-nixos.sh ← Deploy NixOS via nixos-anywhere (172 linhas)
│   ├── enroll-tpm.sh      ← Enrolla TPM2 no LUKS (PCR 7+9)
│   └── audit.sh           ← Auditoria pós-install
│
├── nixos/
│   ├── hosts/
│   │   ├── kernelcore/    ← Laptop atual (Intel + RTX 3050, LUKS1, Bahia)
│   │   ├── desktop/       ← Desktop offload (BLOCKED: hardware.nix sem UUIDs)
│   │   ├── laptop/        ← Template genérico
│   │   └── server/        ← Template servidor (voidnx-server)
│   └── modules/
│       ├── common/        ← boot, impermanence, networking, security, secrets, users
│       ├── desktop/       ← nvidia (prime offload), offload (nix-serve)
│       ├── laptop/        ← networking-wifi, suspend
│       ├── network/       ← tailscale
│       └── server/        ← monitoring, services
│
├── flake.nix              ← Flake com todos os hosts + dev shells
├── flake.lock
├── secrets/               ← sops-nix secrets
│   ├── .sops.yaml
│   └── secrets.yaml
│
├── schema/
│   └── log-event.json     ← Schema JSONL dos eventos
│
├── nix/
│   ├── c.nix / cpp.nix / go.nix / rust.nix ← Dev shells por linguagem
│
├── go-service/            ← Serviço Go (orquestração/fleet) — STUB
├── rust-service/          ← Serviço Rust (verificação de hashes) — STUB
├── c-app/                 ← App C placeholder
│
├── tests/
│   ├── 01-lint.sh         ← shellcheck
│   ├── 02-unit.sh         ← unit tests
│   ├── 03-vm-bootstrap.sh ← bootstrap em VM
│   ├── 04-post-install.sh ← verificação pós-install
│   ├── 05-nixos-vm.sh     ← NixOS em VM
│   └── run-all.sh
│
├── tools/
│   ├── analyze-log.sh     ← Analisa JSONL
│   ├── snapshot.sh        ← Snapshot do sistema
│   └── validate-boot.sh   ← Valida boot chain
│
├── references/            ← Implementações de referência / patterns
│   ├── checkpoints.sh
│   ├── error-handling.sh
│   ├── pre-flight.sh
│   └── structured-logging.sh
│
└── .github/workflows/
    ├── ci.yml
    ├── nixos-bootstrap.yml
    ├── test-installer.yml
    └── test-void.yml
```

---

## Track 1 — Void Linux Installer (`voidnx.sh`)

### Fluxo de execução

```
main()
  ├── detect_environment()        → libc (musl/glibc), arch, IS_LIVE, PART_SUFFIX
  ├── validate_system_requirements() → ferramentas, UEFI, memória, rede
  ├── auto_select_disk()          → nvme > vda > sda > choose_disk() interativo
  ├── detect_disk_size_and_adjust() → sugere tamanhos por faixa (< 30G / < 60G / 60G+)
  │
  └── detect_installation_state()  → retorna STATE|DETAILS
        └── handle_state(STATE)    → executa apenas as fases pendentes
```

### Máquina de estados (12 estados Void Linux)

```
NO_DISK
  → NO_PARTITIONS      → partition_disk() + setup_luks() + open_luks() + ...
  → NOT_ENCRYPTED      → setup_luks() + open_luks() + ...
  → PARTIAL_ENCRYPTED  → setup_luks() + open_luks() + ...
  → LUKS_CLOSED        → open_luks() + mount_filesystems() + ...
  → ROOT_OPEN_HOME_CLOSED
  → NO_ROOT_FS         → open_luks() + mount_filesystems() + bootstrap_system() + ...
  → NO_HOME_FS
  → NOT_MOUNTED        → mount_filesystems() + ...
  → PARTIAL_MOUNT
  → NO_SYSTEM          → bootstrap_system() + generate_fstab() + ...
  → NOT_CONFIGURED     → generate_chroot_script() + run_chroot_config()
  → READY              → show_final_status()
```

O script pode ser interrompido em qualquer ponto e retomado (`./voidnx.sh resume`) — ele detecta o estado atual e continua de onde parou.

### Layout de disco (5 partições)

```
nvme0n1 (ou sda/vda)
├── p1  EFI     512M   vfat F32              plaintext
├── p2  BOOT    1G     ext4                  plaintext  ← key file vive aqui
├── p3  SWAP    8G     random key (crypttab) LUKS swap
├── p4  ROOT    50G    LUKS1 (AES-XTS/SHA512/5000ms)
└── p5  HOME    rest   LUKS2 (Argon2id, mem dinâmica baseada em RAM)
```

**Por que LUKS1 no root?** GRUB não consegue ler LUKS2 nativamente. O GRUB precisa decriptar o `/boot/grub/grub.cfg` antes de passar pra initramfs — então o root precisa ser LUKS1.

**Por que LUKS2 no home?** O home é desbloqueado pelo initramfs (dracut), que já suporta LUKS2 + Argon2id. Argon2id é memory-hard — mais resistente a ataque de força bruta com GPU.

### Key file (`/boot/volume.key`)

- 64 bytes aleatórios gerados no host antes do chroot
- Adicionado como key slot do LUKS1 (root) com `luksAddKey`
- Fica em `/boot` (partição **não** encriptada) com permissões `000`
- **Trade-off consciente**: quem tiver acesso físico ao disco consegue o key file — mas aí também consegue o LUKS header. A proteção real é a passphrase.
- Permite boot automático: dracut inclui o key file no initramfs e abre o root sem interação

### Configuração de segurança no kernel

```
GRUB_CMDLINE_LINUX_DEFAULT:
  loglevel=4
  mitigations=auto
  lockdown=confidentiality
  init_on_alloc=1
  init_on_free=1
  page_poison=1
  vsyscall=none
  slab_nomerge
  pti=on

GRUB_CMDLINE_LINUX:
  rd.luks.uuid=<UUID>
  root=/dev/mapper/root_crypt
```

AppArmor está **comentado** — o kernel Void padrão não compila com `CONFIG_SECURITY_APPARMOR=y`. Pra ativar: instala o pacote `apparmor` e adiciona `apparmor=1 security=apparmor` manualmente.

### Subcomandos do `voidnx.sh`

```bash
./voidnx.sh           # instala / retoma (default)
./voidnx.sh resume    # força retomada
./voidnx.sh status    # lsblk + estado dos mappers/mounts (read-only)
./voidnx.sh debug     # detect_environment + detect_installation_state (read-only)
./voidnx.sh open      # abre LUKS
./voidnx.sh mount     # abre LUKS + monta
./voidnx.sh chroot    # open + mount + chroot /mnt /bin/bash
./voidnx.sh shell     # igual chroot mas -i (interativo)
./voidnx.sh clean     # desmonta tudo e fecha LUKS
```

---

## Track 2 — NixOS (`scripts/bootstrap-nixos.sh` + `nixos/`)

### Fluxo de deploy

```
bootstrap-nixos.sh <profile> <target-ip> [--disk DEV] [--luks-pass FILE] [--dry-run]

  preflight:       root? nix? ssh? age?
  target-select:   profile=server → /dev/sda
                   profile=laptop → /dev/nvme0n1
  luks-setup:      recebe passphrase via arquivo ou prompt (confirma duas vezes)
  deploy:          nixos-anywhere --flake .#voidnx-<profile> \
                     --target-host root@IP \
                     --disk-encryption-keys /tmp/luks-pass <file>
  post-deploy:     instruções: enroll-tpm.sh, sbctl, lynis
```

O nixos-anywhere cuida do particionamento via **disko** (declarado no flake) e da instalação base. O script é só o wrapper com logging JSONL e gerência de passphrase.

### Hosts NixOS

| Host | Hardware | Estado | Bloqueio |
|------|----------|--------|---------|
| `kernelcore` | Laptop Intel + RTX 3050, 477GB NVMe, LUKS1 | Phase 1 ativo | nenhum |
| `desktop` | Desktop offload, 1TB, Nix cache + remote builds + NFS | BLOCKED | hardware.nix precisa de UUIDs reais |
| `laptop` | Template genérico | template | — |
| `server` | Template servidor | template | — |

### Módulos NixOS e o que fazem

**`common/`**
- `boot.nix` — systemd-boot ou GRUB dependendo do host, kernel params de segurança
- `impermanence.nix` — opt-in: raiz em tmpfs, persiste só `/persist` (não ativo no kernelcore ainda)
- `networking.nix` — NetworkManager, DNS over TLS
- `security.nix` — sudo timeout=0, kernel lockdown, proteções de memória
- `secrets.nix` — sops-nix, age keys por host
- `users.nix` — usuário `nx`, grupos, shell zsh

**`desktop/`**
- `nvidia.nix` — PRIME offload (iGPU para display, RTX pra compute/gaming sob demanda)
- `offload.nix` — nix-serve na porta 5000 (binary cache pra outros hosts), configuração como remote builder

**`laptop/`**
- `networking-wifi.nix` — iwd ou NetworkManager wifi profiles
- `suspend.nix` — hibernate via swap encriptado, lid close actions

**`network/`**
- `tailscale.nix` — Tailscale declarativo, rotas, ACLs

**`server/`**
- `monitoring.nix` — Prometheus + Grafana ou exporters
- `services.nix` — serviços do servidor (nginx, etc.)

### Fase de segurança (kernelcore)

```
Phase 1 (atual):  LUKS1 + systemd-boot + NVIDIA PRIME + Tailscale
Phase 2 (próxim): lanzaboote (Secure Boot), o módulo já está importado mas com stub disabled
Phase 3:          TPM2 enroll (enroll-tpm.sh) após Secure Boot ativo
                  (TPM binding a PCR 7+9 — PCR 0 evitado: quebra em firmware updates)
```

---

## Logging System

### Dois loggers, dois contextos

**`lib/logger.sh` (v1)** — logging simples colorido para terminal, usado pelo `voidnx.sh`.

**`lib/logger_v2.sh` + JSONL** — logging estruturado, usado por `scripts/bootstrap-nixos.sh` e `modules/01-partitioning.sh`:

```json
{
  "ts": "2026-07-07T05:00:00+00:00",
  "level": "OK",
  "phase": "deploy",
  "msg": "nixos-anywhere deploy complete",
  "pid": 1234,
  "boot_id": "...",
  "elapsed_ms": 42000
}
```

Os eventos ficam em `/tmp/voidnx-nixos-bootstrap.jsonl` e podem ser analisados por `tools/analyze-log.sh`.

---

## Validators (`lib/validators.sh`)

Cada fase tem validadores pre e post que retornam contagem de erros:

| Validator | Checa |
|-----------|-------|
| `validate_pre_partition` | disco existe, não montado, >= 20GB, UEFI, cryptsetup/sfdisk |
| `validate_post_partition` | 5 partições existem, GPT label |
| `validate_post_encryption` | p4=LUKS1, p5=LUKS2+Argon2id |
| `validate_pre_bootstrap` | mappers abertos, mounts corretos, rede pro repo |
| `validate_post_bootstrap` | dirs essenciais, xbps no target, resolv.conf |
| `validate_post_chroot` | fstab, crypttab, dracut conf, grub.cfg com LUKS UUID, user criado, key file com perms 000, initramfs existe |

O `lib/chroot.sh` tem também `validate_boot_chain()` — verifica se o grub.cfg referencia o UUID correto do LUKS, se o initramfs tem o módulo `crypt`, e se os kernel params de segurança estão presentes.

---

## O que está conectado vs. o que não está

### Conectado e funcionando
- `voidnx.sh` completo com state machine, LUKS, chroot, GRUB
- `voidnx-tui.sh` como wrapper do `voidnx.sh`
- `install-auto.sh` como wrapper CI do `voidnx.sh`
- `scripts/bootstrap-nixos.sh` com nixos-anywhere
- `scripts/enroll-tpm.sh` standalone
- `nixos/hosts/kernelcore` e `nixos/hosts/server/laptop` (templates)
- `flake.nix` com todos os hosts + dev shells por linguagem
- `tests/` com CI no GitHub Actions

### Desconectado / em progresso
- `lib/validators.sh` e `lib/chroot.sh` existem mas **não são sourced** pelo `voidnx.sh` — são referências separadas. O voidnx.sh tem sua própria validação inline.
- `modules/01-partitioning.sh` usa `log_cmd`/`log_phase` que não existem no voidnx.sh — é um módulo orphan (provavelmente destinado a um refactor do voidnx.sh em módulos).
- `lib/state.sh` define estados NixOS mas não é chamado por bootstrap-nixos.sh ainda.
- `rust-service/` e `go-service/` são stubs — a visão do ledger criptográfico ainda não chegou aqui.
- `voidnx-tui.c` existe mas não compila dentro do fluxo — provavelmente esboço de uma TUI em ncurses pra substituir a versão bash.
- `nixos/hosts/desktop/hardware.nix` — UUIDs em branco, deploy bloqueado.

### Inconsistências a resolver
- `voidnx.sh` monta em `/mnt` mas `lib/chroot.sh` hardcoda `/mnt/void` — se a lib for integrada vai precisar parametrizar.
- `install-auto.sh` clona de `github.com/VoidNxSEC/VoidSEC.git` — verificar se esse repo existe e é o certo.
- Dois loggers com APIs diferentes (`log/warn/error` vs `log_info/log_ok/log_fail`) — vai precisar de unificação quando os módulos forem integrados.

---

## Próximas melhorias óbvias

1. **Preencher `hardware.nix` do desktop** com UUIDs reais → desbloqueia deploy
2. **Integrar `lib/validators.sh`** no `voidnx.sh` — substituir validações inline
3. **Refatorar `voidnx.sh` em módulos** usando o pattern de `modules/01-partitioning.sh` + logger_v2
4. **Unificar logging** pra JSONL em todo o código — voidnx.sh + módulos + bootstrap-nixos
5. **Ativar impermanence** no kernelcore (Phase 2)
6. **lanzaboote + sbctl** no kernelcore (Secure Boot)
7. **enroll-tpm.sh** após Secure Boot ativo
8. **Completar rust-service** como verificador de hashes do JSONL ledger

---

## Referência rápida

```bash
# Instalar Void Linux
sudo bash voidnx.sh

# Deploy NixOS via nixos-anywhere
sudo bash scripts/bootstrap-nixos.sh kernelcore 192.168.1.X

# Rebuild NixOS (dentro do sistema)
sudo nixos-rebuild switch --flake .#kernelcore

# Enrollar TPM (após Secure Boot ativo)
sudo bash scripts/enroll-tpm.sh

# Ver estado da instalação Void
./voidnx.sh status
./voidnx.sh debug

# Rodar testes
bash tests/run-all.sh
```
