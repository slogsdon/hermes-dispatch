#!/usr/bin/env python3
"""Tests for lib/extract_files.py — the model-output → real-files parser + path containment.

Covers the two halves that have real blast radius:
  1. parse()       — does it pull the right (path, content) pairs from messy model markdown?
  2. safe_join()   — does it actually keep writes inside the workspace, incl. symlink escape?

Plus one end-to-end subprocess test that reproduces the symlink-escape scenario and asserts
nothing is written outside the workspace (the regression guard for the QW2 hardening).

Run: python3 -m unittest tests.test_extract_files   (or: python3 tests/test_extract_files.py)
No third-party deps.
"""
import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
EXTRACT_PY = REPO_ROOT / "lib" / "extract_files.py"

# Import the script as a module without running main().
_spec = importlib.util.spec_from_file_location("extract_files", EXTRACT_PY)
ef = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ef)


class TestCandidatePath(unittest.TestCase):
    def test_accepts_slash_path(self):
        self.assertEqual(ef.candidate_path("### `src/app.py`"), "src/app.py")

    def test_accepts_heading_without_backticks(self):
        self.assertEqual(ef.candidate_path("### src/app.py"), "src/app.py")

    def test_accepts_bold_path(self):
        self.assertEqual(ef.candidate_path("**lib/util.ts**"), "lib/util.ts")

    def test_accepts_lone_backtick_path(self):
        self.assertEqual(ef.candidate_path("`main.go`"), "main.go")

    def test_accepts_bare_filename_with_extension(self):
        self.assertEqual(ef.candidate_path("### `Makefile.am`"), "Makefile.am")

    def test_rejects_prose(self):
        self.assertIsNone(ef.candidate_path("Here is the implementation:"))

    def test_rejects_path_with_spaces(self):
        self.assertIsNone(ef.candidate_path("### `src/my file.py`"))

    def test_rejects_plain_word_without_slash_or_ext(self):
        self.assertIsNone(ef.candidate_path("### Overview"))

    def test_rejects_unwrapped_lone_line(self):
        # A lone line that isn't backtick/bold-wrapped must not match (prose protection).
        self.assertIsNone(ef.candidate_path("src/app.py"))


class TestParse(unittest.TestCase):
    def test_single_file_backtick_fence(self):
        text = "### `a.py`\n```python\nprint(1)\n```\n"
        self.assertEqual(list(ef.parse(text)), [("a.py", "print(1)\n")])

    def test_tilde_fence(self):
        text = "### `a.py`\n~~~\nx=1\n~~~\n"
        self.assertEqual(list(ef.parse(text)), [("a.py", "x=1\n")])

    def test_multiple_files_in_order(self):
        text = (
            "### `a.py`\n```\nA\n```\n\n"
            "### `dir/b.py`\n```\nB\n```\n"
        )
        self.assertEqual(list(ef.parse(text)), [("a.py", "A\n"), ("dir/b.py", "B\n")])

    def test_prose_between_heading_and_fence_clears_path(self):
        # The fence must NOT misattach to the earlier heading once prose intervenes.
        text = "### `a.py`\nsome explanation here\n```\nORPHAN\n```\n"
        self.assertEqual(list(ef.parse(text)), [])

    def test_empty_block(self):
        text = "### `empty.txt`\n```\n```\n"
        self.assertEqual(list(ef.parse(text)), [("empty.txt", "")])


class TestSafeJoin(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.dest = os.path.join(self.tmp, "ws")
        os.makedirs(self.dest)

    def test_normal_nested_path(self):
        got = ef.safe_join(self.dest, "pkg/mod.py")
        self.assertEqual(got, os.path.join(os.path.realpath(self.dest), "pkg/mod.py"))

    def test_rejects_absolute(self):
        self.assertIsNone(ef.safe_join(self.dest, "/etc/passwd"))

    def test_rejects_parent_traversal(self):
        self.assertIsNone(ef.safe_join(self.dest, "../escape.py"))

    def test_rejects_bare_dotdot(self):
        self.assertIsNone(ef.safe_join(self.dest, ".."))

    def test_rejects_midpath_traversal(self):
        self.assertIsNone(ef.safe_join(self.dest, "a/../../x.py"))

    def test_rejects_symlinked_parent_escape(self):
        # A symlink already inside the workspace pointing outside must not be a write path.
        outside = os.path.join(self.tmp, "victim")
        os.makedirs(outside)
        os.symlink(outside, os.path.join(self.dest, "link"))
        self.assertIsNone(ef.safe_join(self.dest, "link/evil.py"))


class TestEndToEndContainment(unittest.TestCase):
    """Regression guard for QW2: run the actual script and prove nothing escapes the workspace."""

    def test_symlink_and_traversal_blocked_via_cli(self):
        tmp = tempfile.mkdtemp()
        ws = os.path.join(tmp, "ws")
        victim = os.path.join(tmp, "victim")
        os.makedirs(ws)
        os.makedirs(victim)
        os.symlink(victim, os.path.join(ws, "link"))
        md = os.path.join(tmp, "in.md")
        Path(md).write_text(
            "### `ok/app.py`\n```\nhi\n```\n\n"
            "### `link/escape.py`\n```\nescaped\n```\n\n"
            "### `../outside.py`\n```\nnope\n```\n"
        )
        out = subprocess.run(
            [sys.executable, str(EXTRACT_PY), ws, md],
            capture_output=True, text=True,
        )
        # Exactly one legitimate file written.
        self.assertEqual(out.stdout.strip(), "1")
        self.assertTrue(os.path.isfile(os.path.join(ws, "ok/app.py")))
        # Nothing escaped: victim stays empty, no sibling file created.
        self.assertEqual(os.listdir(victim), [])
        self.assertFalse(os.path.exists(os.path.join(tmp, "outside.py")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
