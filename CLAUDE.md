# voidnxsec — Claude Instructions

## Identidade do Projeto

**Este repositório é um framework de bootstrap e desenvolvimento polyglot.**
Ele NÃO compete com `/etc/nixos`. São responsabilidades distintas.

---

## Limite de Escopo (CRÍTICO)

### O que PERTENCE aqui

| Categoria | Exemplos |
|---|---|
| Disco / particionamento | `disko`, `partitions.nix`, layout LUKS2/Argon2id |
| Boot + Secure Boot | Lanzaboote, `kernelParams` de segurança, `boot.blacklistedKernelModules` |
| Hardware mínimo | `initrd` modules, `nixpkgs.hostPlatform` |
| Primeiro acesso | sops-nix wiring, SSH authorized keys, user wheel mínimo |
| Conectividade de infra | Tailscale, binary cache (`nix-serve`), remote builds |
| Dev shells polyglot | Rust, Go, C, C++ environments (`nix/`) |
| Apps de framework | `rust-service/`, `go-service/`, `c-app/`, `cpp-app/` |

### O que NÃO PERTENCE aqui (vai para `/etc/nixos`)

- Power management (`cpuFreqGovernor`, `HandleLidSwitch`, suspend/hibernate)
- Desktop apps, browsers, editors
- Bluetooth, áudio, impressão
- Dotfiles / home-manager
- Hardening operacional completo (duplica `/etc/nixos/sec/hardening.nix`)
- Pacotes de conveniência (`htop`, `bat`, `eza`, etc.)
- Qualquer config que muda após a máquina estar no ar

### Regra de ouro

> Se a mudança requer `sudo nixos-rebuild switch` na máquina rodando, pertence ao `/etc/nixos`.
> Se é necessária para a máquina *chegar a existir e ser acessível*, pertence aqui.

---

## Estrutura `nixos/`

```
nixos/
├── hosts/<host>/
│   ├── hardware.nix     # initrd, kernel modules, fileSystems (UUIDs reais)
│   ├── partitions.nix   # disko layout — LUKS2, GPT, mountpoints
│   ├── profile.nix      # overrides de boot (Lanzaboote, NVIDIA params, sops)
│   └── default.nix      # imports dos três acima + módulos comuns
└── modules/
    ├── common/          # base mínima: boot, users, networking, secrets, security
    ├── desktop/         # offload server (infra, não UI)
    ├── laptop/          # wifi + suspend — só o necessário para bootstrap
    ├── network/         # tailscale
    └── server/          # serviços de infra (cache, builds)
```

Módulos aqui devem ser **idempotentes e cirúrgicos**: rodar `nixos-anywhere` duas vezes
no mesmo alvo deve produzir o mesmo resultado.

---

## Build & Validação

```bash
# Validar antes de qualquer commit
nix --extra-experimental-features 'nix-command flakes' flake check

# Deploy em máquina nova
nixos-anywhere --flake .#<host> root@<ip>
```

---

## Relação com `/etc/nixos`

| | `voidnxsec` | `/etc/nixos` |
|---|---|---|
| **Propósito** | Instalar e bootstrapar | Configurar e manter |
| **Quando muda** | Nova máquina / mudança de hardware | Mudança de comportamento do sistema |
| **Rebuild** | `nixos-anywhere` (remoto) | `nixos-rebuild switch` (local) |
| **Scope** | Disco, boot, acesso inicial | Tudo o mais |
