"""Tests for track_revise.py, using synthetic documents built in the test.

Run with:
    python3 -m unittest discover -s plugins/che-word-mcp/skills/track-changes-edit/tests
"""
import json
import pathlib
import re
import subprocess
import tempfile
import unittest
import zipfile
from html import unescape

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "track_revise.py"
W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
W14 = "http://schemas.microsoft.com/office/word/2010/wordml"

CONTENT_TYPES = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    "{extra}</Types>"
)
ROOT_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/></Relationships>'
)
DOC_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
    'Target="styles.xml"/>{extra}</Relationships>'
)

BLUE = '<w:rPr><w:color w:val="0000FF"/></w:rPr>'
BOLD = "<w:rPr><w:b/></w:rPr>"

PARAS = [
    # (paraId, inner XML)
    ("00000001", f'<w:r>{BLUE}<w:t>小組選定甲案，並於下次會面說明甲案進度。</w:t></w:r>'),
    ("00000002", f'<w:r>{BLUE}<w:t xml:space="preserve">費用由 </w:t></w:r>'
                 f'<w:proofErr w:type="spellStart"/>'
                 f'<w:r>{BOLD}<w:lastRenderedPageBreak/><w:t>甲方</w:t></w:r>'
                 f'<w:proofErr w:type="spellEnd"/>'
                 f'<w:r>{BLUE}<w:t>負擔。</w:t></w:r>'),
    ("00000003", '<w:r><w:t>R&amp;D 團隊另行處理。</w:t></w:r>'),
    ("00000004", '<w:r><w:t>這段不需要修改。</w:t></w:r>'),
]


def document_xml(paras=PARAS):
    body = "".join(f'<w:p w14:paraId="{pid}">{inner}</w:p>' for pid, inner in paras)
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            f'<w:document xmlns:w="{W}" xmlns:w14="{W14}"><w:body>{body}</w:body></w:document>')


def build_docx(path, with_comments=False):
    extra_ct = extra_rels = ""
    files = {"word/document.xml": document_xml(), "word/styles.xml":
             f'<?xml version="1.0" encoding="UTF-8"?><w:styles xmlns:w="{W}"/>'}
    if with_comments:
        extra_ct = ('<Override PartName="/word/comments.xml" ContentType='
                    '"application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"/>')
        extra_rels = ('<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
                      'relationships/comments" Target="comments.xml"/>')
        files["word/comments.xml"] = (
            f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:comments xmlns:w="{W}">'
            '<w:comment w:id="0" w:author="Earlier" w:initials="E"><w:p><w:r><w:t>既有註解</w:t></w:r></w:p>'
            "</w:comment></w:comments>")
    files["[Content_Types].xml"] = CONTENT_TYPES.format(extra=extra_ct)
    files["_rels/.rels"] = ROOT_RELS
    files["word/_rels/document.xml.rels"] = DOC_RELS.format(extra=extra_rels)
    with zipfile.ZipFile(path, "w") as z:
        for name, data in files.items():
            z.writestr(name, data)


def run(spec, src, dst):
    spec_path = pathlib.Path(dst).with_suffix(".json")
    spec_path.write_text(json.dumps(spec, ensure_ascii=False), encoding="utf-8")
    proc = subprocess.run(["python3", str(SCRIPT), str(spec_path), str(src), str(dst)],
                          capture_output=True, text=True, timeout=30)
    return proc


def part(path, name):
    with zipfile.ZipFile(path) as z:
        return z.read(name).decode("utf-8")


def para(xml, pid):
    m = re.search(rf'<w:p [^>]*w14:paraId="{pid}"[^>]*>.*?</w:p>', xml, re.S)
    assert m, pid
    return m.group(0)


def text_of(fragment, tag="w:t"):
    return unescape("".join(re.findall(rf"<{tag}(?: [^>]*)?>([^<]*)</{tag}>", fragment)))


def accept_all(p):
    p = re.sub(r"<w:del [^>]*>.*?</w:del>", "", p, flags=re.S)
    return text_of(p)


def reject_all(p):
    p = re.sub(r"<w:ins [^>]*>.*?</w:ins>", "", p, flags=re.S)
    return text_of(p.replace("w:delText", "w:t"))


def tracked(p, kind):
    tag = "w:delText" if kind == "del" else "w:t"
    return [text_of(m.group(1), tag) for m in re.finditer(rf"<w:{kind} [^>]*>(.*?)</w:{kind}>", p, re.S)]


