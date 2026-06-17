#!/usr/bin/env python3
"""Hermes Dispatch, a two-layer mobile chat over the Hermes agent roster.

Layer 1 (dispatcher): a persistent chat. Each user message goes to a capable
"dispatcher" model (the `reasoning` alias) which BOTH (a) rewrites the request into
a detailed, agent-tuned prompt and (b) routes it to the best agent, returning
JSON {agent, expanded_prompt, reasoning}.

Layer 2 (agent execution): the expanded prompt is sent to the chosen agent using
that agent's own system prompt (~/.hermes/profiles/<name>/SOUL.md) and pinned
model (config.yaml), streamed back token-by-token.

Output stays clean WITHOUT re-implementing Hermes' post-processing: the local
reasoning models route their chain-of-thought to a separate `reasoning_content`
field, so we simply stream `delta.content` and ignore `reasoning_content` (plus a
defensive inline-<think> stripper). This matches what `<agent>/run.sh` emits.

Stdlib only (no pip installs) so launchd can run it with the system python.

Endpoints:
  GET  /            -> index.html (mobile chat UI)
  GET  /agents      -> {agents:[{name, model, desc}]}   (reads ~/.hermes/profiles)
  GET  /history     -> {turns:[...]}                     (full conversation)
  POST /chat        -> SSE: {type:routing}, {type:token}*, {type:done} | {type:error}
  GET  /healthz     -> "ok"
"""
from __future__ import annotations

import datetime
import json
import os
import queue
import re
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = os.environ.get("HERMES_DISPATCH_HOST", "0.0.0.0")
PORT = int(os.environ.get("HERMES_DISPATCH_PORT", "7777"))
# Cap request bodies so a bogus/huge Content-Length can't make the server allocate without bound.
MAX_BODY_BYTES = int(os.environ.get("HERMES_DISPATCH_MAX_BODY", str(8 * 1024 * 1024)))
HERMES_HOME = Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))
PROFILES_DIR = HERMES_HOME / "profiles"
ENV_FILE = HERMES_HOME / ".env"
DISPATCH_HOME = Path(os.environ.get("HERMES_DISPATCH_HOME", str(Path.home() / ".hermes-dispatch")))
HISTORY_FILE = DISPATCH_HOME / "history.json"
LITELLM_BASE = os.environ.get("LITELLM_BASE", "http://localhost:4000/v1")
DISPATCHER_MODEL = os.environ.get("HERMES_DISPATCHER_MODEL", "reasoning")
# Two-tier dispatch: a fast model routes/classifies, a capable model expands the prompt.
ROUTER_MODEL = os.environ.get("HERMES_ROUTER_MODEL", "structured")
ENHANCER_MODEL = os.environ.get("HERMES_ENHANCER_MODEL", DISPATCHER_MODEL)
HISTORY_CONTEXT_TURNS = 20

# Artifacts, shared store so Hermes desktop can pick them up. Default under
# ~/.hermes/artifacts; override with HERMES_ARTIFACTS_DIR if desktop uses another path.
ARTIFACTS_ROOT = Path(os.environ.get("HERMES_ARTIFACTS_DIR", str(HERMES_HOME / "artifacts")))
# Hermes' SQLite session store, desktop reads this, so we record mobile turns here too.
STATE_DB = Path(os.environ.get("HERMES_STATE_DB", str(HERMES_HOME / "state.db")))

# Obsidian vault (for the optional save-to-vault action). Disabled by default:
# set OBSIDIAN_VAULT to your vault's absolute path to enable. Leave blank to turn
# the whole save-to-vault feature off (no intent matching, no endpoint action).
_VAULT_ENV = os.environ.get("OBSIDIAN_VAULT", "").strip()
OBSIDIAN_ENABLED = bool(_VAULT_ENV)
VAULT = Path(_VAULT_ENV).expanduser() if _VAULT_ENV else None
OBSIDIAN_BIN = os.environ.get("OBSIDIAN_BIN") or shutil.which("obsidian") or "obsidian"
PINNED_CONTEXT_MAX = 4000   # chars of pinned artifact shown to the dispatcher
# Titling a note is trivial, use a fast model, not the slow r1 dispatcher.
TITLE_MODEL = os.environ.get("HERMES_TITLE_MODEL", "structured")

HERE = Path(__file__).resolve().parent
INDEX = HERE / "index.html"
HIDDEN_PROFILES = {"default"}

# Pipeline execution (multi-step orchestration via bin/run-pipeline.sh). The dispatch server
# can run a whole pipeline (e.g. dev-workflow) for a "pipeline"-type session, not just one agent.
REPO_ROOT = HERE.parent
PIPELINES_DIR = REPO_ROOT / "pipelines"
RUN_ROOT = REPO_ROOT / "run"
RUN_PIPELINE_SH = REPO_ROOT / "bin" / "run-pipeline.sh"

_hist_lock = threading.Lock()


def conversation_id() -> str:
    """Stable id for this dispatch conversation (one history.json = one conversation)."""
    f = DISPATCH_HOME / "conversation_id"
    try:
        return f.read_text().strip()
    except OSError:
        cid = uuid.uuid4().hex[:12]
        DISPATCH_HOME.mkdir(parents=True, exist_ok=True)
        f.write_text(cid)
        return cid


# --------------------------------------------------------------------------- #
# Config / profiles
# --------------------------------------------------------------------------- #
def litellm_key() -> str:
    key = os.environ.get("LITELLM_MASTER_KEY")
    if key:
        return key.strip()
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            m = re.match(r"^(?:export\s+)?LITELLM_MASTER_KEY=(.*)$", line.strip())
            if m:
                return m.group(1).strip().strip('"').strip("'")
    return ""


def _profile_model(config_text: str) -> str:
    in_model = False
    for raw in config_text.splitlines():
        if re.match(r"^\S", raw):
            in_model = raw.startswith("model:")
            continue
        if in_model:
            m = re.match(r"^\s+default:\s*(\S+)", raw)
            if m:
                return m.group(1).strip().strip('"').strip("'")
    return ""


def _soul_desc(soul: str) -> str:
    """One-line description: the first sentence of the agent's SOUL prompt."""
    for para in soul.strip().split("\n\n"):
        line = " ".join(para.split())
        if not line:
            continue
        sentence = re.split(r"(?<=[.!?])\s", line)[0]
        return (sentence[:200]).strip()
    return ""


def read_profiles() -> dict:
    """{name: {"model": alias, "soul": text, "desc": one-liner}} from ~/.hermes/profiles."""
    out = {}
    if not PROFILES_DIR.is_dir():
        return out
    for d in sorted(PROFILES_DIR.iterdir()):
        if not d.is_dir() or d.name in HIDDEN_PROFILES:
            continue
        cfg, soul_f = d / "config.yaml", d / "SOUL.md"
        if not cfg.exists() or not soul_f.exists():
            continue
        model = _profile_model(cfg.read_text())
        if not model:
            continue
        soul = soul_f.read_text().strip()
        out[d.name] = {"model": model, "soul": soul, "desc": _soul_desc(soul)}
    return out


# --------------------------------------------------------------------------- #
# Sessions, each conversation is an independent record at sessions/<id>.json:
# {id, type: "dispatch"|"direct", agent, title, created_at, updated_at,
#  pinned, turns:[...]}. Turn shape is unchanged from the single-history design.
# --------------------------------------------------------------------------- #
SESSIONS_DIR = DISPATCH_HOME / "sessions"
PIN_FILE = DISPATCH_HOME / "pin.json"          # legacy single pin (migrated once)


