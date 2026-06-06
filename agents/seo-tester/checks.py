#!/usr/bin/env python3
"""seo-tester deterministic checks.

The objective on-page checks (lengths, counts, presence) are computed here in code so the
model never has to count, that was the source of fabricated numbers. The two genuinely
subjective checks (answerable_intro, no_keyword_stuffing) are judged by the model and merged
in. Two modes:

  checks.py --objective         read page on stdin → JSON array of objective check results
  checks.py --merge OBJ SUBJ    OBJ=objective json file, SUBJ=raw model output → final JSON
"""
import sys, json, re

ORDER = ["title_length", "meta_length", "single_h1", "keyword_in_title", "keyword_in_h1",
         "keyword_early", "has_subheadings", "internal_link",
         "answerable_intro", "no_keyword_stuffing"]


def parse(text):
    def field(name):
        m = re.search(rf'^\s*{name}\s*:\s*(.*)$', text, re.M | re.I)
        return m.group(1).strip() if m else ''
    kw = field('Target keyword').lower()
    title = field('Title')
    meta = field('Meta')
    h1s = re.findall(r'^\s*H1\s*:\s*(.+)$', text, re.M | re.I) + re.findall(r'^#\s+(.+)$', text, re.M)
    subheads = re.findall(r'^\s*##\s+\S', text, re.M)
    body_lines = []
    for ln in text.splitlines():
        if re.match(r'^\s*(Target keyword|Title|Meta|H1)\s*:', ln, re.I):
            continue
        if re.match(r'^\s*#', ln):
            continue
        body_lines.append(ln)
    body = ' '.join(body_lines).strip()
    return kw, title, meta, h1s, subheads, body


def _kw_status(kw, text):
    """pass = exact phrase present; warn = ≥60% of keyword tokens present (close variant);
    fail = neither; warn = no keyword given to check against."""
    if not kw:
        return "warn", "no keyword"
    t = text.lower()
    if kw in t:
        return "pass", "exact"
    toks = [w for w in re.findall(r'\w+', kw) if len(w) > 2]
    hit = sum(1 for w in toks if w in t)
    if toks and hit / len(toks) >= 0.6:
        return "warn", f"partial {hit}/{len(toks)}"
    return "fail", "no"


def objective(text):
    kw, title, meta, h1s, subheads, body = parse(text)
    out = []
    def add(i, s, d): out.append({"id": i, "status": s, "detail": str(d)})

    tl = len(title)
    add("title_length", "pass" if 50 <= tl <= 60 else ("warn" if not title else "fail"),
        tl if title else "missing")
    ml = len(meta)
    add("meta_length", "pass" if 140 <= ml <= 160 else ("warn" if not meta else "fail"),
        ml if meta else "missing")
    add("single_h1", "pass" if len(h1s) == 1 else "fail", len(h1s))
    s, d = _kw_status(kw, title)
    add("keyword_in_title", s, d)
    s, d = _kw_status(kw, ' '.join(h1s))
    add("keyword_in_h1", s, d)
    first100 = ' '.join(body.split()[:100])
    s, d = _kw_status(kw, first100)
    add("keyword_early", s, d)
    add("has_subheadings", "pass" if len(subheads) >= 2 else ("warn" if len(subheads) == 1 else "fail"),
        len(subheads))
    real_link = bool(re.search(r'\]\([^)]+\)|https?://', body))
    add("internal_link", "pass" if real_link else "warn", "found" if real_link else "none")
    return out


def merge(obj, subj_raw):
    by = {c["id"]: c for c in obj}
    m = re.search(r'\{.*\}', subj_raw, re.S)
    subj = {}
    if m:
        try:
            subj = json.loads(m.group(0))
        except Exception:
            subj = {}
    for k in ("answerable_intro", "no_keyword_stuffing"):
        v = subj.get(k, {}) if isinstance(subj.get(k), dict) else {}
        st = v.get("status", "warn")
        if st not in ("pass", "fail", "warn"):
            st = "warn"
        by[k] = {"id": k, "status": st, "detail": str(v.get("detail", "not judged"))[:40]}
    checks = [by[k] for k in ORDER if k in by]
    p = sum(c["status"] == "pass" for c in checks)
    f = sum(c["status"] == "fail" for c in checks)
    w = sum(c["status"] == "warn" for c in checks)
    return {"checks": checks, "summary": {"pass": p, "fail": f, "warn": w,
                                          "verdict": "fail" if f else "pass"}}


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--objective":
        print(json.dumps(objective(sys.stdin.read()), separators=(',', ':')))
    elif mode == "--merge":
        obj = json.load(open(sys.argv[2]))
        subj_raw = open(sys.argv[3]).read()
        print(json.dumps(merge(obj, subj_raw), separators=(',', ':')))
    else:
        sys.exit("usage: checks.py --objective | --merge OBJ SUBJ")
