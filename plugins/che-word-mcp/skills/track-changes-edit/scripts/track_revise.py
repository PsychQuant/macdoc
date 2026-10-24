#!/usr/bin/env python3
"""Write minimal tracked changes and comments into a .docx, then verify them.

Usage:
    python3 track_revise.py spec.json input.docx output.docx

Each old/new pair in the spec is diffed character by character, so only the
characters that differ become <w:del>/<w:ins>; inserted text copies the run
properties of the place it goes. Every revision group carries a Word comment.
Whole-paragraph comments change no text (for questions left to the author).

Before writing, the result is checked: reject-all must equal the original,
accept-all must equal the intended text, and paragraphs outside the edit must
be byte-identical. Any failure writes nothing. The output path must not exist.

Spec (JSON):
    {
      "author": "Reviewer", "initials": "R", "date": "2026-01-01T00:00:00Z",
      "revisions": [
        {"paragraph": "<w14:paraId>"  or  "find": "<text unique to one paragraph>",
         "comment": "<reason, quoting the source>",
         "changes": [{"old": "<text, unique in the paragraph>", "new": "<replacement>"}]}
      ],
      "comments": [{"paragraph": "<paraId>" or "find": "...", "text": "<question>",
                    "anchor": "<optional: text unique in the paragraph; omit to comment the whole paragraph>"}]
    }

Stopgap until che-word-mcp writes tracked replacements itself
(PsychQuant/che-word-mcp#276, #292, #296).
"""
import datetime
import difflib
import json
import os
import re
import sys
import zipfile
from html import unescape
from xml.dom import minidom
from xml.sax.saxutils import escape

W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
COMMENTS_TYPE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments"
COMMENTS_CT = "application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"
PARA = re.compile(r"<w:p[ >](?:(?!</w:p>).)*?</w:p>", re.S)
RUN = re.compile(r"<w:r(?: [^>]*)?>(?:(?!</w:r>).)*?</w:r>", re.S)
REF_RUN = re.compile(r"<w:r(?: [^>]*)?>(?:<w:rPr>(?:(?!</w:r>).)*?</w:rPr>)?<w:commentReference [^>]*/></w:r>", re.S)
RUN_SHAPE = re.compile(
    r"(<w:r(?: [^>]*)?>)(<w:rPr>.*?</w:rPr>)?((?:<w:lastRenderedPageBreak/>)?)"
    r"<w:t(?: [^>]*)?>([^<]*)</w:t></w:r>", re.S)


class SpecError(Exception):
    pass


def well_formed(data):
    """Parse-check XML that may come from an untrusted document.

    OOXML parts never carry a DTD, so any DOCTYPE or ENTITY declaration is
    refused before parsing; with no declarations there is nothing to expand.
    """
    text = data.decode("utf-8") if isinstance(data, bytes) else data
    if "<!DOCTYPE" in text or "<!ENTITY" in text:
        raise SpecError("XML with a DOCTYPE or ENTITY declaration is not a valid OOXML part")
    minidom.parseString(text.encode("utf-8"))


# ---------- reading ----------

def plain(fragment):
    return unescape("".join(re.findall(r"<w:t(?: [^>]*)?>([^<]*)</w:t>", fragment)))


def locate(xml, target):
    """Return the match of the one paragraph a revision or comment targets."""
    if "paragraph" in target:
        hits = [m for m in PARA.finditer(xml) if f'w14:paraId="{target["paragraph"]}"' in m.group(0)]
        label = f'paragraph {target["paragraph"]}'
    elif "find" in target:
        hits = [m for m in PARA.finditer(xml) if target["find"] in plain(m.group(0))]
        label = f'paragraph containing {target["find"]!r}'
    else:
        raise SpecError("each entry needs 'paragraph' (a w14:paraId) or 'find' (unique text)")
    if len(hits) != 1:
        raise SpecError(f"{label}: {'not found' if not hits else f'{len(hits)} matches, need exactly 1'}")
    return hits[0]


def parse_run(run_xml):
    m = RUN_SHAPE.fullmatch(run_xml)
    if not m:
        raise SpecError("a run in the target paragraph holds more than plain text "
                        f"(tab, break, field or drawing); edit it in Word instead: {run_xml[:120]}")
    return m.group(1), m.group(2) or "", m.group(3), unescape(m.group(4))


# ---------- writing ----------

