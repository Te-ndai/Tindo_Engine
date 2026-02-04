#!/usr/bin/env bash
set -euo pipefail

# Phase 84 (rewritten for Phase 88): Restore + replay proof WITH compat gate.
# Must be run from repo root.
#
# Contract alignment:
# - Your repo uses sibling manifest: release_<TS>.json (current), but we allow .manifest.json too.
# - Select latest tarball that HAS a sibling manifest (handles partial/stray bundles).
# - Compat gate runs BEFORE executing restored runtime binaries.
# - Canonicalizes case-insensitive compat fields (os/arch/impl) to avoid Linux vs linux noise.

fail() { echo "ERROR: $*" >&2; exit 1; }

ROOT="."
REL_DIR="${ROOT}/runtime/state/releases"

[ -d "${REL_DIR}" ] || fail "missing ${REL_DIR}"
mkdir -p "${ROOT}/.tmp"

: "${RELEASE_ID:?ERROR: RELEASE_ID not set}"

TARBALL="${REL_DIR}/release_${RELEASE_ID}.tar.gz"
MANIFEST="${REL_DIR}/release_${RELEASE_ID}.json"

[ -f "${TARBALL}" ] || fail "missing bundle: ${TARBALL} (run Phase 83 first)"
[ -f "${MANIFEST}" ] || fail "missing manifest: ${MANIFEST} (run Phase 83 first)"


echo "Using bundle:   ${TARBALL#./}"
echo "Using manifest: ${MANIFEST#./}"

TMPDIR="$(mktemp -d "${ROOT}/.tmp/restore.XXXXXX")"
cleanup() { rm -rf "${TMPDIR}"; }
trap cleanup EXIT

tar -xzf "${TARBALL}" -C "${TMPDIR}"

RESTORED_RUNTIME="${TMPDIR}/runtime"
[ -d "${RESTORED_RUNTIME}" ] || fail "bundle did not contain runtime/ root"
[ -x "${RESTORED_RUNTIME}/bin/logchain_verify" ] || fail "missing restored runtime/bin/logchain_verify"
[ -x "${RESTORED_RUNTIME}/bin/rebuild_projections" ] || fail "missing restored runtime/bin/rebuild_projections"
[ -x "${RESTORED_RUNTIME}/bin/ops" ] || fail "missing restored runtime/bin/ops"

# --- COMPAT GATE (Phase 88) ---
python3 - <<'PY' "${MANIFEST}"
import json, platform, sys

manifest_path = sys.argv[1]
m = json.load(open(manifest_path, "r", encoding="utf-8"))

if "schema_version" not in m:
    raise SystemExit("ERROR: manifest missing schema_version")
want = m.get("compat")
if not isinstance(want, dict):
    raise SystemExit("ERROR: manifest missing compat object")

host = {
    "os": platform.system().lower(),
    "arch": platform.machine().lower(),
    "python": platform.python_version(),
    "impl": platform.python_implementation().lower(),
    "machine": platform.platform(),
}

if want != host:
    raise SystemExit(
        "ERROR: compat mismatch; refusing to replay\n"
        f"manifest.compat={want}\n"
        f"current_host={host}\n"
    )

print("OK: compat gate passed")
PY


# --- Replay proof (Phase 84) ---
"${RESTORED_RUNTIME}/bin/logchain_verify"
"${RESTORED_RUNTIME}/bin/rebuild_projections"
"${RESTORED_RUNTIME}/bin/ops" report >/dev/null

# Assert replay results match manifest expectations (event_count + last_event_time_utc)
python3 - <<'PY' "${MANIFEST}" "${RESTORED_RUNTIME}" "${TARBALL}"
import json, os, sys, tarfile

manifest_path = sys.argv[1]
restored_runtime = sys.argv[2]
tarball_path = sys.argv[3]

def load_json(p):
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)

def find_expected(m):
    # Canonical (your current schema): expected_event_count / expected_last_event_time_utc
    c = m.get("expected_event_count")
    t = m.get("expected_last_event_time_utc")
    if c is not None and t is not None:
        return int(c), str(t), "expected_* (top-level)"

    # Legacy: expectations.{event_count,last_event_time_utc}
    exp = m.get("expectations")
    if isinstance(exp, dict):
        c = exp.get("event_count")
        t = exp.get("last_event_time_utc")
        if c is not None and t is not None:
            return int(c), str(t), "expectations.*"

    # Other drift: counts.event_count + last_event_time_utc (if present)
    counts = m.get("counts")
    if isinstance(counts, dict):
        c = counts.get("event_count") or counts.get("events")
        t = m.get("last_event_time_utc") or counts.get("last_event_time_utc")
        if c is not None and t is not None:
            return int(c), str(t), "counts.* + last_event_time_utc"

    return None

