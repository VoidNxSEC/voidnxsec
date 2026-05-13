# Roadmap de Correções — voidnx.sh

Tracker dos bugs identificados na análise de bootstrap. Marcar com `[x]` conforme aplicar.

**Status geral:** 9 / 18 corrigidos (todos os críticos ✅ + #17, #18 colhidos no caminho)

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

- [ ] **#8 — `PART_SUFFIX` calculado antes de `auto_select_disk`** — `voidnx.sh:150`
  - Se `DISK` muda de nvme para vda depois, `PART_SUFFIX` continua "p" → tenta `/dev/vdap1`.
  - **Fix:** mover cálculo de `PART_SUFFIX` para uma função `recompute_part_suffix()` chamada após `auto_select_disk`.

- [ ] **#9 — Pacote inexistente `base-system-essentials`** — `voidnx.sh:666`
  - Void Linux tem `base-system` e `base-minimal`. `xbps-install` falha no bootstrap.
  - **Fix:** remover `base-system-essentials` da lista `BASE_PKGS`.

- [ ] **#10 — `apparmor=1 security=apparmor` sem pacote** — `voidnx.sh:865`
  - GRUB cmdline ativa AppArmor mas pacote não está em `BASE_PKGS`. Kernel do Void pode não ter AppArmor compilado.
  - **Fix:** remover do cmdline OU adicionar `apparmor`/`apparmor-utils` em `BASE_PKGS` E confirmar suporte no kernel.

- [ ] **#11 — `install-auto.sh` finge ser não-interativo** — `install-auto.sh:23-25`
  - Exporta `ROOT_PASS`/`USER_PASS`/`LUKS_PASS` mas `voidnx.sh` chama `passwd` e `cryptsetup --verify-passphrase` interativamente.
  - **Fix:** suportar variáveis no `voidnx.sh` (e.g. `echo "$LUKS_PASS" | cryptsetup luksFormat ...` quando setado), ou documentar que é semi-interativo.

- [ ] **#12 — Faltam ferramentas em `validate_system_requirements`** — `voidnx.sh:172-184`
  - Não checa: `bc`, `uuidgen`, `fuser`, `wipefs`, `swapon`, `awk`, `mkswap`.
  - **Fix:** adicionar essas tools em `required_tools`.

- [ ] **#13 — Precedência ambígua em `IS_LIVE`** — `voidnx.sh:143`
  - `[[ -f X ]] || grep && IS_LIVE=true` — se `-f X` for true, `IS_LIVE` nunca é setado.
  - **Fix:** reescrever com `if`:
    ```bash
    if [[ -f /run/void-live ]] || grep -q "void-live" /proc/cmdline 2>/dev/null; then
        IS_LIVE=true
    fi
    ```

---

## 🟡 Menores (estéticos/ruído)

- [ ] **#14 — Contagem de pacotes errada** — `voidnx.sh:726`
  - `$(echo "${#BASE_PKGS[@]}" | wc -c)` conta caracteres, não pacotes.
  - **Fix:** trocar por `${#BASE_PKGS[@]}`.

- [ ] **#15 — `ls /mnt/bin/bash` em mensagem de sucesso** — `voidnx.sh:738`
  - Saída suja na mensagem; com `set -e`, falha aborta script.
  - **Fix:** trocar por `[[ -x /mnt/bin/bash ]] && echo 'system ready' || echo 'incomplete'`.

- [ ] **#16 — Reconfigure de locale duplicado** — `voidnx.sh:884`
  - Já há um `if LIBC_TYPE` logo acima; o `2>/dev/null || ...` em sequência é redundante e ruidoso.
  - **Fix:** remover linha 884.

- [x] **#17 — `cleanup` tenta desmontar `/mnt/var`** — `voidnx.sh:1060` ✅
  - Removido `/mnt/var` da lista de unmounts.

- [x] **#18 — `cleanup` fecha `void_crypt` que nunca existiu** — `voidnx.sh:1070` ✅
  - Removidas as linhas `cryptsetup close void_crypt` e `vgchange -an void-vg`.

---

## Notas

- Aplicar na ordem dos críticos (#1–#7) primeiro. Sem isso, qualquer teste de bootstrap falha.
- Após cada fix, rodar `bash -n voidnx.sh` para checar sintaxe.
- Quando todos os críticos estiverem feitos, vale rodar uma instalação real em VM antes de tocar nos graves/menores.
