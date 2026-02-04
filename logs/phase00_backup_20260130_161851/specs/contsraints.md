# specs/constraints.md

## Purpose
This document defines enforceable invariants and boundaries. Violations must cause tests to fail and promotion to abort. :contentReference[oaicite:9]{index=9}

## Global Invariants (Always True)
1) Relative paths only: no absolute paths anywhere. :contentReference[oaicite:10]{index=10}  
2) Script sovereignty: only shell scripts create/modify/move files. :contentReference[oaicite:11]{index=11}  
3) Phase isolation: BUILD ≠ POPULATE ≠ TEST ≠ PROMOTE ≠ EXECUTE. :contentReference[oaicite:12]{index=12}  
4) Runtime purity: runtime/ contains only executable artifacts (no specs/tests/scripts/logs). :contentReference[oaicite:13]{index=13}  
5) Promotion is one-way and atomic. :contentReference[oaicite:14]{index=14}  

## Typed Path Safety (Hard Constraint)
- No untyped string paths in runtime execution.
- All paths are typed and validated. :contentReference[oaicite:15]{index=15}

### Path Types
- HostPath: host-specific representation (OS-dependent)
- LogicalPath: host-agnostic reference (namespace, identifier)
- MemoryPath: resolved content with provenance (hash, loaded_at)

### Allowed Transitions (Only)
- adapt: HostPath → LogicalPath
- resolve: LogicalPath → MemoryPath
- freeze: MemoryPath → ImmutableMemoryPath (optional)

No other transitions exist.
In particular: **no HostPath → MemoryPath** direct transition. :contentReference[oaicite:16]{index=16} :contentReference[oaicite:17]{index=17}

## Capability Lattice Safety (Hard Constraint)
- Define a meet-semilattice L = (Capability, ≤).
- Any execution is valid iff:
  C_host ⊓ C_context ⊓ C_runtime ⊓ C_command ⊓ C_financial ≠ ⊥ :contentReference[oaicite:18]{index=18}

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
- must not contain OS detection logic outside runtime/host_adapters/ :contentReference[oaicite:19]{index=19}

Entrypoint must be exactly: runtime/bin/app_entry :contentReference[oaicite:20]{index=20}

## Financial Isolation (Default Constraint)
Default mode is SIMULATED_ONLY:
- Spending cap: $0.00
- Any external service must be represented by a simulator slot.
- Switching to real services requires an explicit revenue gate approval and must remain plug-in compatible with simulators. :contentReference[oaicite:21]{index=21} :contentReference[oaicite:22]{index=22}

## Immutable vs Append-only Rules
- runtime/schema/ is immutable once promoted.
- runtime/state/ is append-only; no overwrites; new facts only. :contentReference[oaicite:23]{index=23}

## Promotion Gate (Must Hold Before Promote)
Promotion to runtime/ is allowed only if:
- all prior phase tests pass
- host adapters are contract-compliant
- all paths are typed (no untyped paths)
- capability lattice validation passes (meet ≠ ⊥ for relevant checks)
- immutable/append-only rules are preserved
- rollback is available for the promote script :contentReference[oaicite:24]{index=24} :contentReference[oaicite:25]{index=25}
