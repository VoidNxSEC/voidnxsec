 DESENVOLVIMENTO LOCAL                    CI (GitHub Actions)
 ═══════════════════                     ═══════════════════

 ┌──────────────────┐                    ┌──────────────────┐
 │  voidnx.sh       │                    │  QEMU VM         │
 │  + lib/logger.sh │──── git push ────→ │  Void Linux ISO  │
 │                  │                    │  25GB vdisk      │
 └────────┬─────────┘                    │  Auto-run        │
          │                              └────────┬─────────┘
          │                                       │
          ▼                                       ▼
 ┌──────────────────┐                    ┌──────────────────┐
 │ install.jsonl    │                    │ install.jsonl    │
 │ install.log      │                    │ (via output disk)│
 │ stderr.log       │                    └────────┬─────────┘
 └────────┬─────────┘                             │
          │                                       │
          ▼                                       ▼
 ┌──────────────────┐                    ┌──────────────────┐
 │ jq local         │                    │ jq + GH annotate │
 │ analyze-log.sh   │                    │ Step Summary     │
 │ "o que quebrou?"  │                    │ Artifacts        │
 └──────────────────┘                    └──────────────────┘
          │                                       │
          └───────────── MESMO FORMATO ───────────┘
                         (JSONL)

┌──────────────────────────────────────────────────────────┐
│                    voidnx.sh                             │
│                                                          │
│  ┌─────────────┐   ┌──────────────┐  ┌───────────────┐  │
│  │ RUNTIME     │   │ HOST         │  │ POST-MORTEM   │  │
│  │             │   │              │  │               │  │
│  │ set -euxo   │   │ preflight    │  │ debug cmd     │  │
│  │ trap ERR    │   │ validate_*   │  │ validate_boot │  │
│  │ state mach  │   │ disk detect  │  │ log analysis  │  │
│  │ checkpoint  │   │ UEFI check   │  │ rollback      │  │
│  │ log_cmd()   │   │ net check    │  │               │  │
│  └──────┬──────┘   └──────┬───────┘  └───────┬───────┘  │
│         │                 │                   │          │
│         ▼                 ▼                   ▼          │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ Phase 1 → Phase 2 → Phase 3 → Phase 4              │ │
│  │  part.     boot.     chroot     final               │ │
│  │                                                     │ │
│  │  PRE_VALIDATE → EXECUTE → POST_VALIDATE → NEXT     │ │
│  │       │                        │                    │ │
│  │       └── FAIL? ──→ ROLLBACK ←─┘                   │ │
│  └─────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
