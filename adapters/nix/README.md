# NixOS Adapter

Distro adapter that maps the VoidNxSEC framework pipeline onto **NixOS**.
It is the Nix counterpart of the Void track (`voidnx.sh`): same canonical
phases, same JSONL ledger, same validator contract — but the heavy lifting
is declarative (disko + `nixos-install --flake`).

## Pipeline

| Phase | Framework name | Nix implementation |
|---|---|---|
| 0 | `preflight` | env/disk/host resolution, LUKS passphrase staging, network+flake sanity |
| 1 | `disk-setup` | `disko --mode disko <host>/partitions.nix` (GPT + LUKS2/Argon2id + mount) |
| 2 | `mount` | verify `/mnt`; repair with `disko --mode mount` on resume |
| 3 | `base-install` | `nixos-install --flake <flake>#<attr> --no-root-passwd` |
| 4 | `chroot-setup` | SSH host key + age key into `/mnt` (sops-nix first-boot) |
| 5 | `bootloader` | verify boot entries/UKIs; sbctl enroll when UEFI in Setup Mode |
| 6 | `finalize` | unmount, state save, post-boot checklist, optional reboot |

## Usage

```bash
sudo bash adapters/nix/install.sh            # fresh install (from NixOS minimal ISO)
sudo bash adapters/nix/install.sh resume     # continue after interruption
sudo bash adapters/nix/install.sh status     # read-only state
sudo bash adapters/nix/install.sh debug      # read-only environment
sudo bash adapters/nix/install.sh clean      # unmount + close mappers
```

Environment variables: `DISK`, `HOST` (default `kernelcore`), `FLAKE_URI`,
`FLAKE_ATTR` (auto: `HOST` → `voidnx-HOST`), `LUKS_PASS` / `--luks-pass FILE`,
`DRY_RUN`, `SKIP_VALIDATION`, `AUTO_REBOOT`.

## Files

```
adapters/nix/
├── install.sh          # driver: phase loop, resume/status/clean, rollback
├── validators.sh       # validate_pre_<phase> / validate_post_<phase>
└── modules/
    ├── 00-preflight.sh … 06-finalize.sh
```

The JSONL ledger lands in `$LOG_JSONL` (default `/var/log/void-fortress/install.jsonl`)
and can be audited with `tools/analyze-log.sh`.
