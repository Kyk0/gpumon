#!/usr/bin/env python3
"""GPU monitor: polls nvidia-smi on remote hosts over SSH, serves a dashboard + JSON at localhost:8765."""
import json
import os
import re
import subprocess
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8765
INTERVAL = 5          # seconds between polls
HISTORY = 180         # points kept per GPU (15 min at 5 s)
HERE = os.path.dirname(os.path.abspath(__file__))
HOSTS_FILE = os.environ.get("GPUMON_HOSTS", os.path.expanduser("~/.config/gpumon/hosts.json"))

# Host entries: {"label": "box1", "target": "user@box1.example.edu"}.
# target is anything `ssh` accepts as a destination, including ~/.ssh/config aliases.
LABEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,31}$")
TARGET_RE = re.compile(r"^([A-Za-z0-9._-]+@)?[A-Za-z0-9][A-Za-z0-9._-]*$")

SSH_OPTS = [
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=8",
    "-o", "ServerAliveInterval=15",
    "-o", "ControlMaster=auto",
    "-o", "ControlPath=~/.ssh/gpumon-%r@%h:%p",
    "-o", "ControlPersist=10m",
    "-o", "StrictHostKeyChecking=accept-new",
]

REMOTE = r"""
nvidia-smi --query-gpu=index,uuid,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit --format=csv,noheader,nounits
echo '@@'
nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv,noheader,nounits
echo '@@'
P=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader | sort -u | paste -sd, -)
[ -n "$P" ] && ps -ww -o pid=,user:32=,etimes=,args= -p "$P" | cut -c1-400
echo '@@'
cat /proc/loadavg; nproc; free -m | awk '/^Mem:/{print $2, $7}'
"""

state = {}
hosts = []      # ordered list of {"label", "target"}
stops = {}      # label -> threading.Event that stops its poller
lock = threading.Lock()


def load_hosts():
    try:
        with open(HOSTS_FILE) as f:
            return [h for h in json.load(f) if valid(h)]
    except FileNotFoundError:
        return []


def save_hosts():
    os.makedirs(os.path.dirname(HOSTS_FILE), exist_ok=True)
    tmp = HOSTS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(hosts, f, indent=2)
    os.replace(tmp, HOSTS_FILE)


def valid(h):
    return (isinstance(h, dict) and LABEL_RE.match(str(h.get("label", "")))
            and TARGET_RE.match(str(h.get("target", ""))))


def me_for(target):
    """Your username on the remote: explicit user@ part, else whatever ssh config resolves to."""
    if "@" in target:
        return target.split("@", 1)[0]
    try:
        out = subprocess.run(["ssh", "-G", target], capture_output=True, text=True, timeout=5).stdout
        for line in out.splitlines():
            if line.startswith("user "):
                return line.split(None, 1)[1]
    except Exception:
        pass
    return os.environ.get("USER", "")


def start_poller(h):
    state.setdefault(h["label"], {"label": h["label"], "target": h["target"], "ok": None, "gpus": [], "error": "connecting…"})
    ev = threading.Event()
    stops[h["label"]] = ev
    threading.Thread(target=poll, args=(h["label"], h["target"], ev), daemon=True).start()


def add_host(label, target):
    h = {"label": label, "target": target}
    if not valid(h):
        raise ValueError("bad name or ssh target")
    with lock:
        if any(x["label"] == label for x in hosts):
            raise ValueError(f"'{label}' already exists")
        hosts.append(h)
        save_hosts()
        start_poller(h)


def remove_host(label):
    with lock:
        hosts[:] = [x for x in hosts if x["label"] != label]
        save_hosts()
        ev = stops.pop(label, None)
        state.pop(label, None)
    if ev:
        ev.set()