class Writer:
    def __init__(self, author, date, first_id, first_comment_id):
        self.author, self.date = escape(author, {'"': "&quot;"}), date
        self.rev, self.cid = first_id, first_comment_id
        self.comments = []  # (id, text)

    def next_rev(self):
        self.rev += 1
        return self.rev

    def new_comment(self, text):
        self.cid += 1
        self.comments.append((self.cid, text))
        return self.cid

    def run(self, ot, rpr, text, deleted=False, pre=""):
        tag = "w:delText" if deleted else "w:t"
        return f'{ot}{rpr}{pre}<{tag} xml:space="preserve">{escape(text)}</{tag}></w:r>'

    def deleted(self, ot, rpr, text, pre=""):
        return (f'<w:del w:id="{self.next_rev()}" w:author="{self.author}" w:date="{self.date}">'
                f"{self.run(ot, rpr, text, True, pre)}</w:del>")

    def inserted(self, ot, rpr, text):
        return (f'<w:ins w:id="{self.next_rev()}" w:author="{self.author}" w:date="{self.date}">'
                f"{self.run(ot, rpr, text)}</w:ins>")


def range_start(cid):
    return f'<w:commentRangeStart w:id="{cid}"/>'


def range_end(cid):
    return f'<w:commentRangeEnd w:id="{cid}"/><w:r><w:commentReference w:id="{cid}"/></w:r>'


def diff_ops(text, groups, writer):
    """Character-level ops (start, end, inserted, comment id) and each comment's span."""
    ops, spans = [], {}
    for comment, pairs in groups:
        cid = writer.new_comment(comment)
        lo = hi = None
        for pair in pairs:
            old, new = pair["old"], pair["new"]
            count = text.count(old)
            if count != 1:
                raise SpecError(f"{old!r}: {'not found' if not count else f'{count} matches'} in the paragraph")
            base = text.index(old)
            for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
                if tag != "equal":
                    ops.append((base + i1, base + i2, new[j1:j2], cid))
                    lo = base + i1 if lo is None else min(lo, base + i1)
                    hi = base + i2 if hi is None else max(hi, base + i2)
        if lo is None:
            raise SpecError(f"revision with comment {comment[:40]!r} changes nothing")
        spans[cid] = (lo, hi)
    ops.sort(key=lambda o: (o[0], o[1]))
    for a, b in zip(ops, ops[1:]):
        if a[1] > b[0]:
            raise SpecError("two changes overlap in the same paragraph")
    return ops, spans


def revise_paragraph(p, groups, writer):
    text = plain(p)
    ops, spans = diff_ops(text, groups, writer)
    starts = {}
    for cid, (lo, _) in spans.items():
        starts.setdefault(lo, []).append(cid)
    last_op = {cid: max((o for o in ops if o[3] == cid), key=lambda o: (o[1], o[0])) for cid in spans}
    out, last, pos, cur = [], 0, 0, None

    def at_point(point, ot, rpr):
        for cid in starts.pop(point, []):
            out.append(range_start(cid))
        for o in ops:
            if o[0] == o[1] == point:
                out.append(writer.inserted(ot, rpr, o[2]))
                if last_op[o[3]] is o:
                    out.append(range_end(o[3]))

    for m in text_runs(p):
        out.append(p[last:m.start()])
        last = m.end()
        ot, rpr, pre, t = parse_run(m.group(0))
        a, b = pos, pos + len(t)
        pos, cur = b, (ot, rpr)
        cuts = sorted({a, b} | {c for o in ops for c in o[:2] if a < c < b})
        for lo, hi in zip(cuts, cuts[1:]):
            at_point(lo, ot, rpr)
            piece, pr = t[lo - a:hi - a], (pre if lo == a else "")
            op = next((o for o in ops if o[0] <= lo and hi <= o[1] and o[0] < o[1]), None)
            if op is None:
                out.append(writer.run(ot, rpr, piece, pre=pr))
                continue
            out.append(writer.deleted(ot, rpr, piece, pr))
            if hi == op[1]:
                if op[2]:
                    out.append(writer.inserted(ot, rpr, op[2]))
                if last_op[op[3]] is op:
                    out.append(range_end(op[3]))
    if cur is None:
        raise SpecError("target paragraph has no text runs")
    at_point(len(text), *cur)
    out.append(p[last:])
    return "".join(out)


