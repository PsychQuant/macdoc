#!/usr/bin/env python3
"""
Ensemble OCR Benchmark — 測試各 VLM 模型的 OCR 忠實度

Usage:
    # 用 Ollama 測試所有模型（預設 localhost:11434）
    python3 benchmark_ocr.py --pdf paper.pdf --pages 3,4 --host localhost:11435

    # 只測特定模型
    python3 benchmark_ocr.py --pdf paper.pdf --pages 3 --models glm-ocr,gemma4

    # 用已有的渲染圖測試
    python3 benchmark_ocr.py --images page-3.png,page-4.png --host localhost:11435

    # 輸出 JSON 報告
    python3 benchmark_ocr.py --pdf paper.pdf --pages 3 --json -o report.json
"""

import argparse
import base64
import difflib
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

# ──────────────────────────────────────────────────────────────
# Config
# ──────────────────────────────────────────────────────────────

DEFAULT_OLLAMA_HOST = "localhost:11434"
DEFAULT_PROMPT = "OCR the text in this image. Output the exact text as it appears."

# Models to test — name: description
OLLAMA_MODELS = {
    "glm-ocr":      "GLM-OCR (智譜, OCR-specialized)",
    "gemma4":        "Gemma 4 (Google, 通用 VLM)",
    "qwen2-vl:2b":  "Qwen2-VL 2B (阿里)",
    "qwen2.5-vl:3b": "Qwen2.5-VL 3B (阿里)",
    "qwen3-vl:4b":  "Qwen3-VL 4B (阿里)",
    "gemma3:4b":     "Gemma 3 4B (Google)",
    "paligemma":     "PaliGemma 3B (Google, OCR-oriented)",
    "smolvlm":       "SmolVLM (HuggingFace, 輕量)",
    "pixtral:12b":   "Pixtral 12B (Mistral)",
    "minicpm-v":     "MiniCPM-V (額外測試)",
}

# ──────────────────────────────────────────────────────────────
# PDF rendering (requires PyMuPDF)
# ──────────────────────────────────────────────────────────────

def render_pdf_pages(pdf_path: str, pages: list[int], dpi: int = 200) -> dict[int, str]:
    """Render PDF pages to PNG files. Returns {page_num: png_path}."""
    try:
        import fitz
    except ImportError:
        print("錯誤: 需要 PyMuPDF — pip install pymupdf", file=sys.stderr)
        sys.exit(1)

    doc = fitz.open(pdf_path)
    out_dir = Path("/tmp/ocr-benchmark")
    out_dir.mkdir(exist_ok=True)

    results = {}
    for pg in pages:
        idx = pg - 1
        if idx < 0 or idx >= doc.page_count:
            print(f"警告: 頁碼 {pg} 超出範圍 (1-{doc.page_count})", file=sys.stderr)
            continue
        page = doc[idx]
        pix = page.get_pixmap(dpi=dpi)
        out_path = str(out_dir / f"page-{pg}.png")
        pix.save(out_path)
        results[pg] = out_path

    doc.close()
    return results


def extract_pdfkit_text(pdf_path: str, pages: list[int]) -> dict[int, str]:
    """Extract text from PDF using PyMuPDF (proxy for PDFKit)."""
    try:
        import fitz
    except ImportError:
        return {}

    doc = fitz.open(pdf_path)
    results = {}
    for pg in pages:
        idx = pg - 1
        if 0 <= idx < doc.page_count:
            results[pg] = doc[idx].get_text()
    doc.close()
    return results


# ──────────────────────────────────────────────────────────────
# Ollama API
# ──────────────────────────────────────────────────────────────

def ollama_generate(host: str, model: str, prompt: str, image_b64: str,
                    timeout: int = 300) -> tuple[str, float]:
    """Call Ollama generate API. Returns (response_text, elapsed_seconds)."""
    url = f"http://{host}/api/generate"
    payload = json.dumps({
        "model": model,
        "prompt": prompt,
        "images": [image_b64],
        "stream": False,
        "options": {"temperature": 0.1},
    }).encode()

    req = urllib.request.Request(url, data=payload,
                                headers={"Content-Type": "application/json"})

    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.loads(resp.read())
            elapsed = time.time() - start
            return data.get("response", ""), elapsed
    except Exception as e:
        elapsed = time.time() - start
        return f"ERROR: {e}", elapsed


def check_model_available(host: str, model: str) -> bool:
    """Check if a model is available on Ollama."""
    url = f"http://{host}/api/tags"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            data = json.loads(resp.read())
            available = [m["name"] for m in data.get("models", [])]
            # Check exact match or base name match
            return model in available or f"{model}:latest" in available
    except Exception:
        return False


# ──────────────────────────────────────────────────────────────
# Text comparison
# ──────────────────────────────────────────────────────────────

