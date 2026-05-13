# Roadmap de Correções — voidnx.sh

Tracker dos bugs identificados na análise de bootstrap. Marcar com `[x]` conforme aplicar.

**Status geral:** 18 / 18 corrigidos ✅

---

## 🔴 Críticos (quebram o bootstrap)

- [x] **#1 — State machine: `void_crypt` vs `root_crypt`** — `voidnx.sh:379` ✅
  - Trocado `/dev/mapper/void_crypt` por `/dev/mapper/root_crypt` em `detect_installation_state`.

- [x] **#2 — Checagem de LVM que nunca é criado** — `voidnx.sh:387-393` ✅
  - Removidas as checagens `vgs void-vg` e `blkid /dev/void-vg/root`. `NO_ROOT_FS` agora checa `/dev/mapper/root_crypt`. Removido `NO_LVM` do `handle_state`.

- [x] **#3 — `dracut --kver $(uname -r)` no chroot** — `voidnx.sh:893` ✅
  - Detecta kernel via `ls /lib/modules | sort -V | tail -1` com fallback de erro se nada for encontrado.

- [x] **#4 — `luksAddKey` antes da key existir** — `voidnx.sh:910-912` ✅
  - Geração da key movida para o host (`generate_chroot_script`) antes do `luksAddKey`. `configure.sh` agora apenas valida que o arquivo existe.

- [x] **#5 — `configure.sh` chama `warn` indefinido** — `voidnx.sh:899-900` ✅
  - `warn()` adicionado ao topo do script chroot (junto com `log()`).

- [x] **#6 — Swap nunca formatado + fstab com UUID errado** — `voidnx.sh:759` ✅
  - Fstab agora aponta para `/dev/mapper/swap`; crypttab cuida do mkswap a cada boot via flag `swap`.

- [x] **#7 — `trap cleanup EXIT` depois do case** — `voidnx.sh:1148` ✅
  - Trap movido para antes do `case`, com flag `RUN_CLEANUP_ON_EXIT`. Comandos read-only (`status`, `debug`) não disparam cleanup. `clean` faz cleanup direto sem double-run via trap.

---

## 🟠 Graves (bloqueiam em condições específicas)

- [x] **#8 — `PART_SUFFIX` calculado antes de `auto_select_disk`** — `voidnx.sh:150` ✅
  - Extraído em `recompute_part_suffix()`; chamado após `auto_select_disk` e em `choose_disk` quando o disco muda.

- [x] **#9 — Pacote inexistente `base-system-essentials`** — `voidnx.sh:666` ✅
  - Removido de `BASE_PKGS`.

- [x] **#10 — `apparmor=1 security=apparmor` sem pacote** — `voidnx.sh:865` ✅
  - Removido do `GRUB_CMDLINE_LINUX_DEFAULT`. Comentário documenta como reativar opt-in.

- [x] **#11 — `install-auto.sh` finge ser não-interativo** — `install-auto.sh:23-25` ✅
  - `setup_luks` usa `--batch-mode --key-file -` quando `LUKS_PASS` setado. `_open_luks_device` helper alimenta a senha via stdin. `luksAddKey` idem. `configure.sh` usa `chpasswd` quando `ROOT_PASS`/`USER_PASS` propagados via `env` no `chroot`.

- [x] **#12 — Faltam ferramentas em `validate_system_requirements`** — `voidnx.sh:172-184` ✅
  - Adicionados: `mkswap`, `wipefs`, `swapon`, `chpasswd`, `awk`, `bc`, `uuidgen`, `fuser`, `dd`, `ping`.

- [x] **#13 — Precedência ambígua em `IS_LIVE`** — `voidnx.sh:143` ✅
  - Reescrito com `if … then … fi` explícito.

---

## 🟡 Menores (estéticos/ruído)

- [x] **#14 — Contagem de pacotes errada** — `voidnx.sh:726` ✅
  - Trocado por `${#BASE_PKGS[@]}` direto.

- [x] **#15 — `ls /mnt/bin/bash` em mensagem de sucesso** — `voidnx.sh:738` ✅
  - Substituído por `if [[ -x /mnt/bin/bash ]]` com fallback de `warn`.

- [x] **#16 — Reconfigure de locale duplicado** — `voidnx.sh:884` ✅
  - Consolidado em um único bloco `if LIBC_TYPE`. `/etc/default/libc-locales` escrito antes do reconfigure.

- [x] **#17 — `cleanup` tenta desmontar `/mnt/var`** — `voidnx.sh:1060` ✅
  - Removido `/mnt/var` da lista de unmounts.

- [x] **#18 — `cleanup` fecha `void_crypt` que nunca existiu** — `voidnx.sh:1070` ✅
  - Removidas as linhas `cryptsetup close void_crypt` e `vgchange -an void-vg`.

---

## Notas

- ✅ **Todos os 18 fixes aplicados.** Suite offline: 47 lint + 18 unit checks (todos verdes).
- Próximo passo: validar boot real em VM via `tests/03-vm-bootstrap.sh` + `tests/04-post-install.sh`.
- Após validação na VM, considerar push para o remote.