class TrackRevise(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        self.src = self.dir / "fixture-a.docx"
        build_docx(self.src)
        self.dst = self.dir / "fixture-a-revised.docx"

    def tearDown(self):
        self.tmp.cleanup()

    def spec(self, revisions=(), comments=()):
        return {"author": "Reviewer A", "initials": "R", "date": "2026-01-01T00:00:00Z",
                "revisions": list(revisions), "comments": list(comments)}

    def test_marks_only_the_characters_that_differ(self):
        proc = run(self.spec([{"paragraph": "00000001", "comment": "依據原文第二節。",
                               "changes": [{"old": "小組選定", "new": "小組評估"}]}]),
                   self.src, self.dst)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        p = para(part(self.dst, "word/document.xml"), "00000001")
        self.assertEqual(tracked(p, "del"), ["選定"])
        self.assertEqual(tracked(p, "ins"), ["評估"])
        self.assertEqual(accept_all(p), "小組評估甲案，並於下次會面說明甲案進度。")
        self.assertEqual(reject_all(p), "小組選定甲案，並於下次會面說明甲案進度。")

    def test_inserted_text_keeps_the_run_formatting(self):
        run(self.spec([{"paragraph": "00000001", "comment": "補上。",
                        "changes": [{"old": "下次會面說明", "new": "下次會面說明結果"}]}]), self.src, self.dst)
        p = para(part(self.dst, "word/document.xml"), "00000001")
        ins = re.search(r"<w:ins [^>]*>(.*?)</w:ins>", p, re.S).group(1)
        self.assertIn('<w:color w:val="0000FF"/>', ins)
        self.assertEqual(tracked(p, "del"), [])
        self.assertEqual(tracked(p, "ins"), ["結果"])

    def test_change_across_runs_keeps_each_runs_formatting_and_markers(self):
        proc = run(self.spec([{"paragraph": "00000002", "comment": "依據原文第三節。",
                               "changes": [{"old": "由 甲方負擔", "new": "由 乙方分擔"}]}]),
                   self.src, self.dst)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        p = para(part(self.dst, "word/document.xml"), "00000002")
        self.assertEqual(accept_all(p), "費用由 乙方分擔。")
        self.assertEqual(reject_all(p), "費用由 甲方負擔。")
        self.assertEqual(p.count('<w:proofErr w:type="spellStart"/>'), 1)
        self.assertEqual(p.count("<w:lastRenderedPageBreak/>"), 1)
        deleted_bold = re.search(r"<w:del [^>]*>(<w:r>(?:(?!</w:r>).)*甲(?:(?!</w:r>).)*</w:r>)</w:del>", p, re.S)
        self.assertIsNotNone(deleted_bold)
        self.assertIn("<w:b/>", deleted_bold.group(1))

    def test_entities_are_matched_unescaped_and_written_escaped(self):
        proc = run(self.spec([{"find": "R&D", "comment": "改為全名。",
                               "changes": [{"old": "R&D 團隊", "new": "R&D 研發團隊"}]}]), self.src, self.dst)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        xml = part(self.dst, "word/document.xml")
        p = para(xml, "00000003")
        self.assertEqual(accept_all(p), "R&D 研發團隊另行處理。")
        self.assertIn("R&amp;D", p)

    def test_each_revision_group_gets_a_comment_quoting_its_reason(self):
        run(self.spec([{"paragraph": "00000001", "comment": "依據原文第二節。",
                        "changes": [{"old": "選定", "new": "評估"}]}]), self.src, self.dst)
        xml = part(self.dst, "word/document.xml")
        comments = part(self.dst, "word/comments.xml")
        self.assertEqual(len(re.findall(r"<w:comment ", comments)), 1)
        self.assertIn("依據原文第二節。", comments)
        self.assertIn('w:author="Reviewer A"', comments)
        cid = re.search(r'<w:comment w:id="(\d+)"', comments).group(1)
        self.assertIn(f'<w:commentRangeStart w:id="{cid}"/>', xml)
        self.assertIn(f'<w:commentReference w:id="{cid}"/>', xml)
        self.assertIn("comments.xml", part(self.dst, "word/_rels/document.xml.rels"))
        self.assertIn("/word/comments.xml", part(self.dst, "[Content_Types].xml"))

    def test_whole_paragraph_comment_changes_no_text(self):
        proc = run(self.spec(comments=[{"paragraph": "00000004", "text": "這段是否保留，請作者決定。"}]),
                   self.src, self.dst)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        p = para(part(self.dst, "word/document.xml"), "00000004")
        self.assertNotIn("<w:ins ", p)
        self.assertNotIn("<w:del ", p)
        self.assertIn("<w:commentRangeStart", p)
        self.assertEqual(text_of(p), "這段不需要修改。")

    def test_other_paragraphs_are_byte_identical(self):
        run(self.spec([{"paragraph": "00000001", "comment": "x", "changes": [{"old": "選定", "new": "評估"}]}]),
            self.src, self.dst)
        before, after = part(self.src, "word/document.xml"), part(self.dst, "word/document.xml")
        for pid in ("00000002", "00000003", "00000004"):
            self.assertEqual(para(before, pid), para(after, pid))

    def test_existing_comments_part_is_extended_not_duplicated(self):
        src = self.dir / "fixture-b.docx"
        build_docx(src, with_comments=True)
        dst = self.dir / "fixture-b-revised.docx"
        proc = run(self.spec([{"paragraph": "00000001", "comment": "新的註解。",
                               "changes": [{"old": "選定", "new": "評估"}]}]), src, dst)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        with zipfile.ZipFile(dst) as z:
            names = z.namelist()
        self.assertEqual(names.count("word/comments.xml"), 1)
        comments = part(dst, "word/comments.xml")
        self.assertIn("既有註解", comments)
        self.assertIn("新的註解。", comments)
        ids = re.findall(r'<w:comment w:id="(\d+)"', comments)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(part(dst, "word/_rels/document.xml.rels").count("comments.xml"), 1)
        self.assertEqual(part(dst, "[Content_Types].xml").count("/word/comments.xml"), 1)

    def test_refuses_text_that_is_not_unique(self):
        proc = run(self.spec([{"paragraph": "00000001", "comment": "x", "changes": [{"old": "甲案", "new": "乙案"}]}]),
                   self.src, self.dst)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(self.dst.exists())

    def test_refuses_text_that_is_absent(self):
        proc = run(self.spec([{"paragraph": "00000001", "comment": "x",
                               "changes": [{"old": "不存在的字串", "new": "y"}]}]), self.src, self.dst)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("not found", proc.stderr)
        self.assertFalse(self.dst.exists())

    def test_refuses_a_find_that_matches_several_paragraphs(self):
        proc = run(self.spec([{"find": "。", "comment": "x", "changes": [{"old": "選定", "new": "評估"}]}]),
                   self.src, self.dst)
        self.assertNotEqual(proc.returncode, 0)
        self.assertFalse(self.dst.exists())

    def test_refuses_to_overwrite_an_existing_output(self):
        self.dst.write_bytes(b"keep me")
        proc = run(self.spec([{"paragraph": "00000001", "comment": "x", "changes": [{"old": "選定", "new": "評估"}]}]),
                   self.src, self.dst)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self.dst.read_bytes(), b"keep me")

    def test_refuses_writing_onto_the_source(self):
        proc = run(self.spec([{"paragraph": "00000001", "comment": "x", "changes": [{"old": "選定", "new": "評估"}]}]),
                   self.src, self.src)
        self.assertNotEqual(proc.returncode, 0)

    def test_requires_a_comment_for_every_revision_group(self):
        proc = run(self.spec([{"paragraph": "00000001", "changes": [{"old": "選定", "new": "評估"}]}]),
                   self.src, self.dst)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("every revision group needs a 'comment'", proc.stderr)
        self.assertFalse(self.dst.exists())

    def test_malformed_spec_is_refused_without_a_traceback(self):
        proc = run(self.spec([{"paragraph": "00000001", "comment": "x", "changes": [{"old": 1, "new": "y"}]}]),
                   self.src, self.dst)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("refused:", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)
        self.assertFalse(self.dst.exists())

    def test_refuses_a_document_part_with_a_dtd(self):
        src = self.dir / "fixture-c.docx"
        build_docx(src)
        with zipfile.ZipFile(src) as z:
            parts = {n: z.read(n) for n in z.namelist()}
        doc = parts["word/document.xml"].decode()
        parts["word/document.xml"] = doc.replace("<w:document", '<!DOCTYPE d [<!ENTITY x "y">]><w:document', 1).encode()
        with zipfile.ZipFile(src, "w") as z:
            for n, data in parts.items():
                z.writestr(n, data)
        proc = run(self.spec([{"paragraph": "00000001", "comment": "x", "changes": [{"old": "選定", "new": "評估"}]}]),
                   src, self.dir / "fixture-c-revised.docx")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("DOCTYPE", proc.stderr)

    def test_source_file_is_unchanged(self):
        before = self.src.read_bytes()
        run(self.spec([{"paragraph": "00000001", "comment": "x", "changes": [{"old": "選定", "new": "評估"}]}]),
            self.src, self.dst)
        self.assertEqual(self.src.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
