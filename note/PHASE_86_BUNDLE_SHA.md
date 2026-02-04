# PHASE 86 — Bundle SHA Verification

Goal:
- Make releases tamper-evident at the bundle level.
- Prove that the tarball bytes match the `bundle_sha256` recorded in the manifest.

Deliverables:
- `test/86_test_bundle_sha.sh`: verifies:
  1) latest release tarball exists
  2) its sha256 matches the sibling manifest `bundle_sha256`
  3) the manifest embedded inside the tarball matches the sibling manifest hash too

Why:
- Prevents "same name, different bytes" and establishes the release as operational evidence.