def _now() -> str:
    return datetime.datetime.now().isoformat(timespec="seconds")


def _sess_file(sid: str) -> Path:
    return SESSIONS_DIR / f"{sid}.json"


def load_session(sid: str) -> dict | None:
    try:
        return json.loads(_sess_file(sid).read_text())
    except (OSError, ValueError):
        return None


def save_session(s: dict) -> None:
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
    f = _sess_file(s["id"])
    tmp = f.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(s, indent=2))
    tmp.replace(f)


def delete_session(sid: str) -> bool:
    """Delete a session file. Returns True if it existed and was removed."""
    if not sid:
        return False
    with _hist_lock:
        f = _sess_file(sid)
        try:
            if f.exists():
                f.unlink()
                return True
        except OSError:
            pass
    return False


def create_session(stype: str = "dispatch", agent: str | None = None,
                   pipeline: str | None = None) -> dict:
    now = datetime.datetime.now()
    sid = f"{now:%Y%m%d_%H%M%S}_{uuid.uuid4().hex[:6]}"
    s = {"id": sid, "type": stype, "agent": agent, "pipeline": pipeline, "title": "",
         "created_at": now.isoformat(timespec="seconds"),
         "updated_at": now.isoformat(timespec="seconds"), "pinned": None, "turns": []}
    save_session(s)
    return s


def set_session_meta(sid: str, **fields) -> None:
    """Set top-level session fields (e.g. pipeline_run_id, pipeline_status) under the lock."""
    with _hist_lock:
        s = load_session(sid)
        if s:
            s.update(fields)
            s["updated_at"] = _now()
            save_session(s)


def discover_pipelines() -> dict:
    """name -> {description, steps, n_steps} from pipelines/*.json (skips routes.json)."""
    out: dict = {}
    if not PIPELINES_DIR.is_dir():
        return out
    for f in sorted(PIPELINES_DIR.glob("*.json")):
        if f.name == "routes.json":
            continue
        try:
            d = json.loads(f.read_text())
        except Exception:
            continue
        name = d.get("name") or f.stem
        steps = d.get("steps", []) or []
        out[name] = {
            "name": name,
            "description": (d.get("description") or "")[:400],
            "steps": [s.get("id") for s in steps],
            "n_steps": len(steps),
        }
    return out


def _step_output_summary(rd: Path, step: dict) -> str:
    """A one-line summary for a finished step: the first non-empty line of its
    written output, or (on failure) the last line of its captured stderr. Trimmed
    to a phone-friendly length. Best-effort — never raises."""
    of = step.get("output_file")
    if of:
        try:
            text = (rd / of).read_text(encoding="utf-8", errors="replace")
            first = next((ln.strip() for ln in text.splitlines() if ln.strip()), "")
            if first:
                return first[:160]
        except OSError:
            pass
    if step.get("status") == "error":
        try:
            errs = (rd / f"{step.get('id', '')}.stderr").read_text(
                encoding="utf-8", errors="replace").splitlines()
            tail = next((ln.strip() for ln in reversed(errs) if ln.strip()), "")
            if tail:
                return tail[:160]
        except OSError:
            pass
    return ""


