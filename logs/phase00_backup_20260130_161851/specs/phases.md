# specs/phases.md

## Purpose
This document defines the only allowed phase transitions and what each phase may do. No mixed-phase operations are allowed. :contentReference[oaicite:26]{index=26}

## Phase Model (Strict)
The construction loop is:

Phase 0 CONTRACT → Phase 1 BUILD → Phase 2 POPULATE → Phase 3 TEST → Phase 4 PROMOTE → Phase 5 EXECUTE :contentReference[oaicite:27]{index=27}

## Phase 0 — CONTRACT (Human Only)
Allowed actions:
- Create/edit: specs/system.md, specs/constraints.md, specs/phases.md only. :contentReference[oaicite:28]{index=28}
Forbidden:
- Running any scripts
- Creating runtime artifacts

Exit criteria:
- Specs are complete and unambiguous.

## Phase 1 — BUILD (Structure Only)
Script:
- build/00_build.sh :contentReference[oaicite:29]{index=29}

Allowed actions:
- Create directories and empty placeholder files only.
- Write logs/build.manifest.json.

Forbidden:
- Writing implementation logic
- Writing config values
- Executing code
- Creating new paths outside declared skeleton

Exit criteria:
- Structure matches specs/system.md
- Manifest written

## Phase 2 — POPULATE (Write, Don’t Run)
Script:
- populate/01_populate.sh :contentReference[oaicite:30]{index=30}

Allowed actions:
- Fill files created in BUILD with inert content (code/text).
- Write logs/populate.files.json and logs/populate.hashes.json.

Forbidden:
- Execution of code
- Creating new files/paths not created in BUILD
- Modifying runtime/ directly

Exit criteria:
- Every populated file satisfies declared contracts
- Hash logs exist

## Phase 3 — TEST (Prove, Don’t Trust)
Script:
- test/02_test.sh :contentReference[oaicite:31]{index=31}

Allowed actions:
- Read-only verification over candidates.
- Deterministic tests with fail-fast behavior.
- Produce logs/test.results.json.

Must include validation of:
- Typed path safety (no untyped paths)
- Allowed path transitions only
- Host adapter contract compliance
- Capability lattice meet checks (meet ≠ ⊥ where required)
- Financial isolation ($0 mode) if enabled as default :contentReference[oaicite:32]{index=32}

Forbidden:
- Modifying runtime/
- Modifying populated artifacts

Exit criteria:
- All tests pass
- results log exists

## Phase 4 — PROMOTE (One-Way Gate)
Script:
- promote/03_promote.sh :contentReference[oaicite:33]{index=33}

Allowed actions:
- Atomic move/copy of verified artifacts into runtime/
- Build runtime from a clean state
- Write logs/runtime.manifest.json

Required promotion constraints:
- all previous phase tests pass
- preserve immutable schema/
- preserve append-only state/
- host adapter compliance report generated
- path type safety report generated
- capability lattice validation report generated
- rollback path exists :contentReference[oaicite:34]{index=34}

Forbidden:
- Partial promotion
- Editing artifacts during promotion

Exit criteria:
- runtime/ stands alone and matches specs/system.md

## Phase 5 — EXECUTE (Out of Factory)
Allowed actions:
- Run runtime like a normal user.

Forbidden:
- Using scripts to “fix” runtime
- depending on specs/, tests/, logs/ or any factory files

Pass condition:
- Runtime stands alone; if runtime depends on anything else, factory failed. :contentReference[oaicite:35]{index=35}

## Transition Rules (Non-negotiable)
- You can only move forward if the current phase is complete and verified.
- Promotion requires all previous phase tests passing.
- Generate exactly one .sh script per phase action (per transition task). :contentReference[oaicite:36]{index=36} :contentReference[oaicite:37]{index=37}
