#!/usr/bin/env python3
"""extract_files.py — materialize an agent's code output into real files on disk.

code-generator and test-designer emit Markdown with one section per file:

    ### `relative/path/to/file.ext`
    ```lang
    <complete file contents>
    ```

This script parses that shape and writes each block to <dest>/<path>, so the
deterministic test-runner can actually run the generated code. The agents stay
pure stdin→stdout; THIS is the bridge from "model wrote code" to "code on disk".

Usage:
    extract_files.py <dest-dir> [src.md]        # src.md, or stdin if omitted
Prints one line per file written to stderr and the count to stdout.

Safety: paths are constrained to <dest-dir>; any block whose resolved path would
escape the destination — absolute paths, ../ traversal, OR a symlinked parent/leaf
(realpath-checked, written with O_NOFOLLOW) — is skipped with a warning. Does not
write outside <dest-dir>.
"""
import os
import re
import sys

# A file path can be announced as an h2–h4 heading (``### `path` `` OR `### path`, with or
# without backticks/bold — models are inconsistent) or as a lone backticked/bold line
# (`` `src/x.py` `` / `**path**`), immediately followed by a fenced block.
HEADING_RE = re.compile(r'^\s{0,3}#{2,4}\s+(.+?)\s*$')
FENCE_RE = re.compile(r'^\s{0,3}(`{3,}|~{3,})')


def candidate_path(line):
    """Return a file path if this line announces one, else None. Tolerant of headings with
    or without surrounding backticks/asterisks; lone lines must be backtick/bold-wrapped so
    prose words don't match. A path has no spaces and either a slash or a file extension."""
    m = HEADING_RE.match(line)
    if m:
        cand = m.group(1)
    else:
        s = line.strip()
        if not (s.startswith('`') or s.startswith('*')):
            return None
        cand = s
    cand = cand.strip().strip('*').strip().strip('`').strip().strip('*').strip()
    if not cand or ' ' in cand:
        return None
    if '/' in cand or re.search(r'\.\w{1,12}$', cand):
        return cand
    return None


def parse(text):
    """Yield (path, content) pairs in document order."""
    lines = text.splitlines()
    i, n = 0, len(lines)
    pending_path = None
    while i < n:
        line = lines[i]
        cand = candidate_path(line)
        if cand:
            pending_path = cand
            i += 1
            continue
        fm = FENCE_RE.match(line)
        if fm and pending_path:
            fence = fm.group(1)[0]  # ` or ~
            i += 1
            buf = []
            while i < n and not re.match(r'^\s{0,3}' + re.escape(fence) + r'{3,}\s*$', lines[i]):
                buf.append(lines[i])
                i += 1
            i += 1  # consume closing fence
            yield pending_path, '\n'.join(buf) + ('\n' if buf else '')
            pending_path = None
            continue
        if line.strip() and not fm:
            # A non-blank, non-fence, non-path line clears a stale path, so prose between a
            # heading and its block doesn't misattach the next code block.
            pending_path = None
        i += 1


def safe_join(dest, rel):
    # Containment must resist symlink escape, not just lexical ../ traversal: a symlink
    # planted in the workspace (e.g. by executed test code in a prior refine cycle — the
    # workspace is not cleared between cycles) could otherwise let `link/x` resolve outside.
    # So reject absolute paths up front, then verify the *real* (symlink-resolved) parent
    # directory stays under dest. The leaf may not exist yet, so resolve the parent only;
    # the write itself uses O_NOFOLLOW (see main) to refuse a symlinked leaf.
    if os.path.isabs(rel):
        return None
    dest_abs = os.path.realpath(dest)
    target = os.path.normpath(os.path.join(dest_abs, rel))
    parent = os.path.realpath(os.path.dirname(target))
    if parent != dest_abs and not parent.startswith(dest_abs + os.sep):
        return None
    return os.path.join(parent, os.path.basename(target))


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: extract_files.py <dest-dir> [src.md]")
    dest = sys.argv[1]
    text = open(sys.argv[2], encoding='utf-8').read() if len(sys.argv) > 2 else sys.stdin.read()
    written = 0
    for rel, content in parse(text):
        target = safe_join(dest, rel)
        if target is None:
            print(f"  skip (path escapes dest): {rel}", file=sys.stderr)
            continue
        os.makedirs(os.path.dirname(target) or '.', exist_ok=True)
        try:
            # O_NOFOLLOW: refuse to write through a symlinked leaf (defense-in-depth with
            # safe_join's parent-realpath check). One bad block is skipped, not fatal to the rest.
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
            with os.fdopen(fd, 'w', encoding='utf-8') as fh:
                fh.write(content)
        except OSError as e:
            print(f"  skip (write failed: {e}): {rel}", file=sys.stderr)
            continue
        print(f"  wrote {rel} ({len(content)}B)", file=sys.stderr)
        written += 1
    print(written)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