def pipeline_status_snapshot(run_id: str, pipeline: str | None = None) -> dict | None:
    """Normalized progress snapshot for a run, read from its state.json. Powers the
    /pipeline-status poll the client uses to re-attach to an in-flight run after a
    reload (when there's no live SSE stream to subscribe to). None if no such run."""
    rd = RUN_ROOT / (run_id or "")
    try:
        state = json.loads((rd / "state.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    pname = pipeline or state.get("pipeline") or ""
    meta = discover_pipelines().get(pname, {})
    steps = []
    for st in state.get("steps", []):
        status = st.get("status", "")
        steps.append({
            "id": st.get("id", ""),
            "agent": st.get("agent", "") or "",
            "status": status,
            "exit_code": st.get("exit_code"),
            "cycle": st.get("revision_cycles"),
            "summary": _step_output_summary(rd, st) if status in ("done", "error") else "",
        })
    return {"run_id": run_id, "pipeline": pname, "status": state.get("status", ""),
            "n_steps": meta.get("n_steps") or len(steps),
            "step_ids": meta.get("steps") or [], "steps": steps}


def _title_from(text: str) -> str:
    return " ".join((text or "").split())[:50]


def append_session_turn(sid: str, turn: dict) -> int | None:
    with _hist_lock:
        s = load_session(sid)
        if s is None:
            return None
        if not s.get("title") and turn.get("user_input"):
            s["title"] = _title_from(turn["user_input"])
        s["turns"].append(turn)
        s["updated_at"] = _now()
        save_session(s)
        return len(s["turns"]) - 1


def update_session_turn(sid: str, idx: int, **fields) -> None:
    with _hist_lock:
        s = load_session(sid)
        if not s or not (0 <= idx < len(s["turns"])):
            return
        s["turns"][idx].update(fields)
        s["updated_at"] = _now()
        save_session(s)


def set_session_pin(sid: str, obj: dict | None) -> None:
    with _hist_lock:
        s = load_session(sid)
        if s:
            s["pinned"] = obj
            save_session(s)


def system_turn(text: str, ok: bool = True, system_kind: str = "obsidian-save") -> dict:
    return {"timestamp": _now(), "kind": "system",
            "system_kind": system_kind, "text": text, "ok": ok}


def most_recent_artifact_in(turns: list) -> dict | None:
    for t in reversed(turns):
        if t.get("artifact_id"):
            return {"artifact_id": t["artifact_id"], "agent": t.get("agent_selected", "")}
    return None


def session_summary(s: dict) -> dict:
    agents = []
    for t in s.get("turns", []):
        a = t.get("agent_selected")
        if a and a != "obsidian-save" and a not in agents:
            agents.append(a)
    if s.get("type") == "direct" and s.get("agent") and s["agent"] not in agents:
        agents.insert(0, s["agent"])
    count = sum(1 for t in s.get("turns", [])
                if t.get("kind") != "system" and (t.get("user_input") or t.get("agent_selected")))
    return {"id": s["id"], "type": s.get("type", "dispatch"), "agent": s.get("agent"),
            "title": s.get("title") or "(untitled)", "created_at": s.get("created_at"),
            "updated_at": s.get("updated_at"), "agents": agents, "turns": count}


def list_sessions() -> list:
    out = []
    if SESSIONS_DIR.is_dir():
        for f in SESSIONS_DIR.glob("*.json"):
            try:
                out.append(session_summary(json.loads(f.read_text())))
            except Exception:
                continue
    out.sort(key=lambda x: x.get("updated_at") or "", reverse=True)
    return out


def migrate_legacy_history() -> None:
    """One-time import of the old single history.json (+pin.json) as a dispatch session."""
    if SESSIONS_DIR.is_dir() and any(SESSIONS_DIR.glob("*.json")):
        return
    try:
        turns = json.loads(HISTORY_FILE.read_text()) if HISTORY_FILE.exists() else []
    except (OSError, ValueError):
        turns = []
    if not turns:
        return
    s = create_session("dispatch")
    s["turns"] = turns
    for t in turns:
        if t.get("user_input"):
            s["title"] = _title_from(t["user_input"])
            break
    try:
        s["pinned"] = json.loads(PIN_FILE.read_text())
    except (OSError, ValueError):
        s["pinned"] = None
    save_session(s)


# --------------------------------------------------------------------------- #
# Orphan recovery — on startup, clear pipeline steps left `running` by a crashed
# or restarted orchestrator so the UI doesn't show a phantom "running…" forever.
# --------------------------------------------------------------------------- #
def _utc_now() -> str:
    """UTC timestamp in the same format orchestrate.sh writes (date -u +%Y-%m-%dT%H:%M:%SZ)."""
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:      # exists but owned by another user
        return True
    return True


def _orchestrator_alive(rd: Path) -> bool:
    """True if a live orchestrator is driving run dir `rd`. bin/run-pipeline.sh writes its PID
    to run/<id>/orchestrator.pid while a run is in flight and removes it on any clean exit, so a
    present-and-live pidfile means work is genuinely running; a missing or stale (dead-pid) file
    means the orchestrator is gone."""
    try:
        pid = int((rd / "orchestrator.pid").read_text().strip())
    except (OSError, ValueError):
        return False
    return _pid_alive(pid)


def recover_orphaned_pipelines() -> None:
    """Startup sweep: clear pipeline steps left `running` by a crashed or restarted orchestrator.

    If this server (or its orchestrator children) was killed mid-run — e.g. a launchd restart
    tore the process group down between a step starting and finishing — state.json keeps a step
    pinned at `running` and the UI shows a phantom "running…" forever. For every session marked
    `pipeline_status=running`, we check the run's orchestrator pidfile: if no live process is
    driving it, the still-`running` step was orphaned, so mark it `needs-human` (resumable; the
    UI already understands this state) and pause the run. Genuinely-live runs are left untouched."""
    if not SESSIONS_DIR.is_dir():
        return
    for sf in SESSIONS_DIR.glob("*.json"):
        try:
            sess = json.loads(sf.read_text())
        except (OSError, ValueError):
            continue
        if sess.get("pipeline_status") != "running":
            continue
        sid = sess.get("id", "")
        run_id = sess.get("pipeline_run_id") or ""
        rd = RUN_ROOT / run_id
        sjf = rd / "state.json"
        if not run_id or not sjf.exists():
            # Session says running but there's no run to verify — clear the phantom on the session.
            set_session_meta(sid, pipeline_status="interrupted")
            print(f"recover: session {sid} pipeline_status=running with no run dir → interrupted",
                  file=sys.stderr)
            continue
        if _orchestrator_alive(rd):
            continue                          # a real process is still driving this run
        try:
            state = json.loads(sjf.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        orphaned = [st for st in state.get("steps", []) if st.get("status") == "running"]
        if not orphaned:
            continue
        for st in orphaned:
            st["status"] = "needs-human"
            st["ended_at"] = st.get("ended_at") or _utc_now()
            st["interrupted"] = True
            st["interrupted_reason"] = "orphaned by server/orchestrator restart"
            print(f"recover: run {run_id} step '{st.get('id')}' orphaned "
                  f"(no live orchestrator) → needs-human", file=sys.stderr)
        if state.get("status") == "running":
            state["status"] = "paused"
        state["updated_at"] = _utc_now()
        tmp = sjf.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(state, indent=2))
        try:
            tmp.chmod(sjf.stat().st_mode & 0o777)   # preserve the run state's mode (0600)
        except OSError:
            pass
        tmp.replace(sjf)
        set_session_meta(sid, pipeline_status="needs-human")


# --------------------------------------------------------------------------- #
# Artifacts (shared with Hermes desktop via the artifacts dir)
# --------------------------------------------------------------------------- #
def _artifact_ext(content: str) -> str:
    s = content.strip()
    if not s:
        return "txt"
    try:
        json.loads(s)
        return "json"
    except ValueError:
        return "md"


def write_artifact(agent: str, content: str, expanded_prompt: str, model: str,
                   run_id: str, conv_id: str) -> str | None:
    """Persist an agent response as an artifact + sidecar meta. Returns the
    artifact id (path relative to ARTIFACTS_ROOT), or None for empty content."""
    if not content.strip():
        return None
    now = datetime.datetime.now()
    day = now.strftime("%Y-%m-%d")
    day_dir = ARTIFACTS_ROOT / day
    day_dir.mkdir(parents=True, exist_ok=True)
    ext = _artifact_ext(content)
    stem = f"{now.strftime('%H%M%S')}-{agent}"
    art = day_dir / f"{stem}.{ext}"
    n = 1
    while art.exists():
        stem = f"{now.strftime('%H%M%S')}-{agent}-{n}"
        art = day_dir / f"{stem}.{ext}"
        n += 1
    art.write_text(content)
    meta = {
        "agent": agent,
        "timestamp": now.isoformat(timespec="seconds"),
        "expanded_prompt": expanded_prompt,
        "model": model,
        "run_id": run_id,
        "conversation_id": conv_id,
    }
    (day_dir / f"{stem}.meta.json").write_text(json.dumps(meta, indent=2))
    return f"{day}/{art.name}"


def resolve_artifact(artifact_id: str) -> Path:
    """Resolve an artifact id to a path, guarding against traversal."""
    root = ARTIFACTS_ROOT.resolve()
    p = (ARTIFACTS_ROOT / artifact_id).resolve()
    if not (p == root or str(p).startswith(str(root) + os.sep)):
        raise ValueError("artifact path outside store")
    if not p.is_file():
        raise FileNotFoundError(artifact_id)
    return p


# --------------------------------------------------------------------------- #
# Hermes session store, record mobile turns so they appear in Hermes desktop
# (which reads the SQLite `sessions`/`messages` tables in ~/.hermes/state.db).
# Mirrors what `hermes chat` writes: a session row (model + system_prompt) plus
# user/assistant message rows. messages FTS is maintained by table triggers, so
# plain INSERTs are enough.
# --------------------------------------------------------------------------- #
def _est_tokens(*texts: str) -> int:
    return sum(len(t or "") for t in texts) // 4


def record_hermes_session(agent: str, model: str, system_prompt: str, user_input: str,
                          assistant_output: str, started_at: float, ended_at: float) -> str | None:
    if not STATE_DB.exists():
        return None
    sid = f"{datetime.datetime.fromtimestamp(started_at):%Y%m%d_%H%M%S}_{uuid.uuid4().hex[:6]}"
    try:
        conn = sqlite3.connect(str(STATE_DB), timeout=30)
        try:
            conn.execute("PRAGMA busy_timeout=30000")
            conn.execute(
                "INSERT INTO sessions (id, source, model, model_config, system_prompt, "
                "started_at, ended_at, end_reason, message_count, input_tokens, output_tokens, "
                "billing_provider, cwd, title) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid, "cli", model, '{"max_iterations": 1}', system_prompt,
                 started_at, ended_at, "completed", 2,
                 _est_tokens(system_prompt, user_input), _est_tokens(assistant_output),
                 "custom:litellm", str(HERE.parent), None),
            )
            conn.execute(
                "INSERT INTO messages (session_id, role, content, timestamp, token_count) "
                "VALUES (?,?,?,?,?)",
                (sid, "user", user_input, started_at, _est_tokens(user_input)))
            conn.execute(
                "INSERT INTO messages (session_id, role, content, timestamp, token_count, finish_reason) "
                "VALUES (?,?,?,?,?,?)",
                (sid, "assistant", assistant_output, ended_at, _est_tokens(assistant_output), "stop"))
            conn.commit()
            return sid
        finally:
            conn.close()
    except Exception:
        return None   # session recording must never break a turn


# --------------------------------------------------------------------------- #
# Obsidian save (a direct side-action, not an agent)
# --------------------------------------------------------------------------- #
_OBS_INTENT = re.compile(
    r"\b(obsidian|vault)\b"
    r"|\b(save|log|add|put|stash|file)\b[^.]{0,40}\bnotes?\b"
    r"|\b(save|log|stash)\s+(this|that|it)\b",
    re.I,
)


def is_obsidian_intent(message: str) -> bool:
    if not OBSIDIAN_ENABLED:
        return False
    return bool(_OBS_INTENT.search(message or ""))


def _safe_title(title: str) -> str:
    title = re.sub(r'[\\/:*?"<>|\n\r\t]', " ", title or "").strip()
    title = re.sub(r"\s+", " ", title)
    return (title or "Hermes note")[:80]


_GENERIC_HEADINGS = {"verdict", "findings", "summary", "introduction", "overview",
                     "output", "result", "results", "analysis", "notes", "note"}


def _first_heading(content: str) -> str | None:
    for line in content.splitlines()[:6]:
        m = re.match(r"^#{1,3}\s+(.+)", line.strip())
        if m:
            h = m.group(1).strip().rstrip(":")
            if 3 <= len(h) <= 70 and h.lower() not in _GENERIC_HEADINGS:
                return h
            return None   # first heading is generic, fall through
    return None


def obsidian_title(content: str, source_agent: str) -> str:
    """A good note title: the first real heading, else a fast-model title for
    headingless prose, else a deterministic agent+date title. Avoids calling the
    LLM for structured output (where the first line is data, not a title)."""
    day = datetime.date.today().isoformat()
    structured = content.lstrip()[:1] in ("{", "[", '"')
    if not structured:
        h = _first_heading(content)
        if h:
            return _safe_title(h)
        try:
            resp = _post(TITLE_MODEL,
                         [{"role": "system", "content":
                           "Give a concise descriptive note title (3-8 words) for the "
                           "content. Reply with ONLY the title text, no quotes, no prose."},
                          {"role": "user", "content": content[:6000]}],
                         stream=False, timeout=60)
            data = json.loads(resp.read().decode("utf-8", "replace"))
            raw = (data.get("choices", [{}])[0].get("message", {}) or {}).get("content", "") or ""
            raw = re.sub(r"<think>.*?</think>", "", raw, flags=re.S).strip().strip('"').splitlines()[0:1]
            t = _safe_title(raw[0] if raw else "")
            if t and t != "Hermes note" and "obsidian" not in t.lower() and t.lower() not in _GENERIC_HEADINGS:
                return t
        except Exception:
            pass
    return _safe_title(f"{source_agent or 'hermes'} {day}")


def obsidian_save(content: str, source_agent: str) -> dict:
    """Save artifact content as a vault note and commit the vault.

    Tries the Obsidian CLI first (works when run interactively with the app),
    but the CLI talks to the GUI app over IPC that the launchd daemon can't
    reach, so we VERIFY the file actually landed and fall back to writing the
    markdown into the vault directly (which is exactly what `obsidian create`
    does). This makes the action reliable headless / from the phone."""
    if not OBSIDIAN_ENABLED:
        return {"ok": False, "error": "Obsidian integration disabled (set OBSIDIAN_VAULT to enable)"}
    if not content.strip():
        return {"ok": False, "error": "nothing to save (empty artifact)"}
    title = obsidian_title(content, source_agent)
    body = content[:200000]

    name = title
    target = VAULT / f"{name}.md"
    if target.exists():   # don't clobber an existing note
        name = f"{title} {datetime.datetime.now().strftime('%H%M%S')}"
        target = VAULT / f"{name}.md"

    via = None
    try:   # 1) Obsidian CLI
        subprocess.run([OBSIDIAN_BIN, f"name={name}", f"content={body}", "silent"],
                       capture_output=True, text=True, timeout=30)
        for _ in range(6):
            if target.exists():
                via = "cli"; break
            time.sleep(0.5)
    except Exception:
        pass
    if via is None:   # 2) direct write (reliable when the CLI can't reach the app)
        try:
            target.write_text(body)
            via = "file"
        except Exception as e:
            return {"ok": False, "error": f"could not write note: {e}"}

    # Stage/commit ONLY this note. `git add -A` / `status` scan the whole tree,
    # which hangs for a launchd daemon against an iCloud vault; a pathspec touches
    # just the one file and the index.
    rel = f"{name}.md"
    committed = False
    detail = ""
    try:
        a = subprocess.run(["git", "-C", str(VAULT), "add", "--", rel],
                           capture_output=True, text=True, timeout=30)
        c = subprocess.run(["git", "-C", str(VAULT), "commit", "-m", f"docs: {name}", "--", rel],
                           capture_output=True, text=True, timeout=30)
        committed = c.returncode == 0
        detail = f"add_rc={a.returncode} commit_rc={c.returncode} out={(c.stdout or c.stderr)[:160]!r}"
    except subprocess.TimeoutExpired:
        detail = "git timed out (launchd may lack Full Disk Access to the iCloud vault)"
    except Exception as e:
        detail = f"exception: {e}"
    message = f"Saved to Obsidian as '{name}'"
    if not committed:
        message += " (note written; vault commit pending, see Full Disk Access in README)"
    return {"ok": True, "title": name, "committed": committed, "via": via,
            "git_detail": detail, "message": message}


def obsidian_system_text(result: dict) -> tuple[str, bool]:
    """The persistent chat-thread message for an Obsidian save result."""
    if result.get("ok"):
        t = result.get("title", "note")
        msg = f'📝 **Saved to Obsidian**, "{t}" added to the vault as `{t}.md`.'
        if not result.get("committed"):
            msg += " _(commit pending, see Full Disk Access)_"
        return msg, True
    return f'⚠️ Obsidian save failed: {result.get("error", "unknown error")}', False


# --------------------------------------------------------------------------- #
# Inline <think> stripper (defensive; survives tag splits across stream chunks)
# --------------------------------------------------------------------------- #
class ThinkFilter:
    OPEN, CLOSE = "<think>", "</think>"

    def __init__(self):
        self.in_think = False
        self.buf = ""

    def feed(self, text: str) -> str:
        self.buf += text
        out = []
        while self.buf:
            if not self.in_think:
                i = self.buf.find(self.OPEN)
                if i == -1:
                    # hold back a possible partial "<think>" at the tail
                    keep = self._tail_keep(self.OPEN)
                    out.append(self.buf[: len(self.buf) - keep])
                    self.buf = self.buf[len(self.buf) - keep:]
                    break
                out.append(self.buf[:i])
                self.buf = self.buf[i + len(self.OPEN):]
                self.in_think = True
            else:
                j = self.buf.find(self.CLOSE)
                if j == -1:
                    keep = self._tail_keep(self.CLOSE)
                    self.buf = self.buf[len(self.buf) - keep:]  # suppress rest
                    break
                self.buf = self.buf[j + len(self.CLOSE):]
                self.in_think = False
        return "".join(out)

    def _tail_keep(self, tag: str) -> int:
        """How many trailing chars of buf could be the start of `tag`."""
        for k in range(min(len(tag) - 1, len(self.buf)), 0, -1):
            if self.buf.endswith(tag[:k]):
                return k
        return 0


# --------------------------------------------------------------------------- #
# LiteLLM calls
# --------------------------------------------------------------------------- #
def _post(model: str, messages: list, stream: bool, timeout: int):
    body = json.dumps({"model": model, "stream": stream, "messages": messages}).encode()
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {litellm_key()}"}
    if stream:
        headers["Accept"] = "text/event-stream"
    req = urllib.request.Request(
        f"{LITELLM_BASE}/chat/completions", data=body, method="POST", headers=headers
    )
    return urllib.request.urlopen(req, timeout=timeout)


def _model_content(model: str, system: str, user: str, timeout: int) -> str:
    """One non-streaming completion → cleaned assistant text (reasoning stripped)."""
    resp = _post(model, [{"role": "system", "content": system},
                         {"role": "user", "content": user}], stream=False, timeout=timeout)
    data = json.loads(resp.read().decode("utf-8", "replace"))
    text = (data.get("choices", [{}])[0].get("message", {}) or {}).get("content", "") or ""
    return re.sub(r"<think>.*?</think>", "", text, flags=re.S).strip()


def _extract_json(text: str) -> dict | None:
    text = re.sub(r"^```(?:json)?|```$", "", text, flags=re.M).strip()
    try:
        return json.loads(text)
    except ValueError:
        pass
    start = text.find("{")
    while start != -1:
        depth = 0
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start:i + 1])
                    except ValueError:
                        break
        start = text.find("{", start + 1)
    return None