def num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def parse(out, me):
    parts = out.split("@@")
    gpus, by_uuid = [], {}
    for line in parts[0].strip().splitlines():
        f = [x.strip() for x in line.split(",")]
        if len(f) < 9:
            continue
        g = {
            "index": int(f[0]), "uuid": f[1], "name": f[2],
            "util": num(f[3]), "mem_used": num(f[4]), "mem_total": num(f[5]),
            "temp": num(f[6]), "power": num(f[7]), "power_limit": num(f[8]),
            "procs": [],
        }
        gpus.append(g)
        by_uuid[g["uuid"]] = g

    ps = {}
    for line in parts[2].strip().splitlines() if len(parts) > 2 else []:
        f = line.split(None, 3)
        if len(f) >= 3:
            ps[f[0]] = {"user": f[1], "elapsed": int(f[2]) if f[2].isdigit() else None,
                        "cmd": f[3] if len(f) > 3 else ""}

    for line in parts[1].strip().splitlines() if len(parts) > 1 else []:
        f = [x.strip() for x in line.split(",")]
        if len(f) < 3 or f[0] not in by_uuid:
            continue
        info = ps.get(f[1], {"user": "?", "elapsed": None, "cmd": ""})
        by_uuid[f[0]]["procs"].append({
            "pid": int(f[1]), "mem": num(f[2]), **info, "mine": info["user"] == me,
        })
    for g in gpus:
        g["procs"].sort(key=lambda p: -(p["mem"] or 0))

    sysinfo = {}
    if len(parts) > 3:
        lines = parts[3].strip().splitlines()
        try:
            sysinfo["load"] = [float(x) for x in lines[0].split()[:3]]
            sysinfo["cpus"] = int(lines[1])
            tot, avail = lines[2].split()
            sysinfo["ram_total"], sysinfo["ram_avail"] = int(tot), int(avail)
        except (IndexError, ValueError):
            pass
    return gpus, sysinfo


def poll(label, target, stop):
    me = me_for(target)
    hist = {}
    while not stop.is_set():
        t0 = time.time()
        try:
            r = subprocess.run(["ssh", *SSH_OPTS, "--", target, REMOTE],
                               capture_output=True, text=True, timeout=25)
            if r.returncode != 0 and "@@" not in r.stdout:
                raise RuntimeError((r.stderr or "ssh failed").strip().splitlines()[-1])
            gpus, sysinfo = parse(r.stdout, me)
            for g in gpus:
                h = hist.setdefault(g["uuid"], deque(maxlen=HISTORY))
                h.append([round(t0), g["util"], g["mem_used"]])
                g["history"] = list(h)
            entry = {"ok": True, "gpus": gpus, "sys": sysinfo, "updated": t0, "error": None}
        except Exception as e:  # keep last good data, mark stale
            with lock:
                prev = state.get(label, {})
            entry = {**prev, "ok": False, "error": str(e), "failed_at": t0}
            entry.setdefault("gpus", [])
        entry.update(label=label, target=target, me=me)
        with lock:
            if stop.is_set():
                return
            state[label] = entry
        stop.wait(max(0.5, INTERVAL - (time.time() - t0)))


def recommendation(entries):
    """Pick the GPU with the most free memory, tie-break on lower utilization."""
    best = None
    for h in entries:
        if not h.get("ok"):
            continue
        for g in h["gpus"]:
            if g["mem_total"] is None or g["mem_used"] is None:
                continue
            free = g["mem_total"] - g["mem_used"]
            score = free - (g["util"] or 0) * 50
            if best is None or score > best["score"]:
                best = {"host": h["label"], "gpu": g["index"], "free_mb": free,
                        "util": g["util"], "score": score}
    return best


def snapshot():
    with lock:
        entries = [dict(state[h["label"]]) for h in hosts if h["label"] in state]
    return {"hosts": entries, "best": recommendation(entries), "now": time.time(), "interval": INTERVAL}


class Handler(BaseHTTPRequestHandler):
    def _local(self):
        # Block DNS rebinding and cross-site writes: only our own pages (which send X-GPUMon) may modify.
        host = (self.headers.get("Host") or "").split(":")[0]
        return host in ("localhost", "127.0.0.1") and self.headers.get("X-GPUMon") == "1"

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/api/hosts" or not self._local():
            return self._json(403, {"error": "forbidden"})
        try:
            n = int(self.headers.get("Content-Length") or 0)
            d = json.loads(self.rfile.read(min(n, 4096)) or b"{}")
            add_host(str(d.get("label", "")).strip(), str(d.get("target", "")).strip())
            self._json(200, {"ok": True})
        except (ValueError, json.JSONDecodeError) as e:
            self._json(400, {"error": str(e)})

    def do_DELETE(self):
        if not self.path.startswith("/api/hosts/") or not self._local():
            return self._json(403, {"error": "forbidden"})
        remove_host(self.path.rsplit("/", 1)[1])
        self._json(200, {"ok": True})

    def do_GET(self):
        if self.path.startswith("/api/status"):
            body, ctype = json.dumps(snapshot()).encode(), "application/json"
        elif self.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "dashboard.html"), "rb") as f:
                body, ctype = f.read(), "text/html; charset=utf-8"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    hosts.extend(load_hosts())
    for h in hosts:
        start_poller(h)
    print(f"gpumon on http://localhost:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
