# macdoc Conversion Matrix

Status legend:
- **implemented** — merged / available in repo
- **active** — issue open and implementation in flight
- **planned** — queue item, no open issue yet
- **research** — needs protocol / package design before implementation

## Current matrix

| Source | Target | Package | Status | Notes |
|--------|--------|---------|--------|-------|
| Word (.docx) | Markdown | `word-to-md-swift` | implemented | Layer 3 converter |
| HTML | Markdown | `html-to-md-swift` | active | Issue #13, SwiftSoup-based streaming emitter |
| PDF | LaTeX | `pdf-to-latex-swift` | implemented | Phase 1 + Phase 2 pipeline |
| BibLaTeX (.bib) | APA HTML | `apa-bib-to-html-swift` | implemented | style-aware renderer |
| BibLaTeX (.bib) | APA Markdown | `apa-bib-to-md-swift` | implemented | style-aware renderer |
| BibLaTeX (.bib) | APA JSON | `apa-bib-to-json-swift` | implemented | pre-rendered HTML + anchors |
| PDF | Markdown | `pdf-to-md-swift` | planned | direct path, avoid hub loss through LaTeX |
| Markdown | HTML | `md-to-html-swift` | implemented | swift-markdown AST renderer + HTML streaming output |
| SRT | HTML | `srt-to-html-swift` | implemented | subtitle blocks emit as structured HTML with timestamp + text |
| Word (.docx) | HTML | `word-to-html-swift` | planned | direct path preserves Word semantics better than hub conversion |
| HTML | Word (.docx) | `html-to-word-swift` | planned | useful reverse path after `word-to-html-swift` |
| Markdown | Word (.docx) | `md-to-word-swift` | research | binary target + protocol shape need design |

## Priority Queue

| Priority | Converter | Status | Why now |
|---------:|-----------|--------|---------|
| P0 | `html-to-md-swift` | active (#13) | explicit future converter in `docs/modular-architecture.md`; fits existing `DocumentConverter` + `StreamingOutput` shape cleanly |
| P0 | `md-to-html-swift` | planned | reverse path auto-promoted after `html-to-md-swift` |
| P1 | `pdf-to-md-swift` | planned | direct markdown export is a natural companion to existing PDF parsing stack |
| P1 | `word-to-html-swift` | planned | direct conversion avoids Markdown hub loss for rich Word semantics |
| P2 | `html-to-word-swift` | planned | reverse path once Word↔HTML design stabilizes |
| P3 | `md-to-word-swift` | research | requires target-binary converter story beyond current text-streaming protocol |

## Rules

- Open **one issue per converter** before writing code.
- New forward converter implies the reverse path is reconsidered immediately; if the reverse path is text-targeted and architecturally straightforward, promote it to **P0**.
- Prefer direct source→target converters over hub-based routing.
- Keep Layer 3 packages independent: source format + target format + `doc-converter-swift`, no converter-to-converter imports.