def text_runs(p):
    """Runs that carry text. Comment-reference runs hold none and stay as inter-run content."""
    return [m for m in RUN.finditer(p) if not REF_RUN.fullmatch(m.group(0))]


def comment_anchor(p, anchor, text, writer):
    """Wrap the one occurrence of `anchor` in a comment range; the text is unchanged."""
    full = plain(p)
    count = full.count(anchor)
    if not anchor or count != 1:
        raise SpecError(f"anchor {anchor!r}: {'not found' if not count else f'{count} matches'} in the paragraph")
    lo = full.index(anchor)
    hi = lo + len(anchor)
    cid = writer.new_comment(text)
    out, last, pos, opened, closed = [], 0, 0, False, False
    for m in text_runs(p):
        out.append(p[last:m.start()])
        last = m.end()
        ot, rpr, pre, t = parse_run(m.group(0))
        a, b = pos, pos + len(t)
        pos = b
        cuts = sorted({a, b} | {c for c in (lo, hi) if a < c < b})
        if len(cuts) <= 2:  # run not split: keep its bytes
            if a == lo and not opened:
                out.append(range_start(cid))
                opened = True
            out.append(m.group(0))
            if b == hi and opened and not closed and a < b:
                out.append(range_end(cid))
                closed = True
            continue
        for x, y in zip(cuts, cuts[1:]):
            if x == lo and not opened:
                out.append(range_start(cid))
                opened = True
            out.append(writer.run(ot, rpr, t[x - a:y - a], pre=pre if x == a else ""))
            if y == hi and not closed:
                out.append(range_end(cid))
                closed = True
    out.append(p[last:])
    return "".join(out)


def comment_paragraph(p, text, writer):
    runs = list(RUN.finditer(p))
    if not runs:
        raise SpecError("paragraph to comment on has no runs")
    cid = writer.new_comment(text)
    s, e = runs[0].start(), runs[-1].end()
    return p[:s] + range_start(cid) + p[s:e] + range_end(cid) + p[e:]


# ---------- verification ----------

def strip_comment_marks(xml):
    return re.sub(r'<w:commentRange(?:Start|End) w:id="\d+"/>|<w:r><w:commentReference w:id="\d+"/></w:r>', "", xml)


def paragraphs_text(xml):
    return [plain(m.group(0)) for m in PARA.finditer(xml)]


def verify(original, revised, expected_by_index, commented):
    bare = strip_comment_marks(revised)
    reject = re.sub(r"<w:ins [^>]*>.*?</w:ins>", "", bare, flags=re.S).replace("w:delText", "w:t")
    accept = re.sub(r"<w:del [^>]*>.*?</w:del>", "", bare, flags=re.S)
    if paragraphs_text(reject) != paragraphs_text(original):
        raise SpecError("verification failed: reject-all does not reproduce the original")
    got = paragraphs_text(accept)
    for i, want in expected_by_index.items():
        if got[i] != want:
            raise SpecError(f"verification failed: accept-all paragraph {i} is {got[i]!r}, expected {want!r}")
    before, after = [m.group(0) for m in PARA.finditer(original)], [m.group(0) for m in PARA.finditer(revised)]
    if len(before) != len(after):
        raise SpecError("verification failed: paragraph count changed")
    touched = set(expected_by_index) | set(commented)
    for i, (b, a) in enumerate(zip(before, after)):
        if i not in touched and a != b:
            raise SpecError(f"verification failed: paragraph {i} changed outside the edit")


# ---------- package ----------

def comments_part(existing, writer, initials):
    items = "".join(
        f'<w:comment w:id="{cid}" w:author="{writer.author}" w:date="{writer.date}" '
        f'w:initials="{escape(initials, {chr(34): "&quot;"})}"><w:p><w:r><w:t xml:space="preserve">'
        f"{escape(text)}</w:t></w:r></w:p></w:comment>" for cid, text in writer.comments)
    if existing is None:
        return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                f'<w:comments xmlns:w="{W}">{items}</w:comments>')
    return existing.replace("</w:comments>", items + "</w:comments>", 1)


