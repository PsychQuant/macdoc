## ADDED Requirements

### Requirement: Operation log to Swift script export

The library SHALL provide `ScriptExporter.exportSwift(log:)` that emits a runnable Swift source file whose execution against an empty `OperationLog` reproduces the input log byte-equal.

#### Scenario: Exported script is runnable Swift

- **GIVEN** an `OperationLog` containing operations
- **WHEN** `exportSwift(log:)` runs
- **THEN** the returned String compiles as a Swift source file with `import OOXMLSwift` and a top-level `func buildDocument() -> Document` that performs the operations

#### Scenario: Round-trip log → script → log preserves operations

- **GIVEN** an input `OperationLog L`
- **WHEN** `L'` is reconstructed from `ScriptImporter.parse(ScriptExporter.exportSwift(log: L))`
- **THEN** every operation in `L'` matches the corresponding operation in `L` for `op_type`, `payload`, and `source` fields (`op_id` and `timestamp` may differ since they regenerate)

### Requirement: Swift script to operation log import

The library SHALL provide `ScriptImporter.parse(source:)` that reads a Swift source string conforming to the exporter's grammar and returns the equivalent `OperationLog`.

#### Scenario: Hand-written script imports successfully

- **GIVEN** a Swift script:
  ```swift
  import OOXMLSwift
  func buildDocument() -> Document {
      let doc = Document.create()
      doc.body.appendParagraph("Title", style: "Heading1")
      doc.body.appendParagraph("Body intro")
      doc.body.appendTable(rows: 3, cols: 4)
      return doc
  }
  ```
- **WHEN** `ScriptImporter.parse(source:)` runs
- **THEN** the returned log contains operations equivalent to `[CreateDocument, InsertParagraphAfter("Title", "Heading1"), InsertParagraphAfter("Body intro"), InsertTable(rows:3, cols:4)]`

#### Scenario: Malformed script raises structured error

- **WHEN** the import receives a Swift source that does not conform to the exporter grammar (e.g., contains arbitrary side-effecting code)
- **THEN** `ScriptImporter.parse` throws `TranscodeError.unsupportedSyntax(line:column:reason:)` with a precise location

### Requirement: Build a docx end-to-end from a Swift script

The library SHALL support construction of a complete docx file from a Swift script with no prior docx as input. `Document.create()` SHALL initialize an empty document; subsequent typed operations populate the document; `Document.save(to:)` writes the resulting docx.

#### Scenario: Empty document save produces valid docx

- **WHEN** `Document.create().save(to: url)` runs
- **THEN** the resulting `url` is a valid docx readable by Word: `[Content_Types].xml`, `_rels/.rels`, `word/_rels/document.xml.rels`, `word/document.xml` are all present and well-formed

#### Scenario: Script-built docx round-trips byte-equal

- **GIVEN** a Swift script that builds a docx and saves to `script_output.docx`
- **WHEN** the docx is opened in Word, saved without edits, and re-read by ooxml-swift
- **THEN** the re-read content matches the original script's output for every typed view (no Word-side rejection, no schema warnings)

### Requirement: Stable script formatting for diff readability

The exported Swift script SHALL use a stable, deterministic formatting (consistent indentation, predictable line ordering, deterministic comment placement) so that two logs differing by one operation produce scripts that differ by one localized hunk in `git diff`.

#### Scenario: Adding one operation produces one-hunk diff

- **GIVEN** logs `L1` of length N and `L2 = L1 + [op_new]` of length N+1
- **WHEN** `exportSwift(L1)` and `exportSwift(L2)` are diffed
- **THEN** the diff contains exactly one inserted block corresponding to `op_new`; no other lines change

### Requirement: Script export covers all operation types in the log

The exporter SHALL produce a Swift representation for every operation type defined by `ooxml-operation-log`. When an unknown future op_type is encountered, the exporter SHALL emit a comment marker and the raw JSON payload, preserving forward compatibility.

#### Scenario: Unknown op_type round-trips via raw form

- **GIVEN** a log containing an operation with `op_type: "future_op_v2"` not recognized by the current exporter
- **WHEN** `exportSwift(log:)` runs and the result is parsed back via `ScriptImporter.parse`
- **THEN** the unknown operation reappears in the resulting log byte-equal in its `payload` field
