# specs/constraints.md

## Purpose
This document defines enforceable invariants and boundaries. Violations must cause tests to fail and promotion to abort.

## Global Invariants (Always True)
1) Relative paths only: no absolute paths anywhere.
2) Script sovereignty: only shell scripts create/modify/move files.
3) Phase isolation: BUILD ≠ POPULATE ≠ TEST ≠ PROMOTE ≠ EXECUTE.
4) Runtime purity: runtime/ contains only executable artifacts (no specs/tests/scripts/logs).
5) Promotion is one-way and atomic.

## Typed Path Safety (Hard Constraint)
- No untyped string paths in runtime execution.
- All paths are typed and validated.

### Path Types
- HostPath: host-specific representation (OS-dependent)
- LogicalPath: host-agnostic reference (namespace, identifier)
- MemoryPath: resolved content with provenance (hash, loaded_at)

### Allowed Transitions (Only)
- adapt: HostPath → LogicalPath
- resolve: LogicalPath → MemoryPath
- freeze: MemoryPath → ImmutableMemoryPath (optional)

No other transitions exist.
In particular: **no HostPath → MemoryPath** direct transition.

## Capability Lattice Safety (Hard Constraint)
- Define a meet-semilattice L = (Capability, ≤).
- Any execution is valid iff:
  C_host ⊓ C_context ⊓ C_runtime ⊓ C_command ⊓ C_financial ≠ ⊥

Meaning:
- No command runs unless the meet of required capabilities is non-bottom.
- Capabilities must be declared honestly by host adapters and respected by core.

## Host Adapter Purity and Contract (Hard Constraint)
Host adapters must be:
- contract-compliant (structure + manifest schema)
- pure translators (no business logic)
- incapable of changing command semantics
- must translate host invocation → canonical entrypoint invocation
- must not introduce untyped paths
- must not contain OS detection logic outside runtime/host_adapters/

Entrypoint must be exactly: runtime/bin/app_entry

## Financial Isolation (Default Constraint)
Default mode is SIMULATED_ONLY:
- Spending cap: $0.00
- Any external service must be represented by a simulator slot.
- Switching to real services requires an explicit revenue gate approval and must remain plug-in compatible with simulators.

## Immutable vs Append-only Rules
- runtime/schema/ is immutable once promoted.
- runtime/state/ is append-only; no overwrites; new facts only.

## Promotion Gate (Must Hold Before Promote)
Promotion to runtime/ is allowed only if:
- all prior phase tests pass
- host adapters are contract-compliant
- all paths are typed (no untyped paths)
- capability lattice validation passes (meet ≠ ⊥ for relevant checks)
- immutable/append-only rules are preserved
- rollback is available for the promote script
