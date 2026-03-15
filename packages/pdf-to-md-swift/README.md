# PDFToMDSwift

Direct PDF → Markdown converter for macdoc.

## Goals

- Stream Markdown output through `DocumentConverter`
- Preserve simple document structure without routing through LaTeX
- Recover common PDF shapes:
  - headings
  - paragraphs
  - bullet / numbered lists
  - page breaks

## Heuristics

`PDFKit` does not expose a full semantic tree for arbitrary PDFs, so this package uses lightweight layout heuristics:

1. extract page text with `PDFSelection.selectionsByLine()`
2. group adjacent lines into blocks using vertical gap thresholds
3. classify blocks as heading / list / paragraph
4. stream Markdown incrementally page by page

The implementation intentionally stays converter-local and does not import other Layer 3 converters.

## Usage

```swift
import PDFToMDSwift

let converter = PDFConverter()
let markdown = try converter.convertToString(input: pdfURL)
```

## CLI

In macdoc, this package backs:

```bash
macdoc pdf to-md input.pdf -o output.md
```
