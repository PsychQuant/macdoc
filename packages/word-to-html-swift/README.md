# WordToHTMLSwift

Direct Word (.docx) → HTML converter for macdoc.

## Features

- Streaming `DocumentConverter` API
- Semantic HTML for headings, paragraphs, lists, tables, links, images, code blocks, and blockquotes
- HTML comment frontmatter option
- Footnote / endnote emission
- URL-based conversion from `.docx` input via `OOXMLSwift.DocxReader`

## Usage

```swift
import DocConverterSwift
import WordToHTMLSwift

let converter = WordHTMLConverter()
let html = try converter.convertToString(input: inputURL)
```

## Design

- Layer 3 converter package
- Depends only on `doc-converter-swift` + `ooxml-swift`
- No converter-to-converter imports
- Emits HTML directly instead of routing through Markdown
