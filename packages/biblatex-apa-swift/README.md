# biblatex-apa-swift

Swift library for parsing, validating, and formatting BibLaTeX entries following APA 7th Edition conventions.

## Features

- **Parse** `.bib` files with full LaTeX-aware parsing (nested braces, `\"` diacriticals, comments)
- **Write** entries back with formatting preservation
- **Validate** entries against APA 7 field requirements (context-aware)
- **Auto-fix** entries to APA 7 format (8-phase rule engine)
- **Classify** entries into APA 7 manual sections (10.1–11.10)
- **Protect** proper nouns and acronyms with braces (~500 terms)
- **Normalize** dates, pages, editions, titles
- **Diff** against Zotero SQLite database (read-only)

## Usage

```swift
import BiblatexAPA

// Parse
let bibFile = try BibParser.parse(filePath: "references.bib")

// Validate
let issues = BibValidator.validate(bibFile.entries[0])

// Auto-fix
let fixed = APARuleEngine.fix(bibFile.entries[0])

// Write
let output = BibWriter.serialize(entries: bibFile.entries)

// Utilities
let normalized = APAUtilities.normalizeDate("2019-02-00")  // "2019-02"
let isSentence = APAUtilities.detectSentenceCase("A test of something")  // true
```

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kiki830621/biblatex-apa-swift.git", from: "1.0.0")
]
```

## Used By

- [che-biblatex-mcp](https://github.com/kiki830621/che-biblatex-mcp) — BibLaTeX MCP server
- [che-zotero-mcp](https://github.com/PsychQuant/che-zotero-mcp) — Zotero MCP server

## License

MIT
