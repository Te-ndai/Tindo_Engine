#!/usr/bin/env bash
set -euo pipefail

cat > runtime/app/dashboard.py <<'PY'
from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
from datetime import datetime, timezone

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

def esc(s: str) -> str:
    return (s or "").replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

class Handler(BaseHTTPRequestHandler):
    def _send(self, status: int, body: bytes, ctype: str):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/api/status":
            d = read_json("runtime/state/projections/system_status.json")
            if d is None:
                out = json.dumps({"error": "system_status.json missing"}).encode("utf-8")
                return self._send(404, out, "application/json")
            out = json.dumps(d, indent=2, sort_keys=True).encode("utf-8")
            return self._send(200, out, "application/json")

        if path == "/api/diagnose":
            d = read_json("runtime/state/projections/diagnose.json")
            if d is None:
                out = json.dumps({"error": "diagnose.json missing (run ./runtime/bin/ops report)"}).encode("utf-8")
                return self._send(404, out, "application/json")
            out = json.dumps(d, indent=2, sort_keys=True).encode("utf-8")
            return self._send(200, out, "application/json")

        if path == "/api/report":
            t = read_text("runtime/state/reports/diagnose.txt")
            if t is None:
                msg = "diagnose.txt missing (run ./runtime/bin/ops report)\n".encode("utf-8")
                return self._send(404, msg, "text/plain; charset=utf-8")
            return self._send(200, t.encode("utf-8"), "text/plain; charset=utf-8")

        if path == "/":
            report = read_text("runtime/state/reports/diagnose.txt") or "diagnose.txt missing (run ./runtime/bin/ops report)\n"
            status = read_json("runtime/state/projections/system_status.json") or {"projections": [], "ok": 0, "errors": ["system_status.json missing"]}

            rows = status.get("projections", [])
            if not isinstance(rows, list):
                rows = []

            table_rows = "\n".join(
                f"<tr><td>{esc(str(r.get('name','')))}</td><td>{esc(str(r.get('status','')))}</td></tr>"
                for r in rows if isinstance(r, dict)
            )

            now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
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
    .muted {{ color:#666; font-size: 0.9em; }}
  </style>
</head>
<body>
  <h2>Runtime Dashboard (read-only)</h2>
  <div class="muted">Rendered at {now}</div>

  <div class="card" style="margin-top:12px;">
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
            return self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")

        return self._send(404, b"not found\n", "text/plain; charset=utf-8")

    def log_message(self, format, *args):
        # quiet
        return

def main():
    host = "127.0.0.1"
    port = 5055
    print(f"Serving on http://{host}:{port}")
    ThreadingHTTPServer((host, port), Handler).serve_forever()

if __name__ == "__main__":
    main()
PY

chmod +x runtime/bin/dashboard
echo "OK: patched dashboard.py to zero-deps http.server"