def register_comments(parts):
    rels = parts["word/_rels/document.xml.rels"].decode("utf-8")
    ids = [int(i) for i in re.findall(r'Id="rId(\d+)"', rels)] or [0]
    rels = rels.replace("</Relationships>", f'<Relationship Id="rId{max(ids) + 1}" Type="{COMMENTS_TYPE}" '
                        'Target="comments.xml"/></Relationships>', 1)
    ct = parts["[Content_Types].xml"].decode("utf-8")
    ct = ct.replace("</Types>", f'<Override PartName="/word/comments.xml" ContentType="{COMMENTS_CT}"/></Types>', 1)
    parts["word/_rels/document.xml.rels"], parts["[Content_Types].xml"] = rels.encode(), ct.encode()


def build(spec, parts):
    well_formed(parts["word/document.xml"])
    xml = parts["word/document.xml"].decode("utf-8")
    existing = parts["word/comments.xml"].decode("utf-8") if "word/comments.xml" in parts else None
    used = [int(i) for i in re.findall(r'w:id="(-?\d+)"', xml + (existing or ""))] or [0]
    writer = Writer(spec.get("author", "Reviewer"), spec.get("date") or
                    datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    max(used) + 1000, max(used))
    original, expected, by_para, commented = xml, {}, {}, []
    for rev in spec.get("revisions", []):
        if not rev.get("comment"):
            raise SpecError("every revision group needs a 'comment' giving its reason and source")
        if not rev.get("changes"):
            raise SpecError("revision group has no 'changes'")
    comments = spec.get("comments", [])
    for c in comments:
        if not c.get("text"):
            raise SpecError("comment entry needs 'text'")
    # Anchored comments go on first, against the original text; revisions then skip their markers.
    for c in (c for c in comments if "anchor" in c):
        m = locate(xml, c)
        commented.append([p.start() for p in PARA.finditer(xml)].index(m.start()))
        xml = xml[:m.start()] + comment_anchor(m.group(0), c["anchor"], c["text"], writer) + xml[m.end():]
    starts = [m.start() for m in PARA.finditer(xml)]
    for rev in spec.get("revisions", []):
        m = locate(xml, rev)
        by_para.setdefault(m.start(), []).append((rev["comment"], rev["changes"]))
    for start in sorted(by_para, reverse=True):
        m = next(PARA.finditer(xml, start))
        want = plain(m.group(0))
        for _, pairs in by_para[start]:
            for pair in pairs:
                want = want.replace(pair["old"], pair["new"], 1)
        expected[starts.index(start)] = want
        xml = xml[:m.start()] + revise_paragraph(m.group(0), by_para[start], writer) + xml[m.end():]
    for c in (c for c in comments if "anchor" not in c):
        m = locate(xml, c)
        commented.append([p.start() for p in PARA.finditer(xml)].index(m.start()))
        xml = xml[:m.start()] + comment_paragraph(m.group(0), c["text"], writer) + xml[m.end():]
    well_formed(xml)
    verify(original, xml, expected, commented)
    parts["word/document.xml"] = xml.encode("utf-8")
    parts["word/comments.xml"] = comments_part(existing, writer, spec.get("initials", "")).encode("utf-8")
    if existing is None:
        register_comments(parts)
    for name in ("word/comments.xml", "word/_rels/document.xml.rels", "[Content_Types].xml"):
        well_formed(parts[name])
    return writer


def main(argv):
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    spec_path, src, dst = argv[1:]
    if os.path.exists(dst):
        print(f"refused: {dst} exists; choose a new output path", file=sys.stderr)
        return 2
    try:
        spec = json.loads(open(spec_path, encoding="utf-8").read())
        with zipfile.ZipFile(src) as zin:
            infos = zin.infolist()
            parts = {i.filename: zin.read(i.filename) for i in infos}
        had_comments = "word/comments.xml" in parts
        writer = build(spec, parts)
    except (SpecError, KeyError, ValueError, TypeError, AttributeError, OSError, zipfile.BadZipFile) as e:
        print(f"refused: {e}", file=sys.stderr)
        return 1
    tmp = dst + ".tmp"
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for info in infos:
            zout.writestr(info, parts[info.filename])
        if not had_comments:
            zout.writestr("word/comments.xml", parts["word/comments.xml"])
    os.replace(tmp, dst)
    xml = parts["word/document.xml"].decode("utf-8")
    print(f"ok: {len(re.findall(r'<w:ins ', xml))} insertions, {len(re.findall(r'<w:del ', xml))} deletions, "
          f"{len(writer.comments)} comments -> {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
