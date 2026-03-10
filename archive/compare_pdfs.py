#!/usr/bin/env python3
"""
Informative PDF Comparison Tool
Compares a reproduced PDF against an original, providing detailed similarity metrics.

Key insight: Pages don't align 1:1 between original and reproduced PDFs because
LaTeX re-flows text. This tool uses chapter-aligned comparison and full-text
coverage analysis instead of naive page-by-page comparison.

Usage:
    python3 compare_pdfs.py <original.pdf> <reproduced.pdf> [--output-dir <dir>]
"""

import sys
import os
import re
import json
import difflib
from pathlib import Path
from collections import defaultdict

import fitz  # PyMuPDF


def extract_all_text(doc):
    """Extract all text from document, page by page."""
    texts = []
    for i in range(len(doc)):
        texts.append(doc[i].get_text("text"))
    return texts


def normalize_text(text):
    """Normalize text for comparison (collapse whitespace, lowercase)."""
    text = re.sub(r'\s+', ' ', text).strip().lower()
    return text


def find_chapter_starts(doc):
    """Find chapter start pages using multiple heuristics.

    Strategies:
    1. "Chapter N" as standalone line (title page or content page)
    2. "Chapter N" anywhere in page text (for mis-rendered chapters)
    3. Section numbers like "10.1" that indicate chapter changes

    Returns: list of (page_index, chapter_number, chapter_title)
    """
    chapters = []
    seen_chapters = set()

    for i in range(len(doc)):
        text = doc[i].get_text("text").strip()
        lines = [l.strip() for l in text.split('\n') if l.strip()]
        if not lines:
            continue

        # Strategy 1: "Chapter N" as first line
        first_line = lines[0]
        match = re.match(r'^Chapter\s+(\d+)$', first_line, re.IGNORECASE)
        if match:
            ch_num = int(match.group(1))
            if ch_num not in seen_chapters:
                title_line_idx = next(
                    (j for j, l in enumerate(lines[1:], 1) if l and not l[0].isdigit()),
                    None
                )
                title = lines[title_line_idx] if title_line_idx else f"Chapter {ch_num}"
                chapters.append((i, ch_num, title))
                seen_chapters.add(ch_num)
                continue

        # Strategy 2: "Chapter N" anywhere in page (for broken \chapter rendering)
        for line in lines:
            match = re.match(r'^Chapter\s+(\d+)$', line, re.IGNORECASE)
            if match:
                ch_num = int(match.group(1))
                if ch_num not in seen_chapters:
                    # Find the title (usually the next non-empty line)
                    line_idx = lines.index(line)
                    title = lines[line_idx + 1] if line_idx + 1 < len(lines) else f"Chapter {ch_num}"
                    chapters.append((i, ch_num, title))
                    seen_chapters.add(ch_num)
                    break

    # Sort by page index
    chapters.sort(key=lambda x: x[0])
    return chapters


def find_chapter_ranges(chapters, total_pages):
    """Convert chapter starts to (start, end) page ranges."""
    ranges = []
    for idx, (page, ch_num, title) in enumerate(chapters):
        if idx + 1 < len(chapters):
            end = chapters[idx + 1][0]
        else:
            end = total_pages
        ranges.append((ch_num, title, page, end))
    return ranges


def extract_chapter_text(doc, start_page, end_page):
    """Extract and concatenate text for a chapter range."""
    texts = []
    for i in range(start_page, end_page):
        page_text = doc[i].get_text("text")
        # Remove running headers like "CHAPTER N. TITLE"
        lines = page_text.split('\n')
        filtered = []
        for line in lines:
            stripped = line.strip()
            if re.match(r'^CHAPTER\s+\d+\.\s+', stripped, re.IGNORECASE):
                continue  # Skip running headers
            filtered.append(line)
        texts.append('\n'.join(filtered))
    return '\n'.join(texts)