def normalize_text(text: str) -> str:
    """Normalize text for comparison."""
    # Remove common VLM preambles
    text = re.sub(r'\*\*\*.*?\*\*\*', '', text, flags=re.DOTALL)
    text = re.sub(r'```(?:markdown)?\s*', '', text)
    text = re.sub(r'```\s*$', '', text)
    # Remove page footers
    text = re.sub(r'(?:December|January|February|March|April|May|June|July|August|September|October|November)\s+\d{4}\s*[•·]\s*American Psychologist\s*\d*', '', text)
    # Join hyphenated line breaks
    text = re.sub(r'-\s*\n\s*', '', text)
    # Collapse whitespace
    text = re.sub(r'\s+', ' ', text).strip()
    return text


def compare_texts(text_a: str, text_b: str) -> dict:
    """Compare two texts and return similarity metrics."""
    norm_a = normalize_text(text_a)
    norm_b = normalize_text(text_b)

    # Character-level similarity
    char_sim = difflib.SequenceMatcher(None, norm_a, norm_b).ratio()

    # Word-level diff
    words_a = norm_a.split()
    words_b = norm_b.split()
    word_sim = difflib.SequenceMatcher(None, words_a, words_b).ratio()

    # Count differences
    sm = difflib.SequenceMatcher(None, words_a, words_b)
    diffs = []
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op != 'equal':
            diffs.append({
                "op": op,
                "a": ' '.join(words_a[i1:i2])[:100],
                "b": ' '.join(words_b[j1:j2])[:100],
            })

    return {
        "char_similarity": round(char_sim, 4),
        "word_similarity": round(word_sim, 4),
        "chars_a": len(norm_a),
        "chars_b": len(norm_b),
        "char_diff_pct": round(abs(len(norm_a) - len(norm_b)) / max(len(norm_a), 1) * 100, 1),
        "word_diffs": len(diffs),
        "diffs_sample": diffs[:10],
    }


# ──────────────────────────────────────────────────────────────
# Benchmark runner
# ──────────────────────────────────────────────────────────────

def run_benchmark(image_path: str, host: str, models: list[str],
                  prompt: str, pdfkit_text: str | None = None) -> dict:
    """Run OCR benchmark on a single image across multiple models."""
    with open(image_path, "rb") as f:
        image_b64 = base64.b64encode(f.read()).decode()

    results = {}
    baseline_text = None

    # Run each model
    for model in models:
        print(f"  Testing {model}...", end=" ", flush=True, file=sys.stderr)

        if not check_model_available(host, model):
            print("SKIP (not available)", file=sys.stderr)
            results[model] = {"status": "skip", "reason": "not available"}
            continue

        text, elapsed = ollama_generate(host, model, prompt, image_b64)

        if text.startswith("ERROR:"):
            print(f"FAIL ({text[:50]})", file=sys.stderr)
            results[model] = {"status": "error", "error": text, "elapsed": elapsed}
            continue

        char_count = len(normalize_text(text))
        print(f"OK ({char_count} chars, {elapsed:.1f}s)", file=sys.stderr)

        result = {
            "status": "ok",
            "raw_chars": len(text),
            "normalized_chars": char_count,
            "elapsed_seconds": round(elapsed, 2),
            "raw_text": text,
        }

        # Use glm-ocr as baseline if available
        if model == "glm-ocr":
            baseline_text = text

        results[model] = result

    # Compare all models against baseline (glm-ocr) and pdfkit
    if baseline_text:
        for model, result in results.items():
            if result.get("status") != "ok" or model == "glm-ocr":
                continue
            result["vs_glmocr"] = compare_texts(baseline_text, result["raw_text"])

    if pdfkit_text:
        results["pdfkit"] = {
            "status": "ok",
            "raw_chars": len(pdfkit_text),
            "normalized_chars": len(normalize_text(pdfkit_text)),
            "elapsed_seconds": 0,
            "raw_text": pdfkit_text,
        }
        if baseline_text:
            results["pdfkit"]["vs_glmocr"] = compare_texts(baseline_text, pdfkit_text)

    return results


