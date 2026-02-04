# specs/system.md

## Purpose
This document declares what exists in the system (inventory), not how it is implemented. It is a Phase 0 contract.

## Root and Pathing
- The human chooses a project root directory (“ROOT/”).
- All paths referenced in this repository are **relative to ROOT/**.
- No artifact may depend on anything outside ROOT/.

## Universal Factory Skeleton (Fixed)
ROOT/
- build/        (scripts that create structure only)
- populate/     (scripts that write file contents only)
- test/         (scripts that verify correctness only)
- promote/      (scripts that move verified artifacts into runtime/)
- specs/        (these contracts; human-written)
- logs/         (machine-readable trace of actions/results)
- runtime/      (final runnable system only; no scripts/tests/specs)

Nothing else is part of the system.

## Runtime: What Must Exist
runtime/ is the only executable deliverable. It must stand alone.

runtime/
- bin/
  - app_entry              (single canonical entrypoint; invoked by all hosts)
- schema/                  (immutable contracts/types once promoted)
  - capability_lattice.json
  - host_adapter_contract.json
  - typed_path_contract.json
  - command_registry.json
- core/                    (host-agnostic logic only)
  - __init__.py
  - path_model.py
  - capability.py
  - executor.py
- host_adapters/           (pure translators only; no business logic)
  - linux/
    - manifest.json
    - install.sh
    - uninstall.sh
    - invoke.sh
  - windows/
    - manifest.json
    - install.ps1
    - uninstall.ps1
    - invoke.ps1
  - macos/
    - manifest.json
    - install.sh
    - uninstall.sh
    - invoke.sh
- simulators/              (zero-cost stand-ins for any external services)
  - README.md
  - registry.json
  - slots/                 (one file per service simulator)
- state/                   (append-only runtime state; never overwritten)
  - logs/                  (append-only JSONL)
  - cache/                 (rebuildable)
  - projections/           (rebuildable derived views)

### Canonical Entrypoint
- The canonical entrypoint path is: `runtime/bin/app_entry`
- Host adapters must invoke exactly this entrypoint.

## System Composition (Non-negotiable)
System = Core ⊗ HostAdapters ⊗ PathModel ⊗ Lattice

Meaning:
- Core: host-independent execution + validation
- HostAdapters: translate host invocation → canonical invocation
- PathModel: typed paths and allowed transitions
- Lattice: capability validation for any execution

## Observability Outputs (Factory-side)
The factory produces machine-readable logs:
- logs/build.manifest.json
- logs/populate.files.json
- logs/populate.hashes.json
- logs/test.results.json
- logs/runtime.manifest.json

## What This System Is (and is not)
- This system is a deterministic construction factory that produces a runtime.
- It is not “a collection of plans.” Plans must compile into scripts + tests + runtime artifacts.