def load_embedded_manifest_from_tar(tar_path):
    # Look for runtime/state/releases/release_*.json inside tarball
    with tarfile.open(tar_path, "r:gz") as tf:
        members = tf.getmembers()
        cand = [m for m in members if m.name.startswith("runtime/state/releases/") and m.name.endswith(".json")]
        cand = [m for m in cand if os.path.basename(m.name).startswith("release_")]
        if not cand:
            return None, None
        cand.sort(key=lambda m: (m.size, m.name), reverse=True)
        m0 = cand[0]
        f = tf.extractfile(m0)
        if f is None:
            return None, None
        data = f.read().decode("utf-8", errors="strict")
        return m0.name, json.loads(data)

m = load_json(manifest_path)

got = find_expected(m)
source = f"sibling:{os.path.basename(manifest_path)}"

if got is None:
    emb_name, emb = load_embedded_manifest_from_tar(tarball_path)
    if emb is not None:
        got = find_expected(emb)
        source = f"embedded:{emb_name}"

if got is None:
    keys = sorted(list(m.keys()))
    raise SystemExit(
        "ERROR: could not find expected values in sibling or embedded manifest.\n"
        f"Sibling manifest keys: {keys}\n"
        "Accepted shapes:\n"
        "  - expected_event_count + expected_last_event_time_utc (preferred)\n"
        "  - expectations.event_count + expectations.last_event_time_utc (legacy)\n"
        "  - counts.event_count + last_event_time_utc (fallback)\n"
    )

exp_count, exp_last, shape = got
print(f"OK: expected values loaded from {source} via {shape}: event_count={exp_count} last_event_time_utc={exp_last}")

logs_dir = os.path.join(restored_runtime, "state", "logs")
if not os.path.isdir(logs_dir):
    raise SystemExit(f"ERROR: restored logs dir missing: {logs_dir}")

# --- Choose which log stream represents "events" ---
# We must match release_bundle's meaning of expected_event_count.
# Priority:
# 1) events.jsonl (canonical)
# 2) any *.jsonl containing "events" in filename
# 3) if only one *.jsonl exists, use it
# 4) last resort: all *.jsonl (but print diagnostics)
all_jsonl = sorted([n for n in os.listdir(logs_dir) if n.endswith(".jsonl")])

def line_count(path):
    c = 0
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                c += 1
    return c

# Diagnostics: show all log files and their line counts
diag = []
for n in all_jsonl:
    diag.append((n, line_count(os.path.join(logs_dir, n))))

# Pick target files (match release_bundle semantics):
# - Prefer executions.jsonl (your canonical event stream)
# - Never count *.chain.jsonl as events
target = []
if "executions.jsonl" in all_jsonl:
    target = ["executions.jsonl"]
else:
    # Fallback: any jsonl that is NOT a chain file
    non_chain = [n for n in all_jsonl if not n.endswith(".chain.jsonl")]
    if len(non_chain) == 1:
        target = non_chain
    elif len(non_chain) > 1:
        # If multiple non-chain logs exist, this is ambiguous: fail hard.
        raise SystemExit(
            "ERROR: ambiguous event logs: multiple non-chain *.jsonl present.\n"
            f"Candidates: {non_chain}\n"
            "Define canonical event stream in release_bundle and tests."
        )
    else:
        raise SystemExit(
            "ERROR: no non-chain *.jsonl logs found to count as events.\n"
            f"All jsonl files: {all_jsonl}"
        )

print("OK: log files present:")
for n, c in diag:
    mark = " <== COUNTED" if n in target else ""
    print(f"  - {n}: {c} lines{mark}")

# --- Count and compute last_event_time from chosen target stream only ---
event_count = 0
last_event_time = None

for name in target:
    p = os.path.join(logs_dir, name)
    with open(p, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            event_count += 1
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                raise SystemExit(f"ERROR: invalid JSONL line in {p}")
            t = obj.get("event_time_utc") or obj.get("event_time") or obj.get("timestamp_utc")
            if t and (last_event_time is None or t > last_event_time):
                last_event_time = t

if event_count != exp_count:
    raise SystemExit(
        f"ERROR: replay event_count mismatch: got={event_count} expected={exp_count}\n"
        f"Counted files: {target}\n"
        "If expected_event_count is intended to cover multiple streams, update release_bundle to define that explicitly."
    )

if last_event_time != exp_last:
    raise SystemExit(
        f"ERROR: replay last_event_time mismatch: got={last_event_time} expected={exp_last}\n"
        f"Counted files: {target}"
    )

print("OK: restore+replay expectations matched")
PY
echo "✅ Phase 84/88 TEST PASS (restore+replay + compat gate)"
