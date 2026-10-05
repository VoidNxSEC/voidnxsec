# Adding a distro adapter

The VoidNxSEC framework separates **what** happens (the canonical pipeline)
from **how** it happens on each distro (the adapter). This file is the
contract a new distro adapter must fulfill. The NixOS implementation lives in
[`adapters/nix/`](../adapters/nix/README.md) and is the reference adapter.

## Canonical pipeline

Every adapter implements the same seven phases, in order:

```
preflight → disk-setup → mount → base-install → chroot-setup → bootloader → finalize
```

A phase is atomic: if it fails, the run stops and the adapter's rollback
tears down whatever was done (mounts, mappers). The adapter persists which
phases completed so `resume` can continue after an interruption.

## Contract

1. **Driver** — an entry point that:
   - sources the framework libs: `lib/logger_v2.sh` (JSONL ledger),
     `lib/state.sh` (state machine), `lib/rollback.sh` (rollback helpers);
   - runs each phase as `pre-validator → module → post-validator`;
   - marks completed phases in a state file and supports `resume`;
   - provides read-only `status` and `debug` subcommands;
   - honors `DRY_RUN` (no destructive side effects).

2. **Phase modules** — one file per phase defining a single function
   `run_<phase>` (dashes become underscores). Modules contain only
   definitions; the driver executes them.

3. **Validators** — `validate_pre_<phase>` / `validate_post_<phase>`
   functions returning the number of failures (0 = pass). Validation
   outcomes are emitted through the JSONL logger, so the ledger records
   why a phase was rejected.

4. **Logging** — only `log_*` functions from `lib/logger_v2.sh`
   (`log_phase`, `log_info`, `log_ok`, `log_warn`, `log_fail`, `log_fatal`,
   `log_cmd`, `log_system_snapshot`). No ad-hoc `echo` for state that
   belongs in the ledger.

5. **State** — reuse `lib/state.sh` (`detect_<distro>_state`,
   `save_<distro>_state`) and extend it with the new distro's states.

6. **Idempotency** — running the adapter twice on the same target must
   produce the same end state (declarative tooling preferred: disko,
   nixos-anywhere, debootstrap, pacstrap, …).

## Checklist

- [ ] `adapters/<distro>/install.sh` driver with `install|resume|status|debug|clean`
- [ ] `adapters/<distro>/modules/00-*.sh … 06-*.sh` phase modules
- [ ] `adapters/<distro>/validators.sh` with pre/post validators per phase
- [ ] `adapters/<distro>/README.md` mapping each phase to the distro tooling
- [ ] `bash -n` clean on every file (enforced by `tests/01-lint.sh`)
- [ ] `DRY_RUN=true` end-to-end run produces zero changes
