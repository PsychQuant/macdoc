# md-to-word-swift

Direct Markdown → Word (`.docx`) converter for macdoc.

## Design

- **Source parser:** `swift-markdown`
- **Target model:** `OOXMLSwift.WordDocument`
- **Archive writer:** `OOXMLSwift.DocxWriter`
- **Protocol surface:** `DocConverterSwift.DocumentConverter`

This package keeps the conversion path direct: Markdown AST is mapped into native Word structures instead of routing through HTML.

## Supported features

- headings → Word heading styles
- paragraphs + inline formatting
- ordered / unordered lists
- tables
- hyperlinks
- fenced code blocks (monospace + shaded paragraphs)
- YAML frontmatter → Word document properties

## Usage

```swift
import Foundation
import MDToWordSwift

let converter = MarkdownToWordConverter()
try converter.convertToFile(
    input: URL(fileURLWithPath: "notes.md"),
    output: URL(fileURLWithPath: "notes.docx")
)
```

## Testing

```bash
cd packages/md-to-word-swift
swift test
```
