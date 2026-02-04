#!/usr/bin/env bash
set -euo pipefail

cat > runtime/app/dashboard.py <<'PY'
from __future__ import annotations
import json, os
from flask import Flask, Response, jsonify

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

def read_json(rel_path: str):
    p = os.path.join(ROOT, rel_path)
    if not os.path.exists(p):
        return None
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)

def read_text(rel_path: str):
    p = os.path.join(ROOT, rel_path)
    if not os.path.exists(p):
        return None
    with open(p, "r", encoding="utf-8") as f:
        return f.read()

app = Flask(__name__)

@app.get("/api/status")
def api_status():
    d = read_json("runtime/state/projections/system_status.json")
    if d is None:
        return jsonify({"error": "system_status.json missing"}), 404
    return jsonify(d)

@app.get("/api/diagnose")
def api_diagnose():
    d = read_json("runtime/state/projections/diagnose.json")
    if d is None:
        return jsonify({"error": "diagnose.json missing (run ./runtime/bin/ops report)"}), 404
    return jsonify(d)

@app.get("/api/report")
def api_report():
    t = read_text("runtime/state/reports/diagnose.txt")
    if t is None:
        return Response("diagnose.txt missing (run ./runtime/bin/ops report)\n", mimetype="text/plain", status=404)
    return Response(t, mimetype="text/plain")

@app.get("/")
def home():
    report = read_text("runtime/state/reports/diagnose.txt") or "diagnose.txt missing (run ./runtime/bin/ops report)\n"
    status = read_json("runtime/state/projections/system_status.json") or {"projections": [], "ok": 0, "errors": ["system_status.json missing"]}

    rows = status.get("projections", [])
    if not isinstance(rows, list):
        rows = []

    def esc(s: str) -> str:
        return (s or "").replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

    table_rows = "\n".join(
        f"<tr><td>{esc(str(r.get('name','')))}</td><td>{esc(str(r.get('status','')))}</td></tr>"
        for r in rows if isinstance(r, dict)
    )

    html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <title>Runtime Dashboard</title>
  <style>
    body {{ font-family: Arial, sans-serif; margin: 20px; }}
    .grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }}
    .card {{ border: 1px solid #ddd; border-radius: 10px; padding: 14px; }}
    pre {{ background:#f7f7f7; padding: 12px; border-radius: 8px; overflow:auto; }}
    table {{ width:100%; border-collapse: collapse; }}
    td, th {{ border-bottom: 1px solid #eee; padding: 8px; text-align:left; }}
    code {{ background:#f0f0f0; padding:2px 6px; border-radius:6px; }}
  </style>
</head>
<body>
  <h2>Runtime Dashboard (read-only)</h2>

  <div class="card">
    <div><strong>Operator commands</strong> (copy/paste)</div>
    <div style="margin-top:8px;">
      <code>./runtime/bin/ops status</code>
      &nbsp;
      <code>./runtime/bin/ops freshen</code>
      &nbsp;
      <code>./runtime/bin/ops report</code>
    </div>
  </div>

  <div class="grid" style="margin-top:16px;">
    <div class="card">
      <h3>Diagnose report</h3>
      <pre>{esc(report)}</pre>
    </div>
    <div class="card">
      <h3>System status</h3>
      <table>
        <thead><tr><th>Projection</th><th>Status</th></tr></thead>
        <tbody>{table_rows}</tbody>
      </table>
    </div>
  </div>
</body>
</html>"""
    return Response(html, mimetype="text/html")

def main():
    host="127.0.0.1"
    port=5055
    print(f"Serving on http://{host}:{port}")
    app.run(host=host, port=port, debug=False)

if __name__ == "__main__":
    main()
PY

cat > runtime/bin/dashboard <<'SH'
#!/usr/bin/env bash
set -euo pipefail
python3 runtime/app/dashboard.py
SH
chmod +x runtime/bin/dashboard

echo "OK: phase 81 populate complete"