def _convo(history: list) -> str:
    recent = history[-HISTORY_CONTEXT_TURNS:]
    if not recent:
        return ""
    return "CONVERSATION SO FAR:\n" + "\n".join(
        f'{i+1}. user: "{t.get("user_input","")}"  -> agent: {t.get("agent_selected","?")}'
        for i, t in enumerate(recent)) + "\n\n"


def route_request(message: str, profiles: dict, history: list) -> dict:
    """Tier 1, router. Returns {agent, intent_summary, domain}. Tries the fast model
    first; if it doesn't yield a valid agent (small models sometimes answer instead of
    routing), falls back to the capable model."""
    roster = "\n".join(f"- {n}: {p['desc'][:70]}" for n, p in profiles.items())
    system = (
        "You are a request router. Do NOT answer or perform the user's request, only "
        "route it. Pick the single best agent from the list for the user's latest request "
        'and classify it. Respond with ONLY a JSON object: {"agent": "<exact name from the '
        'list>", "intent_summary": "<one sentence: what the user wants>", "domain": "<one '
        'of: sales, ops, writing, code, research, legal, finance, productivity, other>"}. '
        "No prose, no code, no fences.\n\n"
        f"AGENTS:\n{roster}\n\n" + _convo(history)
    )
    for model in (ROUTER_MODEL, ENHANCER_MODEL):
        try:
            obj = _extract_json(_model_content(model, system, message, 200)) or {}
        except Exception:
            obj = {}
        agent = str(obj.get("agent", "")).strip()
        if agent not in profiles:                  # fuzzy match
            cand = [n for n in profiles if n.lower() == agent.lower()]
            agent = cand[0] if cand else ""
        if agent in profiles:
            return {"agent": agent,
                    "intent_summary": str(obj.get("intent_summary") or "").strip(),
                    "domain": str(obj.get("domain") or "").strip()}
    raise ValueError("router could not pick a valid agent")


