# HTMLToMDSwift

Native macOS HTML → Markdown converter written in Swift.
Streaming conversion, no Markdown AST.

## Architecture

- **Layer 3 converter** in the macdoc ecosystem
- Implements `DocumentConverter` from `common-converter-swift`
- Uses `markdown-swift` for Markdown-safe formatting
- Uses `SwiftSoup` for HTML parsing

## Current coverage

### Block elements
- `h1` ... `h6`
- `p`
- `ul` / `ol` / `li`
- `blockquote`
- `pre > code`
- `hr`
- `table`
- wrapper blocks like `div`, `section`, `article`

### Inline elements
- `strong`, `b`
- `em`, `i`
- `del`, `s`, `strike`
- `code`
- `a[href]`
- `img[src]`
- `br`
- optional raw HTML preservation for `u`, `sup`, `sub`, `mark`

## Usage

```swift
import HTMLToMDSwift
import CommonConverterSwift

let converter = HTMLConverter()
let markdown = try converter.convertToString(input: htmlURL)
```

## Design notes

The parser necessarily builds an HTML DOM through SwiftSoup, but Markdown output is emitted in document order and streamed through `StreamingOutput`. The converter does not build an intermediate Markdown tree.
