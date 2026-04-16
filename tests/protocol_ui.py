# protocol_ui.py

import threading
import time
import queue
import logging
from flask import Flask, jsonify, request, render_template_string

HTML = """
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Protocol</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: system-ui, sans-serif;
    background: #0f1117;
    color: #e8eaf0;
    display: flex;
    flex-direction: column;
    align-items: center;
    min-height: 100vh;
    padding: 40px 20px;
  }
  h1 { font-size: 1.1rem; font-weight: 500; color: #888; margin-bottom: 32px; letter-spacing: 0.05em; text-transform: uppercase; }

  #setup { display: flex; flex-direction: column; align-items: center; gap: 16px; width: 100%; max-width: 360px; }
  #setup input {
    width: 100%; padding: 12px 16px; border-radius: 8px;
    background: #1c1f2b; border: 1px solid #2e3249; color: #e8eaf0;
    font-size: 1rem; text-align: center; letter-spacing: 0.1em; text-transform: uppercase;
  }
  #setup input:focus { outline: none; border-color: #5c6bc0; }

  #main { width: 100%; max-width: 560px; display: none; flex-direction: column; align-items: center; gap: 24px; }

  #ble-badge {
    font-size: 0.75rem; padding: 4px 12px; border-radius: 20px;
    background: #1c1f2b; border: 1px solid #2e3249; color: #888;
  }
  #ble-badge.connected { border-color: #43a047; color: #66bb6a; }

  #step-counter { font-size: 0.8rem; color: #555; }

  #label {
    font-size: 1.6rem; font-weight: 700; letter-spacing: 0.04em;
    color: #c5cae9; text-align: center;
  }

  #instruction {
    font-size: 1rem; color: #9fa8da; text-align: center;
    min-height: 1.4em;
  }

  #timer-ring { position: relative; width: 160px; height: 160px; }
  #timer-ring svg { transform: rotate(-90deg); }
  #timer-ring circle.track { fill: none; stroke: #1c1f2b; stroke-width: 10; }
  #timer-ring circle.progress {
    fill: none; stroke: #5c6bc0; stroke-width: 10;
    stroke-linecap: round;
    transition: stroke-dashoffset 0.9s linear;
  }
  #timer-text {
    position: absolute; inset: 0;
    display: flex; align-items: center; justify-content: center;
    font-size: 2.4rem; font-weight: 700; color: #e8eaf0;
  }

  .btn {
    padding: 13px 36px; border-radius: 8px; border: none;
    font-size: 1rem; font-weight: 600; cursor: pointer;
    transition: opacity 0.15s, transform 0.1s;
  }
  .btn:active { transform: scale(0.97); }
  .btn:disabled { opacity: 0.3; cursor: default; }

  #btn-start  { background: #5c6bc0; color: #fff; }
  #btn-skip   { background: #1c1f2b; color: #888; border: 1px solid #2e3249; }
  #btn-repeat { background: #1c1f2b; color: #888; border: 1px solid #2e3249; }
  #btn-row { display: flex; gap: 12px; }

  #ref-row { display: flex; gap: 8px; width: 100%; }
  #ref-input {
    flex: 1; padding: 11px 14px; border-radius: 8px;
    background: #1c1f2b; border: 1px solid #2e3249; color: #e8eaf0;
    font-size: 0.95rem;
  }
  #ref-input:focus { outline: none; border-color: #5c6bc0; }
  #ref-input::placeholder { color: #444; }
  #ref-log {
    width: 100%; max-height: 120px; overflow-y: auto;
    font-size: 0.78rem; color: #666; display: flex; flex-direction: column; gap: 4px;
  }
  #ref-log span { color: #7986cb; }

  #done-msg { font-size: 1.2rem; color: #66bb6a; display: none; text-align: center; }
</style>
</head>
<body>
<h1>{{ title }}</h1>

<div id="setup">
  <input id="initials-input" maxlength="4" placeholder="Participant initials" autofocus>
  <button class="btn" id="btn-start-session" style="background:#5c6bc0;color:#fff;width:100%">Connect &amp; Start</button>
  <div id="connect-status" style="font-size:0.8rem;color:#555;min-height:1.2em;text-align:center"></div>
</div>

<div id="main">
  <div id="ble-badge">BLE: connecting…</div>
  <div id="step-counter"></div>
  <div id="label">—</div>
  <div id="instruction"></div>

  <div id="timer-ring">
    <svg width="160" height="160" viewBox="0 0 160 160">
      <circle class="track"    cx="80" cy="80" r="70"/>
      <circle class="progress" cx="80" cy="80" r="70" id="ring-path"
              stroke-dasharray="439.8" stroke-dashoffset="439.8"/>
    </svg>
    <div id="timer-text">—</div>
  </div>

  <div id="btn-row">
    <button class="btn" id="btn-repeat">Repeat prev</button>
    <button class="btn" id="btn-start">Start</button>
    <button class="btn" id="btn-skip">Skip</button>
  </div>

  <div id="ref-row">
    <input id="ref-input" placeholder="{{ ref_placeholder }}" autocomplete="off">
  </div>
  <div id="ref-log"></div>

  <div id="done-msg">Session complete. CSV saved.</div>
</div>

<script>
const CIRCUMFERENCE = 2 * Math.PI * 70;
let pollInterval = null;

document.getElementById("btn-start-session").addEventListener("click", startSession);
document.getElementById("initials-input").addEventListener("keydown", e => {
  if (e.key === "Enter") startSession();
});

async function startSession() {
  const initials = document.getElementById("initials-input").value.trim().toUpperCase();
  if (!initials) return;
  document.getElementById("connect-status").textContent = "Connecting to device…";
  document.getElementById("btn-start-session").disabled = true;

  const res  = await fetch("/api/init", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ initials })
  });
  const data = await res.json();

  if (data.ok) {
    document.getElementById("setup").style.display = "none";
    document.getElementById("main").style.display  = "flex";
    pollInterval = setInterval(poll, 500);
  } else {
    document.getElementById("connect-status").textContent = data.error || "Connection failed.";
    document.getElementById("btn-start-session").disabled = false;
  }
}

async function poll() {
  const s = await (await fetch("/api/state")).json();

  const badge = document.getElementById("ble-badge");
  badge.textContent = s.ble ? "BLE connected" : "BLE disconnected";
  badge.className   = s.ble ? "connected" : "";

  document.getElementById("step-counter").textContent =
    s.done ? "" : `Step ${s.step} / ${s.total}`;
  document.getElementById("label").textContent       = s.label       || "—";
  document.getElementById("instruction").textContent = s.instruction || "";

  const frac = s.duration > 0 ? s.remaining / s.duration : 0;
  document.getElementById("ring-path").style.strokeDashoffset = CIRCUMFERENCE * (1 - frac);
  document.getElementById("timer-text").textContent =
    s.running ? s.remaining : (s.done ? "✓" : "—");

  document.getElementById("btn-start").disabled  = s.running || s.done || !s.waiting;
  document.getElementById("btn-skip").disabled   = s.running || s.done;
  document.getElementById("btn-repeat").disabled = s.running || s.done || s.step <= 1;

  if (s.done) {
    document.getElementById("done-msg").style.display = "block";
    document.getElementById("btn-row").style.display  = "none";
    document.getElementById("ref-row").style.display  = "none";
    clearInterval(pollInterval);
  }
}

document.getElementById("btn-start").addEventListener("click",  () => sendCmd("start"));
document.getElementById("btn-skip").addEventListener("click",   () => sendCmd("skip"));
document.getElementById("btn-repeat").addEventListener("click", () => sendCmd("repeat"));

async function sendCmd(cmd) {
  await fetch("/api/command", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ cmd })
  });
}

// Submit reference reading on Enter — no click needed
document.getElementById("ref-input").addEventListener("keydown", async e => {
  if (e.key !== "Enter") return;
  const val = e.target.value.trim();
  if (!val) return;

  const res  = await fetch("/api/ref", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ value: val })
  });
  const data = await res.json();

  if (data.ok) {
    const entry = document.createElement("div");
    entry.innerHTML = `<span>[REF]</span> ${data.display}`;
    document.getElementById("ref-log").prepend(entry);
    e.target.value = "";
  } else {
    e.target.style.borderColor = "#e53935";
    setTimeout(() => e.target.style.borderColor = "", 600);
  }
});
</script>
</body>
</html>
"""


