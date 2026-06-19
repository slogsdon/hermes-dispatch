#!/usr/bin/env python3
"""
swarm.py — parallel fan-out over the swarm-worker agent (qwen2.5-coder:1.5b, the `swarm`
LiteLLM alias). Manages parallelized coding grunt-work: annotation passes, doc/test stubs,
and any batch of independent one-shot code transforms.

WHY THIS LIVES HERE (not as a pipelines/*.json definition)
----------------------------------------------------------
The repo's linear pipeline runner (bin/run-pipeline.sh + lib/orchestrate.sh) threads ONE
named key from step to step over a file-based state store, and runs steps SEQUENTIALLY —
its step types are agent / gate / tool / test-loop, none of which fan a *list* of inputs
out to many concurrent workers. The swarm pipelines take a list and fan it out N-wide, so
they can't be expressed in that model. This handler implements the fan-out directly with a
ThreadPoolExecutor (the workers are independent subprocesses → threads suffice; the GIL is
released across the subprocess call), mirroring the project's "agents stay pure stdin→stdout
shell wrappers, the orchestration layer owns concurrency" split — just with parallelism the
linear runner lacks.

THREE PIPELINES (subcommands)
-----------------------------
  fanout       Generic. JSON list of {id, instruction, code} → [{id, result, tokens_used}].
  annotate     Type-annotation pass. code + language (python|typescript|php): split into
               per-function units, fan each out, return the annotated functions.
  test-stubs   Test skeletons. code + framework (jest|pytest|phpunit): split into per-function
               units, fan each out, return the test stubs.

annotate / test-stubs split the input into per-function units (see the splitters below) and
fan each unit out as its own swarm-worker task. If a body can't be split, the whole input is
sent as a single unit so the pipeline always produces output.

USAGE
-----
  echo '{"tasks":[{"id":"fn1","instruction":"Add JSDoc","code":"function f(x){return x*2}"}]}' \
    | bin/swarm.py fanout
  bin/swarm.py fanout --file tasks.json

  bin/swarm.py annotate --lang python     --file mod.py
  bin/swarm.py annotate --lang typescript < code.ts

  bin/swarm.py test-stubs --framework pytest  --file mod.py
  bin/swarm.py test-stubs --framework jest   < code.ts

OUTPUT
------
JSON to stdout: a list of {id, result, tokens_used}, in input order. `tokens_used` is an
ESTIMATE (~len(result)/4): the hermes CLI emits only text on stdout and surfaces no usage
counts, so an exact token tally isn't available from this layer.

ENV
---
  SWARM_MAX_WORKERS   concurrency cap (default 8)
  SWARM_TIMEOUT       per-worker timeout in seconds (default 180)
  HERMES_DRY_RUN=1    swarm-worker prints its composed hermes command instead of calling a model
                      (use to verify plumbing/concurrency with no GPU/RAM cost)
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKER = REPO_ROOT / "agents" / "swarm-worker" / "run.sh"

DEFAULT_WORKERS = int(os.environ.get("SWARM_MAX_WORKERS", "8"))
DEFAULT_TIMEOUT = int(os.environ.get("SWARM_TIMEOUT", "180"))

# Prompt templates (verbatim per the spec). language/framework → instruction.
ANNOTATE_PROMPTS = {
    "python": "Add type annotations to all parameters and return value. "
              "Return the function with annotations only.",
    "typescript": "Add TypeScript type annotations to all parameters and return type. "
                  "Return the typed function only.",
    "php": "Add PHP 8.2+ type declarations to all parameters and return type. "
           "Return the function only.",
}
TEST_STUB_PROMPTS = {
    "jest": "Write 3 Jest unit tests for this function. Tests only, no imports, no describe block.",
    "pytest": "Write 3 pytest test functions for this function. "
              "Tests only, no imports, no fixtures.",
    "phpunit": "Write 3 PHPUnit test methods for this function. "
               "Test methods only, no class wrapper.",
}
# A test framework implies the language to split with.
FRAMEWORK_LANG = {"jest": "typescript", "pytest": "python", "phpunit": "php"}


# ── worker + fan-out engine ──────────────────────────────────────────────────

def estimate_tokens(text: str) -> int:
    """Rough token estimate (~4 chars/token). The hermes CLI gives no usage counts."""
    return math.ceil(len(text) / 4) if text else 0


def run_worker(task: dict) -> dict:
    """Run one swarm-worker subprocess. task {id, instruction, code} → {id, result, tokens_used}."""
    tid = str(task.get("id", "?"))
    instruction = (task.get("instruction") or "").strip()
    code = task.get("code") or ""
    payload = f"{instruction}\n\n{code}" if code else instruction
    try:
        proc = subprocess.run(
            [str(WORKER)],
            input=payload,
            capture_output=True,
            timeout=DEFAULT_TIMEOUT,
            encoding="utf-8",
            errors="replace",  # worker stdout may carry stray non-UTF-8 bytes; don't crash batch
        )
        result = (proc.stdout or "").strip()
        if proc.returncode != 0 and not result:
            err = (proc.stderr or "").strip()[:300]
            result = f"[swarm-worker error: exit {proc.returncode}] {err}"
    except subprocess.TimeoutExpired:
        result = f"[swarm-worker timeout after {DEFAULT_TIMEOUT}s]"
    except Exception as exc:  # never let one worker take down the batch
        result = f"[swarm-worker exception] {exc}"
    return {"id": tid, "result": result, "tokens_used": estimate_tokens(result)}


def fanout(tasks: list[dict], max_workers: int = DEFAULT_WORKERS) -> list[dict]:
    """Fan tasks out to concurrent swarm-worker subprocesses; return results in input order."""
    if not tasks:
        return []
    results: list[dict | None] = [None] * len(tasks)
    workers = max(1, min(max_workers, len(tasks)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(run_worker, t): i for i, t in enumerate(tasks)}
        for fut in concurrent.futures.as_completed(futures):
            results[futures[fut]] = fut.result()
    return [r for r in results if r is not None]


# ── per-function splitters ───────────────────────────────────────────────────
# Pragmatic, dependency-free splitters: good enough to chop a file into grunt-sized units.
# They are heuristic (regex + brace/indent matching, not a real parser) — braces inside
# strings/comments can fool the brace matcher. When a splitter finds nothing, the caller
# falls back to treating the whole input as one unit, so output is always produced.

def split_python(src: str) -> list[tuple[str, str]]:
    """Split Python source into (name, block) units by `def`, using indentation to bound bodies."""
    lines = src.splitlines(keepends=True)
    pat = re.compile(r"^(\s*)(?:async\s+)?def\s+(\w+)")
    funcs: list[tuple[str, str]] = []
    i, n = 0, len(lines)
    while i < n:
        m = pat.match(lines[i])
        if not m:
            i += 1
            continue
        indent, name, start = len(m.group(1)), m.group(2), i
        i += 1
        while i < n:  # consume the body: blank lines, or lines indented deeper than the def
            stripped = lines[i].strip()
            if stripped == "":
                i += 1
                continue
            cur_indent = len(lines[i]) - len(lines[i].lstrip())
            if cur_indent <= indent:
                break
            i += 1
        funcs.append((name, "".join(lines[start:i]).rstrip("\n")))
    return funcs


def _brace_blocks(src: str, sig_pat: re.Pattern) -> list[tuple[str, str]]:
    """Split brace-delimited languages (TS/PHP): a signature match, then `{`…`}` brace-match."""
    funcs: list[tuple[str, str]] = []
    for m in sig_pat.finditer(src):
        name = next((g for g in m.groups() if g), "fn")
        brace = src.find("{", m.end() - 1)
        if brace == -1:  # arrow single-expression / abstract method: take to end of line
            end = src.find("\n", m.end())
            funcs.append((name, src[m.start(): end if end != -1 else len(src)].strip()))
            continue
        depth, i, end = 0, brace, len(src)
        while i < len(src):
            c = src[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
            i += 1
        funcs.append((name, src[m.start():end].strip()))
    return funcs


TS_SIG = re.compile(
    r"(?m)^[ \t]*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+(\w+)\s*\("
    r"|(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\([^)]*\)\s*(?::\s*[\w<>\[\],\s|]+)?=>"
)
PHP_SIG = re.compile(
    r"(?m)^[ \t]*(?:(?:public|private|protected|static|final|abstract)\s+)*function\s+(\w+)\s*\("
)


def split_typescript(src: str) -> list[tuple[str, str]]:
    return _brace_blocks(src, TS_SIG)


def split_php(src: str) -> list[tuple[str, str]]:
    return _brace_blocks(src, PHP_SIG)


SPLITTERS = {"python": split_python, "typescript": split_typescript, "php": split_php}


def split_units(code: str, language: str) -> list[tuple[str, str]]:
    """Split into (id, block) units; fall back to a single unit when nothing matches."""
    units = SPLITTERS[language](code)
    if not units:
        return [("unit-1", code.strip())]
    # de-duplicate ids (overloads / repeated names) so every result is addressable
    seen: dict[str, int] = {}
    out: list[tuple[str, str]] = []
    for name, block in units:
        seen[name] = seen.get(name, 0) + 1
        out.append((name if seen[name] == 1 else f"{name}-{seen[name]}", block))
    return out


# ── input helpers ────────────────────────────────────────────────────────────

def read_code(args) -> str:
    if getattr(args, "file", None):
        return Path(args.file).read_text()
    if not sys.stdin.isatty():
        return sys.stdin.read()
    sys.exit("swarm: no code (pass --file or pipe via stdin)")


def emit(results: list[dict]) -> None:
    json.dump(results, sys.stdout, indent=2)
    sys.stdout.write("\n")


# ── subcommands ──────────────────────────────────────────────────────────────

def cmd_fanout(args) -> None:
    raw = Path(args.file).read_text() if args.file else (
        sys.stdin.read() if not sys.stdin.isatty() else "")
    if not raw.strip():
        sys.exit("swarm fanout: no input (pass --file or pipe a JSON object on stdin)")
    data = json.loads(raw)
    tasks = data["tasks"] if isinstance(data, dict) else data
    if not isinstance(tasks, list):
        sys.exit('swarm fanout: expected {"tasks": [...]} or a JSON list of tasks')
    for j, t in enumerate(tasks):  # default an id so every result is addressable
        t.setdefault("id", f"task-{j + 1}")
    emit(fanout(tasks, args.workers))


def cmd_annotate(args) -> None:
    instruction = ANNOTATE_PROMPTS[args.lang]
    units = split_units(read_code(args), args.lang)
    tasks = [{"id": uid, "instruction": instruction, "code": block} for uid, block in units]
    emit(fanout(tasks, args.workers))


def cmd_test_stubs(args) -> None:
    instruction = TEST_STUB_PROMPTS[args.framework]
    language = FRAMEWORK_LANG[args.framework]
    units = split_units(read_code(args), language)
    tasks = [{"id": uid, "instruction": instruction, "code": block} for uid, block in units]
    emit(fanout(tasks, args.workers))


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="swarm.py", description="Parallel fan-out over the swarm-worker agent.")
    p.add_argument("--workers", type=int, default=DEFAULT_WORKERS,
                   help=f"max concurrent workers (default {DEFAULT_WORKERS})")
    sub = p.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fanout", help="generic fan-out over a JSON task list")
    f.add_argument("--file", help="read the tasks JSON from a file instead of stdin")
    f.set_defaults(func=cmd_fanout)

    a = sub.add_parser("annotate", help="type-annotation pass, one worker per function")
    a.add_argument("--lang", required=True, choices=sorted(ANNOTATE_PROMPTS))
    a.add_argument("--file", help="read code from a file instead of stdin")
    a.set_defaults(func=cmd_annotate)

    t = sub.add_parser("test-stubs", help="test-skeleton generation, one worker per function")
    t.add_argument("--framework", required=True, choices=sorted(TEST_STUB_PROMPTS))
    t.add_argument("--file", help="read code from a file instead of stdin")
    t.set_defaults(func=cmd_test_stubs)
    return p


def main() -> None:
    if not WORKER.exists():
        sys.exit(f"swarm: missing worker agent at {WORKER}")
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
