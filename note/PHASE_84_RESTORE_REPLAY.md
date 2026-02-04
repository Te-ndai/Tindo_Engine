# Phase 84 — Restore + Replay Proof

Goal:
- A "release" is not archival unless it can be restored and replayed in a clean directory.

Restore + Replay proof must:
1) unpack a release bundle into a clean temp dir
2) run logchain_verify
3) run rebuild_projections
4) run ops report
5) assert results match manifest expectations:
   - counts (at least: logchain events)
   - last_event_time_utc (or equivalent)
   - integrity verification pass

Non-negotiables:
- test is read-only with respect to repository artifacts
- temp restore dir is isolated and deleted
- no absolute paths
- fail-fast