def enhance_prompt(message: str, profiles: dict, history: list, agent: str,
                   intent: str, domain: str, pinned: dict | None = None) -> str:
    """Tier 2, capable model expands the request into a full brief for the agent."""
    desc = profiles[agent]["soul"][:700]
    system = (
        "You are a prompt engineer. Your job is to take the user's intent and expand it into a "
        f"detailed, specific, actionable prompt for the `{agent}` agent. The agent specializes "
        f"in:\n{desc}\n\n"
        "Write the expanded prompt as if you are briefing a skilled specialist, include every "
        "detail they need to do excellent work, infer reasonable requirements the user didn't "
        "state, name concrete things rather than vague descriptions, handle obvious edge cases, "
        "and structure it clearly. Stay tight to what was asked, do not invent scope or pad "
        "with filler. Output only the expanded prompt, no preamble."
    )
    pinned_block = ""
    if pinned and pinned.get("content"):
        pinned_block = (
            f"ATTACHED CONTEXT, output from a previous '{pinned.get('agent','')}' run the user "
            f"is referring to; fold relevant parts into the brief:\n{pinned['content'][:PINNED_CONTEXT_MAX]}\n\n"
        )
    user = (_convo(history) + pinned_block
            + (f"(intent: {intent}; domain: {domain})\n\n" if intent else "")
            + f"USER REQUEST:\n{message}")
    out = _model_content(ENHANCER_MODEL, system, user, 300)
    return out or message


