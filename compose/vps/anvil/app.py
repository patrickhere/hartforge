#!/usr/bin/env python3
"""anvil strike counter. two endpoints behind caddy at /api/anvil/*:
GET /count -> {"strikes": N}
POST /strike -> {"strikes": N, "counted": bool}  (deduped by hashed ip+day)
stdlib only, sqlite storage, no cookies, no identity kept."""
import hashlib
import json
import os
import sqlite3
from datetime import date
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB = "/data/anvil.db"
SALT = os.environ["ANVIL_SALT"]

db = sqlite3.connect(DB, check_same_thread=False)
db.execute("CREATE TABLE IF NOT EXISTS strikes (h TEXT PRIMARY KEY, d TEXT)")
db.execute("CREATE TABLE IF NOT EXISTS total (id INTEGER PRIMARY KEY CHECK (id=1), n INTEGER)")
db.execute("INSERT OR IGNORE INTO total (id, n) VALUES (1, 0)")
db.commit()
import threading
lock = threading.Lock()


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _client_hash(self):
        ip = (self.headers.get("X-Forwarded-For") or self.client_address[0]).split(",")[0].strip()
        return hashlib.sha256(f"{SALT}{ip}{date.today().isoformat()}".encode()).hexdigest()

    def do_GET(self):
        if self.path in ("/count", "/"):
            with lock:
                n = db.execute("SELECT n FROM total WHERE id=1").fetchone()[0]
            self._send(200, {"strikes": n})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/strike":
            self._send(404, {"error": "not found"})
            return
        h = self._client_hash()
        with lock:
            counted = False
            try:
                db.execute("INSERT INTO strikes (h, d) VALUES (?, ?)", (h, date.today().isoformat()))
                db.execute("UPDATE total SET n = n + 1 WHERE id=1")
                db.commit()
                counted = True
            except sqlite3.IntegrityError:
                pass
            # keep the dedupe table from growing forever
            db.execute("DELETE FROM strikes WHERE d < date('now', '-2 day')")
            db.commit()
            n = db.execute("SELECT n FROM total WHERE id=1").fetchone()[0]
        self._send(200, {"strikes": n, "counted": counted})

    def log_message(self, *a):
        pass


ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
