# Void Fortress Framework - Architecture

This framework is built around a declarative, verifiable, and highly structured pipeline for bootstrapping Linux environments.

## The Phase Diagram

The OS installation and orchestration processes are broken down into discrete **phases**. Each phase acts as an atomic state transition:

```text
[ Pre-flight ] -> [ Disk Setup ] -> [ Mount ] -> [ Base Install ] -> [ Chroot Setup ] -> [ Bootloader ] -> [ Finalize ]
```

Each phase is strictly validated using scripts in `lib/validators.sh` before the system is allowed to progress to the next phase. If a phase fails, `lib/rollback.sh` is triggered to cleanly undo the setup.

## Structured JSONL Flow

Instead of relying on unstructured text logs (like standard `echo` output), the framework outputs structured JSON Lines (`.jsonl`). Every action, state change, and error is logged as a JSON object conforming to `schema/log-event.json`.

**Benefits of the JSONL Flow:**
1.  **Machine-Readable Debugging:** Utilities in `tools/` (like `analyze-log.sh`) can instantly parse failures without fragile text scraping or `regex` magic.
2.  **Deterministic Auditing:** We generate hashes for the filesystem and state at each phase and embed them in the logs.
3.  **State Rollback:** By reading the JSONL log chronologically, the framework knows exactly which phases succeeded and can execute corresponding teardown procedures safely.

## Component Interactions

-   **`lib/`**: Contains the core reusable shell framework functions. These are entirely distro-agnostic.
-   **`examples/`**: Distro-specific installer implementations (Void, Arch, Debian) that source the core `lib/` files to do the actual work.
-   **`tools/`**: External/Host-side utilities to analyze the resulting JSONL logs, validate state integrity, and manage snapshots.
