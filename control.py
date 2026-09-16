#!/usr/bin/env python3
"""little-cctv control server.

Single public port (default 7357, bound to the wired-LAN interface by run.sh):
  - serves the dashboard (dashboard.html) and static assets
  - GET  /api/status            current res/fps + recording state
  - POST /api/settings          {res,fps} -> write settings.env, restart capture
  - POST /api/record            {action: start|pause|resume|stop}
  - GET  /cam/*                 reverse-proxied to MediaMTX HLS (internal 127.0.0.1:8888)

No auth by design (LAN use, router-side IP restriction assumed).
"""
import json
import os
import signal
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
BIND = os.environ.get("BIND_ADDR", "0.0.0.0")
PORT = int(os.environ.get("PORT", "7357"))
UPSTREAM = os.environ.get("UPSTREAM", "127.0.0.1:8888")          # MediaMTX HLS
RTSP = os.environ.get("RTSP_URL", "rtsp://localhost:8554/cam")   # internal restream
SETTINGS = os.path.join(HERE, "settings.env")
REC_DIR = os.path.join(HERE, "recordings")

ALLOWED_RES = {"1080", "720", "540", "360"}
ALLOWED_FPS = {"30", "60"}
DEFAULTS = {"RES_H": "1080", "FPS": "30"}


# ---------------------------------------------------------------- settings
def read_settings():
    s = dict(DEFAULTS)
    try:
        with open(SETTINGS) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                s[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return s


def write_settings(res, fps):
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w") as f:
        f.write(f"RES_H={res}\nFPS={fps}\n")
    os.replace(tmp, SETTINGS)


def restart_capture():
    # Kill the capture ffmpeg; MediaMTX (runOnInitRestart) relaunches capture.sh,
    # which re-reads settings.env. Motion/recorder read RTSP, not avfoundation.
    subprocess.run(["pkill", "-f", "avfoundation"], check=False)


# ---------------------------------------------------------------- recorder
_lock = threading.Lock()
_rec_proc = None
_rec_state = "idle"        # idle | recording | paused
_rec_started = None        # epoch of the current take's start (None when idle)
_rec_files = []            # basenames written in the current session


def _spawn_recorder():
    global _rec_proc
    os.makedirs(REC_DIR, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    out = os.path.join(REC_DIR, f"rec_{ts}.mp4")
    _rec_proc = subprocess.Popen(
        ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostdin",
         "-rtsp_transport", "tcp", "-i", RTSP,
         "-c", "copy",
         "-movflags", "+frag_keyframe+empty_moov+default_base_moof",
         out],
        stdin=subprocess.DEVNULL)
    _rec_files.append(os.path.basename(out))


def _stop_recorder():
    global _rec_proc
    if _rec_proc and _rec_proc.poll() is None:
        try:
            _rec_proc.send_signal(signal.SIGINT)   # graceful: finalizes the mp4
            _rec_proc.wait(timeout=4)
        except Exception:
            try:
                _rec_proc.kill()
            except Exception:
                pass
    _rec_proc = None


def rec_action(action):
    global _rec_state, _rec_started, _rec_files
    with _lock:
        if action in ("start", "resume"):
            if _rec_state == "idle":
                _rec_files = []
                _rec_started = time.time()
                _spawn_recorder()
                _rec_state = "recording"
            elif _rec_state == "paused":
                _spawn_recorder()
                _rec_state = "recording"
        elif action == "pause":
            if _rec_state == "recording":
                _stop_recorder()
                _rec_state = "paused"
        elif action == "stop":
            _stop_recorder()
            _rec_state = "idle"
            _rec_started = None
        return _rec_status_locked()


def _rec_status_locked():
    return {"state": _rec_state, "since": _rec_started, "files": list(_rec_files)}


def rec_status():
    with _lock:
        return _rec_status_locked()


# ---------------------------------------------------------------- http
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _file(self, path, ctype):
        try:
            with open(path, "rb") as f:
                data = f.read()
        except FileNotFoundError:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def _proxy(self):
        url = f"http://{UPSTREAM}{self.path}"
        try:
            with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as up:
                data = up.read()
                self.send_response(up.status)
                ct = up.headers.get("Content-Type")
                self.send_header("Content-Type", ct or "application/octet-stream")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            self.send_error(e.code)
        except Exception:
            self.send_error(502)

    def do_GET(self):
        p = self.path.split("?", 1)[0]
        if p in ("/", "/index.html"):
            self._file(os.path.join(HERE, "dashboard.html"), "text/html; charset=utf-8")
        elif p == "/api/status":
            s = read_settings()
            self._json({"res": s.get("RES_H", "1080"), "fps": s.get("FPS", "30"),
                        "record": rec_status()})
        elif p.startswith("/static/"):
            name = os.path.basename(p)
            ctype = "application/javascript" if name.endswith(".js") else "text/plain"
            self._file(os.path.join(HERE, "static", name), ctype)
        elif p.startswith("/cam"):
            self._proxy()
        else:
            self.send_error(404)

    def do_POST(self):
        p = self.path.split("?", 1)[0]
        n = int(self.headers.get("Content-Length", "0") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            body = {}
        if p == "/api/settings":
            res, fps = str(body.get("res", "")), str(body.get("fps", ""))
            if res not in ALLOWED_RES or fps not in ALLOWED_FPS:
                self._json({"error": "invalid res/fps"}, 400)
                return
            write_settings(res, fps)
            restart_capture()
            self._json({"ok": True, "res": res, "fps": fps})
        elif p == "/api/record":
            action = str(body.get("action", ""))
            if action not in ("start", "pause", "resume", "stop"):
                self._json({"error": "invalid action"}, 400)
                return
            self._json({"ok": True, "record": rec_action(action)})
        else:
            self.send_error(404)


def main():
    srv = ThreadingHTTPServer((BIND, PORT), Handler)
    srv.daemon_threads = True
    print(f"control.py listening on http://{BIND}:{PORT}  (HLS upstream {UPSTREAM})", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        with _lock:
            _stop_recorder()
        srv.server_close()


if __name__ == "__main__":
    main()
