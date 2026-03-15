# HTMLToWordSwift

Native macOS HTML → Word (.docx) converter written in Swift.

## Architecture

- **Layer 3 converter** in the macdoc ecosystem
- Parses HTML with **SwiftSoup**
- Builds `WordDocument` with **ooxml-swift**
- Conforms to `DocumentConverter` from **doc-converter-swift**
- Overrides `convertToFile` to emit a real `.docx` archive

## Current coverage

### Block elements
- `h1` ... `h6`
- `p`
- `ul` / `ol` / `li`
- `blockquote`
- `pre` / `code`
- `table`
- wrapper blocks like `div`, `section`, `article`

### Inline elements
- `strong`, `b`
- `em`, `i`
- `u`
- `del`, `s`, `strike`
- `sup`, `sub`
- `mark`
- `a[href]`
- `br`
- `img[alt]` placeholder text

## Usage

```swift
import HTMLToWordSwift

let converter = HTMLToWordConverter()
try converter.convertToFile(
    input: htmlURL,
    output: outputDocxURL
)
```

## Design notes

`DocumentConverter` is streaming-text-first, but `.docx` is a binary target. This package follows the same pattern as other binary-target converters:

- `convert(input:output:options:)` streams the generated `word/document.xml`
- `convertToFile(input:output:options:)` writes a complete `.docx` archive

That keeps protocol compatibility for inspection/tests while still producing a native Word document for real use.
