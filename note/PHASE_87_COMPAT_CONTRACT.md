# PHASE 87 — Compatibility Contract

Problem:
- A release without a declared runtime environment is archival, not portable.
- We need a compatibility contract: “this release can be restored and replayed on X”.

Solution:
- Add `compat` fields to the release manifest:
  - os, arch, python version, python implementation, machine
- Add `schema_version` to manifest for forward evolution.

Test:
- Build a release.
- Assert manifest contains compat + schema_version.
- Assert compat matches current host (os/arch/python/impl/machine).