def print_report(all_results: dict, output_json: str | None = None):
    """Print human-readable benchmark report."""
    print()
    print("=" * 78)
    print("Ensemble OCR Benchmark Report")
    print("=" * 78)

    for page_key, results in all_results.items():
        print(f"\n{'─' * 78}")
        print(f"  {page_key}")
        print(f"{'─' * 78}")

        # Summary table
        print(f"\n  {'Model':<22} {'Chars':>6} {'Time':>7} {'vs GLM-OCR':>12} {'Word Diffs':>11}")
        print(f"  {'─'*22} {'─'*6} {'─'*7} {'─'*12} {'─'*11}")

        for model, result in sorted(results.items()):
            if result.get("status") != "ok":
                status = result.get("reason", result.get("error", "?"))[:30]
                print(f"  {model:<22} {'—':>6} {'—':>7} {status:>12}")
                continue

            chars = result["normalized_chars"]
            elapsed = result.get("elapsed_seconds", 0)
            time_str = f"{elapsed:.1f}s" if elapsed > 0 else "—"

            vs = result.get("vs_glmocr", {})
            sim = vs.get("word_similarity")
            sim_str = f"{sim*100:.1f}%" if sim is not None else "baseline"
            diffs = vs.get("word_diffs", "—")

            print(f"  {model:<22} {chars:>6} {time_str:>7} {sim_str:>12} {str(diffs):>11}")

        # Show notable diffs for non-glmocr models
        print()
        for model, result in results.items():
            vs = result.get("vs_glmocr", {})
            diffs = vs.get("diffs_sample", [])
            if not diffs or model == "glm-ocr":
                continue

            # Only show interesting diffs (not just whitespace/quote differences)
            interesting = [d for d in diffs if len(d["a"]) > 3 or len(d["b"]) > 3]
            if interesting:
                print(f"  {model} — notable diffs vs GLM-OCR:")
                for d in interesting[:5]:
                    print(f"    [{d['op']}] GLM: '{d['a'][:60]}' → '{d['b'][:60]}'")
                print()

    print("=" * 78)

    # Quality ranking
    print("\n  Quality Ranking (by word similarity to GLM-OCR baseline):")
    all_scores = []
    for page_key, results in all_results.items():
        for model, result in results.items():
            vs = result.get("vs_glmocr", {})
            sim = vs.get("word_similarity")
            if sim is not None:
                all_scores.append((model, sim, result.get("elapsed_seconds", 0)))

    if all_scores:
        # Average across pages
        model_avg = {}
        for model, sim, elapsed in all_scores:
            if model not in model_avg:
                model_avg[model] = {"sims": [], "times": []}
            model_avg[model]["sims"].append(sim)
            model_avg[model]["times"].append(elapsed)

        ranked = sorted(model_avg.items(),
                       key=lambda x: sum(x[1]["sims"])/len(x[1]["sims"]),
                       reverse=True)

        print(f"\n  {'Rank':<6} {'Model':<22} {'Avg Similarity':>15} {'Avg Time':>10}")
        print(f"  {'─'*6} {'─'*22} {'─'*15} {'─'*10}")
        for i, (model, data) in enumerate(ranked, 1):
            avg_sim = sum(data["sims"]) / len(data["sims"])
            avg_time = sum(data["times"]) / len(data["times"])
            marker = " ★" if avg_sim >= 0.95 else " ✓" if avg_sim >= 0.85 else " ✗"
            print(f"  {i:<6} {model:<22} {avg_sim*100:>14.1f}% {avg_time:>9.1f}s{marker}")

    print()

    # Save JSON if requested
    if output_json:
        # Remove raw_text from JSON output to keep it small
        clean = {}
        for page_key, results in all_results.items():
            clean[page_key] = {}
            for model, result in results.items():
                r = {k: v for k, v in result.items() if k != "raw_text"}
                clean[page_key][model] = r

        with open(output_json, "w") as f:
            json.dump(clean, f, indent=2, ensure_ascii=False)
        print(f"  JSON report saved to: {output_json}")


# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Ensemble OCR Benchmark")
    parser.add_argument("--pdf", help="PDF 檔案路徑")
    parser.add_argument("--pages", help="頁碼（逗號分隔，如 3,4,8）")
    parser.add_argument("--images", help="已渲染的 PNG 路徑（逗號分隔）")
    parser.add_argument("--host", default=DEFAULT_OLLAMA_HOST, help=f"Ollama host (default: {DEFAULT_OLLAMA_HOST})")
    parser.add_argument("--models", help="只測特定模型（逗號分隔）")
    parser.add_argument("--prompt", default=DEFAULT_PROMPT, help="OCR prompt")
    parser.add_argument("--json", action="store_true", help="輸出 JSON")
    parser.add_argument("-o", "--output", help="JSON 輸出路徑")
    parser.add_argument("--dpi", type=int, default=200, help="PDF 渲染 DPI")
    parser.add_argument("--timeout", type=int, default=300, help="每個模型的超時秒數")
    args = parser.parse_args()

    if not args.pdf and not args.images:
        parser.error("需要 --pdf 或 --images")

    # Determine which models to test
    if args.models:
        models = args.models.split(",")
    else:
        models = list(OLLAMA_MODELS.keys())

    # Prepare images
    page_images = {}  # {label: image_path}
    pdfkit_texts = {}

    if args.pdf:
        if not args.pages:
            parser.error("使用 --pdf 時需要 --pages")

        pages = [int(p.strip()) for p in args.pages.split(",")]
        print(f"Rendering {len(pages)} pages from {args.pdf}...", file=sys.stderr)
        page_images = {f"Page {pg}": path
                      for pg, path in render_pdf_pages(args.pdf, pages, args.dpi).items()}
        pdfkit_texts = {f"Page {pg}": text
                       for pg, text in extract_pdfkit_text(args.pdf, pages).items()}

    if args.images:
        for img_path in args.images.split(","):
            img_path = img_path.strip()
            label = Path(img_path).stem
            page_images[label] = img_path

    # Run benchmarks
    all_results = {}
    for label, image_path in page_images.items():
        print(f"\n{'='*60}", file=sys.stderr)
        print(f"  {label}: {image_path}", file=sys.stderr)
        print(f"{'='*60}", file=sys.stderr)

        pdfkit = pdfkit_texts.get(label)
        results = run_benchmark(image_path, args.host, models, args.prompt, pdfkit)
        all_results[label] = results

    # Output
    output_path = args.output if args.json or args.output else None
    print_report(all_results, output_path)


if __name__ == "__main__":
    main()