class ProtocolUI:
    def __init__(
        self,
        steps: list,
        title: str = "Protocol",
        ref_placeholder: str = "reference value",
        on_start=None,
        on_ref=None,
        on_tick=None,
        on_done=None,
        port: int = 5000,
    ):
        self.steps           = steps
        self.title           = title
        self.ref_placeholder = ref_placeholder
        self.on_start        = on_start
        self.on_ref          = on_ref
        self.on_tick         = on_tick
        self.on_done         = on_done
        self.port            = port

        self.action_queue = queue.Queue()
        self.state = {
            "step":        0,
            "total":       len(steps),
            "label":       "",
            "instruction": "",
            "duration":    0,
            "remaining":   0,
            "running":     False,
            "waiting":     True,
            "done":        False,
            "initials":    "",
            "ble":         False,
        }

        self._app = self._build_app()

    def set_ble_status(self, connected: bool):
        self.state["ble"] = connected

    def _run_protocol(self):
        total = len(self.steps)
        i = 0

        while i < total:
            label, duration, instruction = self.steps[i]

            self.state.update({
                "step":        i + 1,
                "label":       label,
                "instruction": instruction,
                "duration":    duration,
                "remaining":   duration,
                "running":     False,
                "waiting":     True,
            })

            cmd = self.action_queue.get()

            if cmd == "skip":
                print(f"  {label} marked invalid, skipping.")
                i += 1
                continue

            if cmd == "repeat" and i > 0:
                prev_label, prev_dur, prev_instr = self.steps[i - 1]
                print(f"\nRepeating: {prev_label}  ({prev_dur}s)")
                self._run_countdown(prev_label + "_REPEAT", prev_dur, prev_instr)

                # Re-prompt for the current step after the repeat
                self.state.update({
                    "label":       label,
                    "instruction": instruction,
                    "remaining":   duration,
                    "waiting":     True,
                    "running":     False,
                })
                cmd = self.action_queue.get()
                if cmd == "skip":
                    print(f"  {label} marked invalid, skipping.")
                    i += 1
                    continue

            print(f"\nStep {i+1}/{total}  {label}  ({duration}s)")
            self._run_countdown(label, duration, instruction)
            print("  Done.")
            i += 1

        self.state["done"] = True
        if self.on_done:
            self.on_done(partial=False)

    def _run_countdown(self, label: str, duration: int, instruction: str):
      self.state.update({
          "label":       label,
          "instruction": instruction,
          "duration":    duration,
          "remaining":   duration,
          "running":     True,
          "waiting":     False,
      })
      for remaining in range(duration, -1, -1):  # now goes to 0
          self.state["remaining"] = remaining
          if self.on_tick:
              self.on_tick(label, remaining)
          if remaining > 0:
              time.sleep(1)
      self.state["running"] = False

    def _build_app(self):
        app = Flask(__name__)

        # Suppress Flask/werkzeug request logs
        logging.getLogger("werkzeug").setLevel(logging.ERROR)
        app.logger.disabled = True

        ui = self  # Reference for use inside route closures

        @app.route("/")
        def index():
            return render_template_string(
                HTML,
                title=ui.title,
                ref_placeholder=ui.ref_placeholder,
            )

        @app.route("/api/state")
        def api_state():
            return jsonify(ui.state)

        @app.route("/api/init", methods=["POST"])
        def api_init():
            if ui.state["initials"]:
                return jsonify({"ok": False, "error": "Session already started."})

            data     = request.get_json()
            initials = data.get("initials", "XX").strip().upper() or "XX"
            ui.state["initials"] = initials

            # on_start handles BLE connection and any other setup; returns True on success
            if ui.on_start:
                ok = ui.on_start(initials)
                if not ok:
                    ui.state["initials"] = ""
                    return jsonify({"ok": False, "error": f"Could not connect to device."})

            threading.Thread(target=ui._run_protocol, daemon=True).start()
            return jsonify({"ok": True})

        @app.route("/api/command", methods=["POST"])
        def api_command():
            cmd = request.get_json().get("cmd", "")
            if cmd in ("start", "skip", "repeat"):
                ui.action_queue.put(cmd)
            return jsonify({"ok": True})

        @app.route("/api/ref", methods=["POST"])
        def api_ref():
            value = request.get_json().get("value", "").strip()
            if ui.on_ref:
                result = ui.on_ref(value)
                if result:
                    return jsonify(result)
            return jsonify({"ok": False})

        return app

    def run(self, port: int = None):
        p = port or self.port
        print(f"Open http://localhost:{p} in your browser.")
        try:
            self._app.run(host="0.0.0.0", port=p, threaded=True)
        finally:
            # Save whatever was collected if the protocol didn't finish normally
            if not self.state["done"] and self.on_done:
                print("\nInterrupted — saving partial data.")
                self.on_done(partial=True)