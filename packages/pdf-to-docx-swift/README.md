# pdf-to-docx-swift

Direct PDF → Word (`.docx`) converter for macdoc.

## What it does

- reads PDF files with `PDFKit`
- maps detected structure into `OOXMLSwift` `WordDocument`
- writes full `.docx` archives via `DocxWriter`
- exposes a streaming `DocumentConverter` surface that emits `word/document.xml`

## Current structure detection

- document metadata (`Title`, `Author`, `Subject`, `Keywords`, creation/modification date)
- headings (first-page title + short heading-like lines)
- paragraphs
- bullet / ordered lists
- simple tables detected from tabs / multi-space aligned columns / pipe rows
- page breaks between PDF pages

## Usage

```swift
import PDFToDOCXSwift

let converter = PDFToDOCXConverter()
try converter.convertToFile(
    input: URL(fileURLWithPath: "paper.pdf"),
    output: URL(fileURLWithPath: "paper.docx")
)
```

## CLI

After wiring into `macdoc`:

```bash
macdoc pdf to-docx input.pdf -o output.docx
# or let macdoc choose input.docx next to the source PDF
macdoc pdf to-docx input.pdf
```

## Testing

```bash
cd packages/pdf-to-docx-swift
swift build
swift test
```

## Notes

This package prioritizes editable Word output from native PDF text extraction. It does not yet reconstruct embedded images or advanced PDF layout semantics.