def word_set_coverage(text_orig, text_repr):
    """Calculate what fraction of original words appear in reproduced text.

    Uses word sets (bag of words) — order-independent coverage metric.
    """
    words_o = set(normalize_text(text_orig).split())
    words_r = set(normalize_text(text_repr).split())
    if not words_o:
        return 1.0 if not words_r else 0.0
    covered = words_o & words_r
    return len(covered) / len(words_o)


def sequence_similarity(text_a, text_b, max_len=50000):
    """Compute word-level sequence similarity.

    For very long texts, sample to keep it tractable.
    """
    words_a = normalize_text(text_a).split()
    words_b = normalize_text(text_b).split()

    if not words_a and not words_b:
        return 1.0
    if not words_a or not words_b:
        return 0.0

    # Sample if too long
    if len(words_a) > max_len:
        step = len(words_a) // max_len
        words_a = words_a[::step]
    if len(words_b) > max_len:
        step = len(words_b) // max_len
        words_b = words_b[::step]

    return difflib.SequenceMatcher(None, words_a, words_b).ratio()


def count_math_elements(text):
    """Count math-related elements in text."""
    equations = len(re.findall(r'\\begin\{(?:equation|align|gather)', text))
    inline_math = text.count('$') // 2  # rough estimate
    theorems = len(re.findall(r'\\begin\{(?:theorem|lemma|proposition|corollary|definition)', text))
    return {"equations": equations, "inline_math": inline_math, "theorems": theorems}


def count_images(doc, page_num):
    """Count images on a page."""
    page = doc[page_num]
    return len(page.get_images(full=True))


def render_page_pixmap(doc, page_num, dpi=150):
    """Render page to pixmap at given DPI."""
    page = doc[page_num]
    mat = fitz.Matrix(dpi / 72, dpi / 72)
    return page.get_pixmap(matrix=mat)


def pixel_similarity_fast(pix_a, pix_b, sample_rate=4):
    """Fast pixel comparison by sampling every Nth pixel."""
    w = min(pix_a.width, pix_b.width)
    h = min(pix_a.height, pix_b.height)

    samples_a = pix_a.samples
    samples_b = pix_b.samples
    n_a = pix_a.n
    n_b = pix_b.n
    stride_a = pix_a.stride
    stride_b = pix_b.stride

    total = 0
    close_match = 0
    threshold = 30

    for y in range(0, h, sample_rate):
        for x in range(0, w, sample_rate):
            off_a = y * stride_a + x * n_a
            off_b = y * stride_b + x * n_b

            channels = min(3, n_a, n_b)
            max_diff = 0
            for c in range(channels):
                diff = abs(samples_a[off_a + c] - samples_b[off_b + c])
                max_diff = max(max_diff, diff)

            total += 1
            if max_diff <= threshold:
                close_match += 1

    return close_match / total if total else 0


