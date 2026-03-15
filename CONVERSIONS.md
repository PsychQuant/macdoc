# macdoc Conversion Matrix

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | **implemented** — merged and available |
| · | not planned |

## Cross Matrix (Source → Target)

|  → Target | Markdown | HTML | Word (.docx) | LaTeX | JSON | PDF | SRT |
|----------:|:--------:|:----:|:------------:|:-----:|:----:|:---:|:---:|
| **Markdown** | — | ✅ `md-to-html` | ✅ `md-to-word` | · | · | · | · |
| **HTML** | ✅ `html-to-md` | — | ✅ `html-to-word` | · | · | · | · |
| **Word (.docx)** | ✅ `word-to-md` | ✅ `word-to-html` | — | · | · | · | · |
| **PDF** | ✅ `pdf-to-md` | · | ✅ `pdf-to-docx` | ✅ `pdf-to-latex` | · | — | · |
| **BibLaTeX (.bib)** | ✅ `bib-apa-to-md` | ✅ `bib-apa-to-html` | · | · | ✅ `bib-apa-to-json` | · | · |
| **SRT** | · | ✅ `srt-to-html` | · | · | · | · | — |

## Converter Details

| Source → Target | Package | Status | Notes |
|-----------------|---------|--------|-------|
| Word → Markdown | `word-to-md-swift` | ✅ implemented | Layer 3 converter |
| HTML → Markdown | `html-to-md-swift` | ✅ implemented | SwiftSoup-based streaming emitter |
| Markdown → HTML | `md-to-html-swift` | ✅ implemented | swift-markdown AST renderer |
| SRT → HTML | `srt-to-html-swift` | ✅ implemented | structured HTML with timestamp + speaker detection |
| PDF → LaTeX | `pdf-to-latex-swift` | ✅ implemented | Phase 1 + Phase 2 pipeline |
| BibLaTeX → APA HTML | `bib-apa-to-html-swift` | ✅ implemented | style-aware renderer |
| BibLaTeX → APA Markdown | `bib-apa-to-md-swift` | ✅ implemented | style-aware renderer |
| BibLaTeX → APA JSON | `bib-apa-to-json-swift` | ✅ implemented | pre-rendered HTML + anchors |
| PDF → Markdown | `pdf-to-md-swift` | ✅ implemented | direct path via PDFKit, heading/list heuristics |
| Word → HTML | `word-to-html-swift` | ✅ implemented | direct path preserves Word semantics |
| HTML → Word | `html-to-word-swift` | ✅ implemented | SwiftSoup → OOXML writer |
| Markdown → Word | `md-to-word-swift` | ✅ implemented | swift-markdown AST → OOXML writer |
| PDF → DOCX | `pdf-to-docx-swift` | ✅ implemented | PDFKit text extraction → OOXML writer |

## Rules

- Open **one issue per converter** before writing code.
- New forward converter implies the reverse path is reconsidered immediately.
- Prefer direct source→target converters over hub-based routing.
- Keep Layer 3 packages independent: source format + target format + `common-converter-swift`, no converter-to-converter imports.
