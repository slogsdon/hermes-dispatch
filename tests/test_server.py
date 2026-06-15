#!/usr/bin/env python3
"""Tests for dispatch/server.py — the bits with real blast radius, isolated from live state.

Covered:
  - resolve_artifact()    : the path-traversal guard on the artifact store
  - write_artifact()      : roundtrips through resolve_artifact
  - session turn helpers  : append/update/load, incl. the out-of-range idx no-op (S8 surface)
  - Handler._read_body()  : the QW4 body-size cap (oversized / negative rejected)

server.py computes its paths from env at import time and has no import-time side effects
(dir creation + socket bind live inside functions / __main__), so we point HERMES_DISPATCH_HOME
and HERMES_ARTIFACTS_DIR at throwaway temp dirs BEFORE importing it.
"""
import atexit
import importlib.util
import io
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

# --- Point the server at throwaway state BEFORE import ---------------------------------------
_TMP = tempfile.mkdtemp(prefix="hermes_server_test_")
atexit.register(lambda: shutil.rmtree(_TMP, ignore_errors=True))
os.environ["HERMES_DISPATCH_HOME"] = os.path.join(_TMP, "dispatch")
os.environ["HERMES_ARTIFACTS_DIR"] = os.path.join(_TMP, "artifacts")
os.environ["HERMES_HOME"] = os.path.join(_TMP, "hermes")

REPO_ROOT = Path(__file__).resolve().parent.parent
SERVER_PY = REPO_ROOT / "dispatch" / "server.py"
_spec = importlib.util.spec_from_file_location("hermes_server", SERVER_PY)
srv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(srv)


class TestResolveArtifact(unittest.TestCase):
    def test_valid_roundtrip(self):
        aid = srv.write_artifact("pr-reviewer", "# verdict\nlgtm\n", "prompt", "max", "rid", "cid")
        self.assertIsNotNone(aid)
        p = srv.resolve_artifact(aid)
        self.assertTrue(p.is_file())
        self.assertTrue(str(p).startswith(str(srv.ARTIFACTS_ROOT.resolve())))

    def test_rejects_traversal(self):
        with self.assertRaises(ValueError):
            srv.resolve_artifact("../../../etc/passwd")

    def test_rejects_absolute_escape(self):
        with self.assertRaises(ValueError):
            srv.resolve_artifact("/etc/passwd")

    def test_missing_file_raises(self):
        with self.assertRaises(FileNotFoundError):
            srv.resolve_artifact("2026-01-01/nope.md")

    def test_empty_content_returns_none(self):
        self.assertIsNone(srv.write_artifact("a", "   \n ", "p", "m", "r", "c"))


class TestSessionTurns(unittest.TestCase):
    def test_append_returns_sequential_idx(self):
        s = srv.create_session("dispatch")
        i0 = srv.append_session_turn(s["id"], {"user_input": "first", "status": "pending"})
        i1 = srv.append_session_turn(s["id"], {"user_input": "second", "status": "pending"})
        self.assertEqual((i0, i1), (0, 1))

    def test_title_set_from_first_turn(self):
        s = srv.create_session("dispatch")
        srv.append_session_turn(s["id"], {"user_input": "Launch the Acme deal next week"})
        self.assertEqual(srv.load_session(s["id"])["title"], "Launch the Acme deal next week")

    def test_update_writes_correct_turn(self):
        s = srv.create_session("dispatch")
        srv.append_session_turn(s["id"], {"user_input": "a"})
        srv.append_session_turn(s["id"], {"user_input": "b"})
        srv.update_session_turn(s["id"], 1, status="ok", agent_response="done")
        turns = srv.load_session(s["id"])["turns"]
        self.assertEqual(turns[1]["status"], "ok")
        self.assertNotIn("status", turns[0])  # turn 0 untouched

    def test_update_out_of_range_is_noop(self):
        s = srv.create_session("dispatch")
        srv.append_session_turn(s["id"], {"user_input": "a"})
        srv.update_session_turn(s["id"], 5, status="ok")   # must not raise or grow
        self.assertEqual(len(srv.load_session(s["id"])["turns"]), 1)

    def test_append_to_missing_session_returns_none(self):
        self.assertIsNone(srv.append_session_turn("no_such_session", {"user_input": "x"}))


class TestReadBodyCap(unittest.TestCase):
    """QW4: _read_body must reject oversized / negative Content-Length before reading."""

    def _call(self, length: int, body: bytes = b"{}"):
        fake = SimpleNamespace(
            headers={"Content-Length": str(length)},
            rfile=io.BytesIO(body),
        )
        return srv.Handler._read_body(fake)

    def test_rejects_oversized(self):
        with self.assertRaises(ValueError):
            self._call(srv.MAX_BODY_BYTES + 1)

    def test_rejects_negative(self):
        with self.assertRaises(ValueError):
            self._call(-1)

    def test_accepts_small_body(self):
        self.assertEqual(self._call(12, b'{"ok": true}'), {"ok": True})

    def test_empty_body_is_empty_dict(self):
        self.assertEqual(self._call(0, b""), {})


if __name__ == "__main__":
    unittest.main(verbosity=2)
