# macdoc Conversion Matrix

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | **implemented** — merged and available |
| 🔄 | **active** — issue open, implementation in flight |
| 📋 | **planned** — queue item, no open issue yet |
| 🔬 | **research** — needs protocol/package design first |
| · | not planned |

## Cross Matrix (Source → Target)

|  → Target | Markdown | HTML | Word (.docx) | LaTeX | JSON | PDF | SRT |
|----------:|:--------:|:----:|:------------:|:-----:|:----:|:---:|:---:|
| **Markdown** | — | ✅ `md-to-html` | 🔄 `md-to-word` | · | · | · | · |
| **HTML** | ✅ `html-to-md` | — | 📋 `html-to-word` | · | · | · | · |
| **Word (.docx)** | ✅ `word-to-md` | 📋 `word-to-html` | — | · | · | · | · |
| **PDF** | 📋 `pdf-to-md` | · | · | ✅ `pdf-to-latex` | · | — | · |
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
| PDF → Markdown | `pdf-to-md-swift` | 📋 planned | direct path, avoid hub loss through LaTeX |
| Word → HTML | `word-to-html-swift` | 📋 planned | direct path preserves Word semantics |
| HTML → Word | `html-to-word-swift` | 📋 planned | reverse path after word-to-html |
| Markdown → Word | `md-to-word-swift` | 🔄 active | direct Markdown AST → OOXML writer using `swift-markdown` + `ooxml-swift` |

## Priority Queue

| Priority | Converter | Status | Why now |
|---------:|-----------|--------|---------|
| P1 | `pdf-to-md-swift` | 📋 planned | direct markdown export is a natural companion to existing PDF parsing stack |
| P1 | `word-to-html-swift` | 📋 planned | direct conversion avoids Markdown hub loss for rich Word semantics |
| P2 | `html-to-word-swift` | 📋 planned | reverse path once Word↔HTML design stabilizes |
| P0 | `md-to-word-swift` | 🔄 active | reverse path for the existing Word ↔ Markdown pair, now direct via OOXML writer |

## Rules

- Open **one issue per converter** before writing code.
- New forward converter implies the reverse path is reconsidered immediately; if the reverse path is text-targeted and architecturally straightforward, promote it to **P0**.
- Prefer direct source→target converters over hub-based routing.
- Keep Layer 3 packages independent: source format + target format + `common-converter-swift`, no converter-to-converter imports.