# --------------------------------------------------------------------------- #
# HTTP handler
# --------------------------------------------------------------------------- #
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, code, body: bytes, ctype="application/json; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj).encode())

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/" or path.startswith("/index.html"):
            if not INDEX.exists():
                return self._send(500, b"index.html missing", "text/plain")
            return self._send(200, INDEX.read_bytes(), "text/html; charset=utf-8")
        if path == "/healthz":
            return self._send(200, b"ok", "text/plain")
        if path == "/agents":
            profs = read_profiles()
            return self._json(200, {"agents": [
                {"name": n, "model": p["model"], "desc": p["desc"]} for n, p in profs.items()
            ]})
        if path == "/pipelines":
            return self._json(200, {"pipelines": list(discover_pipelines().values())})
        if path == "/pipeline-status":
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            snap = pipeline_status_snapshot((qs.get("run_id") or [""])[0])
            if snap is None:
                return self._json(404, {"error": "no such run"})
            return self._json(200, snap)
        if path == "/sessions":
            return self._json(200, {"sessions": list_sessions()})
        if path == "/session":
            qs = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            s = load_session((qs.get("id") or [""])[0])
            if not s:
                return self._json(404, {"error": "no such session"})
            return self._json(200, {"session": s})
        return self._send(404, b"not found", "text/plain")

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        if length < 0 or length > MAX_BODY_BYTES:
            raise ValueError(f"request body too large or invalid: {length}")
        return json.loads(self.rfile.read(length) or b"{}")

    def _open_sse(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()

    def do_POST(self):
        if self.path == "/obsidian-save":
            return self._obsidian_save_endpoint()
        if self.path == "/pin":
            return self._pin_endpoint()
        if self.path == "/sessions":
            return self._create_session_endpoint()
        if self.path == "/delete-session":
            return self._delete_session_endpoint()
        if self.path == "/dispatch":
            return self._dispatch_endpoint()
        if self.path == "/run":
            return self._run_endpoint()
        if self.path == "/run-pipeline":
            return self._run_pipeline_endpoint()
        if self.path == "/resume-pipeline":
            return self._resume_pipeline_endpoint()
        return self._send(404, b"not found", "text/plain")

    def _create_session_endpoint(self):
        try:
            payload = self._read_body()
        except Exception:
            return self._json(400, {"error": "bad request body"})
        stype = payload.get("type", "dispatch")
        if stype not in ("dispatch", "direct", "pipeline"):
            stype = "dispatch"
        agent = payload.get("agent")
        pipeline = None
        if stype == "direct":
            if agent not in read_profiles():
                return self._json(400, {"error": f"unknown agent: {agent}"})
        elif stype == "pipeline":
            agent = None
            pipeline = str(payload.get("pipeline", "")).strip()
            if pipeline not in discover_pipelines():
                return self._json(400, {"error": f"unknown pipeline: {pipeline}"})
        else:
            agent = None
        return self._json(200, {"session": create_session(stype, agent, pipeline)})

    def _delete_session_endpoint(self):
        try:
            payload = self._read_body()
        except Exception:
            return self._json(400, {"error": "bad request body"})
        sid = str(payload.get("session_id", "")).strip()
        if not sid:
            return self._json(400, {"error": "session_id required"})
        ok = delete_session(sid)
        return self._json(200 if ok else 404, {"ok": ok})

    def _run_pipeline_endpoint(self):
        """Start an orchestrated pipeline (e.g. dev-workflow) for a pipeline session. Runs
        bin/run-pipeline.sh as a background worker, streams step progress, surfaces step
        outputs as artifacts, and pauses at the spec-approval gate."""
        try:
            payload = self._read_body()
        except Exception:
            return self._json(400, {"error": "bad request body"})
        session_id = str(payload.get("session_id", "")).strip()
        session = load_session(session_id)
        if session is None:
            return self._json(400, {"error": "valid session_id required"})
        message = str(payload.get("message", "")).strip()
        if not message:
            return self._json(400, {"error": "message is required"})
        pipeline = session.get("pipeline") or str(payload.get("pipeline", "")).strip()
        if pipeline not in discover_pipelines():
            return self._json(400, {"error": f"unknown pipeline: {pipeline}"})
        self._open_sse()
        if not RUN_PIPELINE_SH.exists():
            return self._pump(lambda push: push({"type": "error", "message": "run-pipeline.sh not found"}))
        append_session_turn(session_id, {
            "timestamp": _now(), "user_input": message, "agent_selected": pipeline,
            "domain": "pipeline", "expanded_prompt": "", "agent_response": "",
            "status": "running", "artifact_id": "", "kind": "pipeline-input"})
        self._pump(lambda push: self._pipeline_worker(push, session_id, pipeline, message, None))

    def _resume_pipeline_endpoint(self):
        """Approve the gate and resume a paused pipeline run through to completion."""
        try:
            payload = self._read_body()
        except Exception:
            return self._json(400, {"error": "bad request body"})
        session_id = str(payload.get("session_id", "")).strip()
        session = load_session(session_id)
        if session is None:
            return self._json(400, {"error": "valid session_id required"})
        run_id = str(payload.get("run_id", "") or session.get("pipeline_run_id", "")).strip()
        if not run_id or not (RUN_ROOT / run_id / "state.json").exists():
            return self._json(400, {"error": "valid run_id required"})
        pipeline = session.get("pipeline") or ""
        self._open_sse()
        append_session_turn(session_id, system_turn("✔ Spec approved — building…", True, "pipeline"))
        self._pump(lambda push: self._pipeline_worker(push, session_id, pipeline, None, run_id))

    def _pipeline_worker(self, push, session_id, pipeline, message, run_id):
        """Drive run-pipeline.sh, relay progress, and finalize from state.json. Runs to
        completion even if the client disconnects (the run dir + session persist progress)."""
        resume = run_id is not None
        cmd = (["bash", str(RUN_PIPELINE_SH), "--resume", run_id] if resume
               else ["bash", str(RUN_PIPELINE_SH), pipeline, message])
        set_session_meta(session_id, pipeline_status="running")
        meta = discover_pipelines().get(pipeline, {})
        reported: set = set()
        push({"type": "pipeline-start", "pipeline": pipeline, "resume": resume,
              "run_id": run_id or "", "n_steps": meta.get("n_steps", 0),
              "step_ids": meta.get("steps", [])})
        if run_id:                       # resume: backfill steps already done on a prior pass
            self._emit_step_dones(push, RUN_ROOT / run_id, reported)
        step_re = re.compile(r"→ (\S+): (\S+)")
        tool_re = re.compile(r"⚙ (\S+): (\S+)")
        runid_re = re.compile(r"run (\d\S+?)(?:\s*\[resume\])?\s*$")
        cycle_re = re.compile(r"⟳ (\S+): test cycle (\d+)")
        try:
            # Decode the merged stdout as UTF-8 with errors="replace": the orchestrator emits
            # multibyte progress glyphs (→ ▸ ✓ ⟳), and under launchd the locale's preferred
            # encoding may not be UTF-8 — a strict decode there would kill the whole live stream
            # on the first glyph. errors="replace" keeps the parse alive on any stray byte too.
            proc = subprocess.Popen(cmd, cwd=str(REPO_ROOT), env=dict(os.environ),
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, bufsize=1, encoding="utf-8", errors="replace")
        except Exception as e:
            push({"type": "error", "message": f"failed to start pipeline: {e}"})
            return
        for line in proc.stdout:
            line = line.rstrip("\n")
            if not line:
                continue
            if not run_id:
                m = runid_re.search(line)
                if m:
                    run_id = m.group(1)
                    set_session_meta(session_id, pipeline_run_id=run_id)
                    push({"type": "pipeline-run", "run_id": run_id})
            ms = step_re.search(line) or tool_re.search(line)
            if ms:
                if run_id:               # flush the step that just finished before this one starts
                    self._emit_step_dones(push, RUN_ROOT / run_id, reported)
                append_session_turn(session_id, system_turn(f"▸ {ms.group(1)} ({ms.group(2)})…", True, "pipeline"))
                push({"type": "pipeline-step", "id": ms.group(1), "agent": ms.group(2)})
                continue
            mc = cycle_re.search(line)
            if mc:
                push({"type": "pipeline-cycle", "id": mc.group(1), "cycle": int(mc.group(2))})
                continue
            if "tests GREEN" in line or "gate '" in line:
                push({"type": "pipeline-note", "text": line.strip()})
        try:
            proc.wait(timeout=10)
        except Exception:
            pass
        if run_id:                       # flush the final step(s) before the terminal event
            self._emit_step_dones(push, RUN_ROOT / run_id, reported)
        self._pipeline_finalize(push, session_id, pipeline, run_id)

    def _emit_step_dones(self, push, rd, reported: set) -> None:
        """Push a `pipeline-step-done` (with exit code + one-line output summary) for each
        step in state.json that has finished since the last flush. Idempotent via `reported`,
        so steps are reported exactly once across the run's lifetime."""
        try:
            state = json.loads((rd / "state.json").read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        for st in state.get("steps", []):
            sid, status = st.get("id"), st.get("status")
            if not sid or sid in reported or status not in ("done", "error"):
                continue
            reported.add(sid)
            push({"type": "pipeline-step-done", "id": sid, "agent": st.get("agent", "") or "",
                  "ok": status == "done", "exit_code": st.get("exit_code"),
                  "summary": _step_output_summary(rd, st)})

    def _pipeline_finalize(self, push, session_id, pipeline, run_id):
        rd = RUN_ROOT / (run_id or "")
        try:
            state = json.loads((rd / "state.json").read_text(encoding="utf-8"))
        except Exception:
            state = {}
        status = state.get("status", "error")
        if status == "paused":
            paused = next((s for s in reversed(state.get("steps", []))
                           if s.get("status") in ("paused", "needs-human")), {})
            pid = paused.get("id", "")
            if paused.get("status") == "needs-human":          # validate escalation
                susp = paused.get("suspected_bad_tests", "")
                arts = self._surface_keys(session_id, rd, state,
                                          ["validated", "code", "tests_audited", "tests"], pipeline)
                txt = f"⚠ Validation stuck at '{pid}' — tests still failing after the cycle cap."
                if susp:
                    txt += f" Suspected incorrect test(s): {susp}"
                append_session_turn(session_id, system_turn(txt, False, "pipeline"))
                set_session_meta(session_id, pipeline_status="needs-human")
                push({"type": "pipeline-escalation", "run_id": run_id, "step": pid,
                      "suspected_bad_tests": susp, "artifacts": arts})
            else:                                              # human gate (e.g. spec-approval)
                arts = self._surface_keys(session_id, rd, state, ["plan", "directions", "brief"], pipeline)
                append_session_turn(session_id, system_turn(
                    f"⏸ Spec ready (paused at '{pid}'). Review it, then Approve to build.", True, "pipeline"))
                set_session_meta(session_id, pipeline_status="paused")
                push({"type": "gate", "run_id": run_id, "step": pid, "artifacts": arts})
        elif status == "complete":
            arts = self._surface_keys(session_id, rd, state,
                                      ["validated", "review", "security", "release", "pr"], pipeline)
            append_session_turn(session_id, system_turn("✓ Pipeline complete — validated solution ready.", True, "pipeline"))
            set_session_meta(session_id, pipeline_status="complete")
            push({"type": "pipeline-done", "status": "complete", "run_id": run_id, "artifacts": arts})
        else:
            append_session_turn(session_id, system_turn(f"✗ Pipeline ended: {status}.", False, "pipeline"))
            set_session_meta(session_id, pipeline_status=status)
            push({"type": "pipeline-done", "status": status, "run_id": run_id, "artifacts": []})

    def _surface_keys(self, session_id, rd, state, keys, pipeline):
        """Read produced run keys, persist each as a dispatch artifact + session turn.
        Returns [{key, artifact_id, title}] for keys present in state."""
        out = []
        kmap = state.get("keys", {})
        for key in keys:
            meta = kmap.get(key)
            if not meta:
                continue
            f = rd / meta.get("file", "")
            if not f.exists():
                continue
            try:
                # errors="replace": agent output isn't guaranteed clean UTF-8 (a stray byte
                # would otherwise drop the key silently, surfacing nothing for that step).
                content = f.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            label = f"{pipeline}-{key}"
            art_id = write_artifact(label, content, "", pipeline, uuid.uuid4().hex[:12], session_id) or ""
            append_session_turn(session_id, {
                "timestamp": _now(), "user_input": "", "agent_selected": label,
                "domain": "pipeline", "expanded_prompt": "", "agent_response": content,
                "status": "ok", "artifact_id": art_id, "kind": "pipeline-output", "pipeline_key": key})
            out.append({"key": key, "artifact_id": art_id, "title": label})
        return out

    def _obsidian_save_endpoint(self):
        """Manual 'Save to Obsidian' button, save a specific artifact by id."""
        try:
            payload = self._read_body()
        except Exception:
            return self._json(400, {"error": "bad request body"})
        art_id = str(payload.get("artifact_id", "")).strip()
        sid = str(payload.get("session_id", "")).strip()
        if not art_id:
            return self._json(400, {"error": "artifact_id required"})
        try:
            path = resolve_artifact(art_id)
        except Exception as e:
            return self._json(404, {"error": f"artifact not found: {e}"})
        agent = ""
        try:
            agent = json.loads(path.with_name(path.stem + ".meta.json").read_text()).get("agent", "")
        except Exception:
            pass
        try:
            result = obsidian_save(path.read_text(), agent)
        except Exception as e:
            result = {"ok": False, "error": f"save failed: {e}"}
        text, ok = obsidian_system_text(result)
        if sid and load_session(sid) is not None:    # persist system message to the session
            append_session_turn(sid, system_turn(text, ok))
        result["system_text"] = text
        return self._json(200 if result.get("ok") else 500, result)

    def _pin_endpoint(self):
        """Set or clear the pinned context artifact for a session (survives reloads)."""
        try:
            payload = self._read_body()
        except Exception:
            return self._json(400, {"error": "bad request body"})
        sid = str(payload.get("session_id", "")).strip()
        if not sid or load_session(sid) is None:
            return self._json(400, {"error": "valid session_id required"})
        art_id = str(payload.get("artifact_id", "")).strip()
        if not art_id:
            set_session_pin(sid, None)
            return self._json(200, {"ok": True, "pinned": None})
        try:
            p = resolve_artifact(art_id)
        except Exception as e:
            return self._json(404, {"error": f"artifact not found: {e}"})
        agent, ts = "", ""
        try:
            m = json.loads(p.with_name(p.stem + ".meta.json").read_text())
            agent, ts = m.get("agent", ""), m.get("timestamp", "")
        except Exception:
            pass
        obj = {"artifact_id": art_id, "agent": agent, "time": ts}
        set_session_pin(sid, obj)
        return self._json(200, {"ok": True, "pinned": obj})

    def _emit(self, obj) -> bool:
        return self._write_raw(f"data: {json.dumps(obj)}\n\n")

    def _write_raw(self, s: str) -> bool:
        try:
            self.wfile.write(s.encode())
            self.wfile.flush()
            return True
        except (BrokenPipeError, ConnectionResetError, OSError):
            return False

    def _pump(self, worker):
        """Run worker(push) in a thread and relay pushed SSE events to the client,
        with 10s heartbeats so idle phases don't trip timeouts. The worker owns
        persistence and runs to completion even if the client disconnects."""
        events: "queue.Queue" = queue.Queue()

        def run():
            try:
                worker(events.put)
            except Exception as e:           # never lose the connection silently
                events.put({"type": "error", "message": f"internal: {e}"})
            finally:
                events.put(None)

        threading.Thread(target=run, daemon=True).start()
        alive = True
        while True:
            try:
                ev = events.get(timeout=10)
            except queue.Empty:
                if alive and not self._write_raw(": hb\n\n"):
                    alive = False
                continue
            if ev is None:
                break
            if alive and not self._emit(ev):
                alive = False

    def _resolve_pinned(self, pinned_id: str):
        if not pinned_id:
            return None
        try:
            p = resolve_artifact(pinned_id)
            agent = ""
            try:
                agent = json.loads(p.with_name(p.stem + ".meta.json").read_text()).get("agent", "")
            except Exception:
                pass
            return {"content": p.read_text(), "agent": agent, "artifact_id": pinned_id}
        except Exception:
            return None

    def _dispatch_endpoint(self):
        """Tier 1 (router) + Tier 2 (enhancer). Emits a `dispatched` event carrying the
        chosen agent + expanded prompt; the client then calls /run (optionally edited).
        Direct sessions skip both tiers and pass the message through verbatim."""
        try:
            payload = self._read_body()
        except Exception:
            return self._json(400, {"error": "bad request body"})
        message = str(payload.get("message", "")).strip()
        session_id = str(payload.get("session_id", "")).strip()
        if not message:
            return self._json(400, {"error": "message is required"})
        session = load_session(session_id)
        if session is None:
            return self._json(400, {"error": "valid session_id required"})
        pinned_id = str(payload.get("pinned_artifact_id", "")).strip()
        self._open_sse()

        profiles = read_profiles()
        if not litellm_key():
            return self._pump(lambda push: push({"type": "error", "message": "LITELLM_MASTER_KEY not found"}))
        direct = session.get("type") == "direct"

        # Obsidian save is a side-action, detected BEFORE routing (dispatch sessions only).
        if not direct and is_obsidian_intent(message):
            recent = most_recent_artifact_in(session.get("turns", []))
            if recent:
                return self._pump(lambda push: self._obsidian_worker(push, session_id, message, recent))

        pinned = self._resolve_pinned(pinned_id)
        prior = list(session.get("turns", []))   # captured BEFORE persisting this turn
        idx = append_session_turn(session_id, {
            "timestamp": _now(), "user_input": message, "dispatcher_reasoning": "",
            "agent_selected": "", "domain": "", "expanded_prompt": "", "agent_response": "",
            "status": "pending", "artifact_id": "",
            "pinned_artifact_id": (pinned or {}).get("artifact_id", ""),
            "pinned_agent": (pinned or {}).get("agent", ""),
        })

        def worker(push):
            try:
                if direct:
                    agent = session.get("agent", "")
                    if agent not in profiles:
                        update_session_turn(session_id, idx, status="error", error=f"unknown agent '{agent}'")
                        return push({"type": "error", "message": f"unknown agent '{agent}'"})
                    intent, domain, expanded = "", "", message
                else:
                    r = route_request(message, profiles, prior)                       # Tier 1
                    agent, intent, domain = r["agent"], r["intent_summary"], r["domain"]
                    expanded = enhance_prompt(message, profiles, prior, agent,         # Tier 2
                                              intent, domain, pinned)
                update_session_turn(session_id, idx, agent_selected=agent,
                                    dispatcher_reasoning=intent, domain=domain, expanded_prompt=expanded)
                push({"type": "dispatched", "turn_idx": idx, "agent": agent,
                      "model": profiles[agent]["model"], "intent_summary": intent,
                      "domain": domain, "expanded_prompt": expanded, "direct": direct})
            except Exception as e:
                update_session_turn(session_id, idx, status="error", error=str(e))
                push({"type": "error", "message": str(e)})

        self._pump(worker)

    def _run_endpoint(self):
        """Tier 3, stream the target agent for a dispatched turn (with the possibly
        user-edited expanded prompt)."""
        try:
            payload = self._read_body()
        except Exception:
            return self._json(400, {"error": "bad request body"})
        session_id = str(payload.get("session_id", "")).strip()
        session = load_session(session_id)
        if session is None:
            return self._json(400, {"error": "valid session_id required"})
        try:
            idx = int(payload.get("turn_idx"))
        except (TypeError, ValueError):
            return self._json(400, {"error": "turn_idx required"})
        turns = session.get("turns", [])
        if not (0 <= idx < len(turns)):
            return self._json(400, {"error": "bad turn_idx"})
        turn = turns[idx]
        edited = bool(payload.get("edited"))
        expanded = str(payload.get("expanded_prompt") or turn.get("expanded_prompt")
                       or turn.get("user_input") or "")
        agent = turn.get("agent_selected", "")
        pinned = self._resolve_pinned(turn.get("pinned_artifact_id", ""))
        self._open_sse()

        profiles = read_profiles()
        if agent not in profiles:
            return self._pump(lambda push: push({"type": "error", "message": f"unknown agent '{agent}'"}))
        prof = profiles[agent]
        if edited:
            update_session_turn(session_id, idx, expanded_prompt=expanded, edited=True)

        def worker(push):
            collected, upstream = [], None
            started = time.time()
            try:
                user_content = expanded
                if pinned and pinned.get("content"):   # attach pinned artifact for the agent
                    user_content = (
                        f"===== ATTACHED CONTEXT (output from a previous "
                        f"{pinned.get('agent','')} run) =====\n{pinned['content']}\n\n"
                        f"===== REQUEST =====\n{expanded}"
                    )
                upstream = _post(prof["model"],
                                 [{"role": "system", "content": prof["soul"]},
                                  {"role": "user", "content": user_content}],
                                 stream=True, timeout=900)
                tf = ThinkFilter(); buf = b""; last_save = time.time()
                for raw in upstream:
                    buf += raw
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        s = line.decode("utf-8", "replace").strip()
                        if not s.startswith("data:"):
                            continue
                        d = s[5:].strip()
                        if d == "[DONE]":
                            continue
                        try:
                            j = json.loads(d)
                        except ValueError:
                            continue
                        delta = (j.get("choices", [{}])[0].get("delta", {})) or {}
                        piece = delta.get("content")        # answer channel only
                        if not piece:                        # ignore reasoning_content
                            continue
                        clean = tf.feed(piece)
                        if clean:
                            collected.append(clean)
                            push({"type": "token", "content": clean})
                            if time.time() - last_save > 2:  # checkpoint partial output
                                update_session_turn(session_id, idx, agent_response="".join(collected))
                                last_save = time.time()
                final = "".join(collected).strip()
                art_id = write_artifact(agent, final, expanded, prof["model"],
                                        uuid.uuid4().hex[:12], session_id)
                record_hermes_session(agent, prof["model"], prof["soul"], user_content,
                                      final, started, time.time())
                update_session_turn(session_id, idx, status="ok", agent_response=final,
                                    artifact_id=art_id or "")
                push({"type": "done", "artifact_id": art_id or "", "agent": agent, "edited": edited})
            except urllib.error.HTTPError as e:
                msg = f"HTTP {e.code}: {e.read()[:200].decode('utf-8', 'replace')}"
                update_session_turn(session_id, idx, status="error", error=msg,
                                    agent_response="".join(collected).strip())
                push({"type": "error", "message": msg})
            except Exception as e:
                update_session_turn(session_id, idx, status="error", error=str(e),
                                    agent_response="".join(collected).strip())
                push({"type": "error", "message": str(e)})
            finally:
                if upstream is not None:
                    try: upstream.close()
                    except Exception: pass

        self._pump(worker)

    def _obsidian_worker(self, push, session_id: str, message: str, recent: dict):
        """Save the most recent artifact in this session to the vault (intent action)."""
        append_session_turn(session_id, {   # the triggering user message
            "timestamp": _now(), "user_input": message, "agent_selected": "",
            "dispatcher_reasoning": "", "expanded_prompt": "", "artifact_id": "",
            "agent_response": "", "status": "ok"})
        push({"type": "action", "name": "obsidian-save", "status": "saving"})
        try:
            content = resolve_artifact(recent["artifact_id"]).read_text()
            result = obsidian_save(content, recent.get("agent", ""))
        except Exception as e:
            result = {"ok": False, "error": str(e)}
        text, ok = obsidian_system_text(result)
        append_session_turn(session_id, system_turn(text, ok))   # persistent system message
        push({"type": "system", "text": text, "ok": ok})         # render it live
        push({"type": "done"})


def main():
    DISPATCH_HOME.mkdir(parents=True, exist_ok=True)
    migrate_legacy_history()
    recover_orphaned_pipelines()
    if not INDEX.exists():
        print(f"warning: {INDEX} not found", file=sys.stderr)
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Hermes Dispatch on http://{HOST}:{PORT}")
    print(f"  profiles: {PROFILES_DIR}  ({len(read_profiles())} agents)")
    print(f"  router: {ROUTER_MODEL}  enhancer: {ENHANCER_MODEL}   key: {'found' if litellm_key() else 'MISSING'}")
    print(f"  sessions: {SESSIONS_DIR}  ({len(list_sessions())} sessions)")
    print(f"  artifacts: {ARTIFACTS_ROOT}")
    print(f"  obsidian: {'enabled at ' + str(VAULT) if OBSIDIAN_ENABLED else 'disabled (set OBSIDIAN_VAULT)'}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