def compare_pdfs(original_path, reproduced_path, output_dir=None, visual_sample_pages=None):
    """Main comparison function with chapter-aligned analysis."""
    print(f"Original:   {original_path}")
    print(f"Reproduced: {reproduced_path}")
    print("=" * 80)

    doc_orig = fitz.open(original_path)
    doc_repr = fitz.open(reproduced_path)

    n_orig = len(doc_orig)
    n_repr = len(doc_repr)

    # ─── 1. Basic Stats ─────────────────────────────────────────────────
    print(f"\n{'─' * 80}")
    print(f"  1. BASIC STATISTICS")
    print(f"{'─' * 80}")
    print(f"  Original:   {n_orig} pages")
    print(f"  Reproduced: {n_repr} pages")
    print(f"  Difference: {n_repr - n_orig:+d} pages ({n_repr/n_orig:.1%} of original)")

    # Total word counts
    all_text_orig = '\n'.join(extract_all_text(doc_orig))
    all_text_repr = '\n'.join(extract_all_text(doc_repr))
    words_orig = len(all_text_orig.split())
    words_repr = len(all_text_repr.split())
    chars_orig = len(all_text_orig)
    chars_repr = len(all_text_repr)

    print(f"\n  Total words:  orig={words_orig:,}  repr={words_repr:,}  ({words_repr/words_orig:.1%})")
    print(f"  Total chars:  orig={chars_orig:,}  repr={chars_repr:,}  ({chars_repr/chars_orig:.1%})")

    # Image count
    total_img_orig = sum(count_images(doc_orig, i) for i in range(n_orig))
    total_img_repr = sum(count_images(doc_repr, i) for i in range(n_repr))
    print(f"  Total images: orig={total_img_orig}  repr={total_img_repr}")

    # ─── 2. Full-Text Coverage ───────────────────────────────────────────
    print(f"\n{'─' * 80}")
    print(f"  2. FULL-TEXT COVERAGE (bag-of-words)")
    print(f"{'─' * 80}")
    coverage = word_set_coverage(all_text_orig, all_text_repr)
    print(f"  Word coverage: {coverage:.1%} of original words found in reproduced")

    # Reverse coverage
    rev_coverage = word_set_coverage(all_text_repr, all_text_orig)
    print(f"  Reverse coverage: {rev_coverage:.1%} of reproduced words found in original")

    # Find unique words in each
    words_o_set = set(normalize_text(all_text_orig).split())
    words_r_set = set(normalize_text(all_text_repr).split())
    only_in_orig = words_o_set - words_r_set
    only_in_repr = words_r_set - words_o_set

    print(f"\n  Unique vocabulary: orig={len(words_o_set):,}  repr={len(words_r_set):,}")
    print(f"  Words only in original:   {len(only_in_orig):,}")
    print(f"  Words only in reproduced: {len(only_in_repr):,}")

    if only_in_orig:
        sample = sorted(list(only_in_orig))[:20]
        print(f"  Sample missing words: {', '.join(sample[:10])}")

    # ─── 3. Chapter-Aligned Comparison ───────────────────────────────────
    print(f"\n{'─' * 80}")
    print(f"  3. CHAPTER-ALIGNED COMPARISON")
    print(f"{'─' * 80}")

    ch_orig = find_chapter_starts(doc_orig)
    ch_repr = find_chapter_starts(doc_repr)

    print(f"  Chapters found: orig={len(ch_orig)}  repr={len(ch_repr)}")

    ranges_orig = find_chapter_ranges(ch_orig, n_orig)
    ranges_repr = find_chapter_ranges(ch_repr, n_repr)

    # Build lookup by chapter number
    ch_orig_map = {r[0]: r for r in ranges_orig}
    ch_repr_map = {r[0]: r for r in ranges_repr}

    all_ch_nums = sorted(set(list(ch_orig_map.keys()) + list(ch_repr_map.keys())))

    chapter_results = []
    print(f"\n  {'Ch':>3}  {'Title':<35}  {'Orig':>10}  {'Repr':>10}  {'Coverage':>9}  {'SeqSim':>8}")
    print(f"  {'─'*3}  {'─'*35}  {'─'*10}  {'─'*10}  {'─'*9}  {'─'*8}")

    for ch_num in all_ch_nums:
        orig_r = ch_orig_map.get(ch_num)
        repr_r = ch_repr_map.get(ch_num)

        if orig_r and repr_r:
            text_o = extract_chapter_text(doc_orig, orig_r[2], orig_r[3])
            text_r = extract_chapter_text(doc_repr, repr_r[2], repr_r[3])

            cov = word_set_coverage(text_o, text_r)
            sim = sequence_similarity(text_o, text_r)

            orig_pages = f"{orig_r[3] - orig_r[2]} pp"
            repr_pages = f"{repr_r[3] - repr_r[2]} pp"
            title = orig_r[1][:35]

            chapter_results.append({
                "chapter": ch_num,
                "title": orig_r[1],
                "orig_pages": orig_r[3] - orig_r[2],
                "repr_pages": repr_r[3] - repr_r[2],
                "word_coverage": round(cov, 4),
                "sequence_similarity": round(sim, 4),
            })

            print(f"  {ch_num:>3}  {title:<35}  {orig_pages:>10}  {repr_pages:>10}  {cov:>8.1%}  {sim:>7.1%}")
        elif orig_r:
            title = orig_r[1][:35]
            orig_pages = f"{orig_r[3] - orig_r[2]} pp"
            print(f"  {ch_num:>3}  {title:<35}  {orig_pages:>10}  {'MISSING':>10}  {'N/A':>9}  {'N/A':>8}")
            chapter_results.append({
                "chapter": ch_num,
                "title": orig_r[1],
                "orig_pages": orig_r[3] - orig_r[2],
                "repr_pages": 0,
                "word_coverage": 0,
                "sequence_similarity": 0,
                "status": "missing_in_reproduced"
            })
        else:
            title = repr_r[1][:35] if repr_r else f"Chapter {ch_num}"
            repr_pages = f"{repr_r[3] - repr_r[2]} pp" if repr_r else "?"
            print(f"  {ch_num:>3}  {title:<35}  {'MISSING':>10}  {repr_pages:>10}  {'N/A':>9}  {'N/A':>8}")

    if chapter_results:
        valid = [c for c in chapter_results if "status" not in c]
        if valid:
            avg_cov = sum(c["word_coverage"] for c in valid) / len(valid)
            avg_sim = sum(c["sequence_similarity"] for c in valid) / len(valid)
            print(f"\n  Average coverage:   {avg_cov:.1%}")
            print(f"  Average similarity: {avg_sim:.1%}")

    # ─── 4. Content Gaps Analysis ────────────────────────────────────────
    print(f"\n{'─' * 80}")
    print(f"  4. CONTENT GAPS ANALYSIS")
    print(f"{'─' * 80}")

    # Check which chapters from original are missing in reproduced
    orig_ch_nums = set(ch_orig_map.keys())
    repr_ch_nums = set(ch_repr_map.keys())
    missing = orig_ch_nums - repr_ch_nums
    extra = repr_ch_nums - orig_ch_nums

    if missing:
        print(f"\n  Missing chapters: {sorted(missing)}")
        for ch in sorted(missing):
            r = ch_orig_map[ch]
            print(f"    Chapter {ch}: {r[1]} ({r[3]-r[2]} pages)")
    else:
        print(f"\n  No missing chapters (all {len(orig_ch_nums)} original chapters present)")

    # Check for front/back matter
    if ch_orig:
        front_pages_orig = ch_orig[0][0]  # pages before first chapter
    else:
        front_pages_orig = 0
    if ch_repr:
        front_pages_repr = ch_repr[0][0]
    else:
        front_pages_repr = 0

    print(f"\n  Front matter: orig={front_pages_orig} pages  repr={front_pages_repr} pages")

    if ch_orig:
        back_pages_orig = n_orig - ranges_orig[-1][3] if ranges_orig else 0
    else:
        back_pages_orig = 0
    if ch_repr:
        back_pages_repr = n_repr - ranges_repr[-1][3] if ranges_repr else 0
    else:
        back_pages_repr = 0
    print(f"  Back matter:  orig={back_pages_orig} pages  repr={back_pages_repr} pages")

    # ─── 5. Visual Comparison (sampled) ──────────────────────────────────
    if visual_sample_pages and output_dir:
        os.makedirs(output_dir, exist_ok=True)
        print(f"\n{'─' * 80}")
        print(f"  5. VISUAL COMPARISON (sampled pages)")
        print(f"{'─' * 80}")

        visual_results = []
        for orig_pg, repr_pg in visual_sample_pages:
            if orig_pg >= n_orig or repr_pg >= n_repr:
                continue
            print(f"  orig p{orig_pg+1} vs repr p{repr_pg+1}...", end=" ", flush=True)
            pix_o = render_page_pixmap(doc_orig, orig_pg, dpi=100)
            pix_r = render_page_pixmap(doc_repr, repr_pg, dpi=100)

            close = pixel_similarity_fast(pix_o, pix_r)
            visual_results.append({
                "orig_page": orig_pg + 1,
                "repr_page": repr_pg + 1,
                "close_pixel_match": round(close, 4),
            })
            print(f"similarity={close:.1%}")

            # Save images
            pix_o.save(os.path.join(output_dir, f"orig_p{orig_pg+1:03d}.png"))
            pix_r.save(os.path.join(output_dir, f"repr_p{repr_pg+1:03d}.png"))

    # ─── 6. Summary ─────────────────────────────────────────────────────
    print(f"\n{'─' * 80}")
    print(f"  SUMMARY")
    print(f"{'─' * 80}")
    print(f"  Page ratio:     {n_repr}/{n_orig} = {n_repr/n_orig:.1%}")
    print(f"  Word ratio:     {words_repr:,}/{words_orig:,} = {words_repr/words_orig:.1%}")
    print(f"  Word coverage:  {coverage:.1%} (original words found in reproduced)")
    if chapter_results:
        valid = [c for c in chapter_results if "status" not in c]
        if valid:
            print(f"  Avg ch coverage: {avg_cov:.1%}")
            print(f"  Avg ch sequence: {avg_sim:.1%}")

    missing_chs = sorted(orig_ch_nums - repr_ch_nums) if ch_orig else []
    if missing_chs:
        print(f"  Missing chapters: {missing_chs}")
    else:
        print(f"  All chapters present")
    print(f"  Images: {total_img_repr} (reproduced) vs {total_img_orig} (original embedded)")

    # Save JSON report
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        report = {
            "original": str(original_path),
            "reproduced": str(reproduced_path),
            "original_pages": n_orig,
            "reproduced_pages": n_repr,
            "original_words": words_orig,
            "reproduced_words": words_repr,
            "word_coverage": round(coverage, 4),
            "reverse_coverage": round(rev_coverage, 4),
            "total_images_original": total_img_orig,
            "total_images_reproduced": total_img_repr,
            "chapters": chapter_results,
            "missing_chapters": sorted(missing) if missing else [],
        }
        report_path = os.path.join(output_dir, "comparison_report.json")
        with open(report_path, "w") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print(f"\n  Report saved: {report_path}")

    doc_orig.close()
    doc_repr.close()

    print("\n" + "=" * 80)


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Informative PDF Comparison Tool")
    parser.add_argument("original", help="Path to original PDF")
    parser.add_argument("reproduced", help="Path to reproduced PDF")
    parser.add_argument("--output-dir", "-o", default=None,
                        help="Directory to save comparison report and images")
    parser.add_argument("--visual", "-v", action="store_true",
                        help="Enable visual comparison of chapter-aligned pages")
    args = parser.parse_args()

    if not os.path.exists(args.original):
        print(f"Error: Original PDF not found: {args.original}")
        sys.exit(1)
    if not os.path.exists(args.reproduced):
        print(f"Error: Reproduced PDF not found: {args.reproduced}")
        sys.exit(1)

    visual_pages = None
    if args.visual:
        # Build chapter-aligned page pairs for visual comparison
        doc_o = fitz.open(args.original)
        doc_r = fitz.open(args.reproduced)
        ch_o = find_chapter_starts(doc_o)
        ch_r = find_chapter_starts(doc_r)

        ch_o_map = {ch[1]: ch[0] for ch in ch_o}  # ch_num -> page
        ch_r_map = {ch[1]: ch[0] for ch in ch_r}

        visual_pages = []
        for ch_num in sorted(set(ch_o_map.keys()) & set(ch_r_map.keys())):
            # Compare chapter start + a few pages in
            o_start = ch_o_map[ch_num]
            r_start = ch_r_map[ch_num]
            visual_pages.append((o_start, r_start))
            visual_pages.append((min(o_start + 3, len(doc_o) - 1),
                                min(r_start + 3, len(doc_r) - 1)))

        doc_o.close()
        doc_r.close()

    if not args.output_dir:
        args.output_dir = "/tmp/pdf_comparison"

    compare_pdfs(args.original, args.reproduced, args.output_dir, visual_pages)


if __name__ == "__main__":
    main()
