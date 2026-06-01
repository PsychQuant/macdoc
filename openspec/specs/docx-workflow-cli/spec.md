# docx-workflow-cli Specification

## Purpose

TBD - created by archiving change 'macdoc-docx-workflow-cli'. Update Purpose after archive.

## Requirements

### Requirement: Manifest is JSON-Codable in Phase 1

A docx workflow manifest SHALL be a JSON document decodable via Swift's `JSONDecoder` into a single root `Manifest` value whose type is `Codable`. The root document SHALL contain three top-level fields: `baseline` (relative or absolute file path string), `output` (relative or absolute file path string), and `steps` (ordered array of step objects). An optional fourth field `verify` (object containing post-condition assertions) MAY be present.

YAML manifest decoding SHALL NOT be required in Phase 1. A future capability change MAY add a YAML adapter that decodes via `Yams` into the same `Manifest` value without breaking JSON consumers.

#### Scenario: Decoding a minimal JSON manifest

- **WHEN** `JSONDecoder().decode(Manifest.self, from: data)` is called with a UTF-8 JSON document that has only `baseline`, `output`, and a non-empty `steps` array
- **THEN** decoding MUST succeed and produce a `Manifest` value whose `verify` field is `nil`

##### Example: Minimal manifest

- **GIVEN** the JSON document:
  ```json
  {
    "baseline": "archived/baseline.docx",
    "output": "docs/output.docx",
    "steps": [
      { "type": "insert_paragraph", "anchor": { "after_text": "Introduction" }, "content": "New paragraph body." }
    ]
  }
  ```
- **WHEN** `JSONDecoder().decode(Manifest.self, from: jsonData)` runs
- **THEN** the result has `baseline == "archived/baseline.docx"`, `output == "docs/output.docx"`, `steps.count == 1`, `verify == nil`

#### Scenario: Decoding fails for missing required fields

- **WHEN** a JSON manifest omits `baseline`, `output`, or `steps`
- **THEN** decoding MUST throw `DecodingError.keyNotFound` with the missing field name

#### Scenario: UTF-8 CJK anchor text decodes intact

- **GIVEN** a JSON manifest whose anchor text contains CJK characters (e.g., `"after_text": "前言"`)
- **WHEN** decoded
- **THEN** the resulting `Manifest.steps[0].anchor.afterText` value MUST equal `"前言"` byte-for-byte (no UTF-8 corruption)


<!-- @trace
source: macdoc-docx-workflow-cli
updated: 2026-06-01
code:
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - Package.swift
  - .remember/logs/autonomous/save-133659.log
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - .remember/logs/autonomous/save-132859.log
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - CLAUDE.md
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - Package.resolved
  - Sources/MacDocCLI/MacDoc.swift
-->

---
### Requirement: Anchor resolution semantics are deterministic

Each step's `anchor` field SHALL resolve via exact-substring search against paragraph text in the baseline document. Resolution outcomes SHALL be exactly one of three: exact-one-match (succeeds), zero-match (fails with `AnchorError.notFound`), or multi-match (fails with `AnchorError.ambiguous`). First-match-wins fallback SHALL NOT be available.

The `paragraph_index` anchor variant SHALL bypass text matching and resolve directly to the paragraph at the given zero-based index in document body order. If the index is out of range, resolution SHALL fail with `AnchorError.indexOutOfRange`.

#### Scenario: Exact-one substring match resolves successfully

- **GIVEN** a baseline document with paragraphs whose text values are `["Introduction", "Background", "Methods"]`
- **WHEN** a step's anchor is `{ "after_text": "Background" }` resolving against this baseline
- **THEN** the AnchorResolver MUST return the ParagraphRef for the paragraph whose text is `"Background"`

#### Scenario: Multi-match fails with explicit error

- **GIVEN** a baseline document with paragraphs whose text values are `["Section A", "Section B", "Section A"]`
- **WHEN** a step's anchor is `{ "after_text": "Section A" }` resolving against this baseline
- **THEN** the AnchorResolver MUST throw `AnchorError.ambiguous(anchor: "Section A", step: ..., matches: [0, 2])`

##### Example: Multi-match error message

- **GIVEN** baseline paragraphs at indices `[0]="Section A"`, `[2]="Section A"`
- **WHEN** anchor `{ "after_text": "Section A" }` is resolved
- **THEN** the thrown `AnchorError.ambiguous` MUST include `matches: [0, 2]` so the executor can format the error as `"anchor 'Section A' matched 2 paragraphs at indices [0, 2]; lengthen the anchor substring to disambiguate"`

#### Scenario: Zero-match fails with explicit error

- **GIVEN** a baseline document whose paragraph text does not contain the substring `"NonExistent"`
- **WHEN** a step's anchor is `{ "after_text": "NonExistent" }`
- **THEN** the AnchorResolver MUST throw `AnchorError.notFound(anchor: "NonExistent", step: ..., scanned: <paragraph count>)`

#### Scenario: paragraph_index resolves directly

- **GIVEN** a baseline document with 5 paragraphs
- **WHEN** a step's anchor is `{ "paragraph_index": 2 }`
- **THEN** the AnchorResolver MUST return the ParagraphRef for the 3rd paragraph (zero-based) without scanning any paragraph text

#### Scenario: paragraph_index out of range fails

- **GIVEN** a baseline document with 3 paragraphs
- **WHEN** a step's anchor is `{ "paragraph_index": 5 }`
- **THEN** the AnchorResolver MUST throw `AnchorError.indexOutOfRange(requested: 5, available: 3)`


<!-- @trace
source: macdoc-docx-workflow-cli
updated: 2026-06-01
code:
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - Package.swift
  - .remember/logs/autonomous/save-133659.log
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - .remember/logs/autonomous/save-132859.log
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - CLAUDE.md
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - Package.resolved
  - Sources/MacDocCLI/MacDoc.swift
-->

---
### Requirement: Executor applies steps in manifest order

The Executor SHALL apply manifest steps in the order they appear in the `steps` array. Each step's anchor resolution and Edit construction SHALL happen immediately before that step's Edit is applied; anchor resolution SHALL NOT be done up-front in a separate pass before any Edits are applied. This rule ensures that step N can reference content inserted by step N-1.

If any step's anchor resolution or Edit application throws, the Executor SHALL stop processing immediately and propagate the error to the caller. No partial output SHALL be written to the `output` file.

#### Scenario: Sequential anchor resolution sees prior step output

- **GIVEN** a baseline with one paragraph `"Existing"` and a manifest with steps `[{ insert_paragraph after_text: "Existing", content: "Inserted" }, { insert_paragraph after_text: "Inserted", content: "Second" }]`
- **WHEN** the Executor processes the manifest
- **THEN** step 2's anchor `"Inserted"` MUST resolve against the post-step-1 document state (not the original baseline) and produce a final body of `["Existing", "Inserted", "Second"]`

#### Scenario: Anchor failure aborts execution before write

- **GIVEN** a manifest with 3 steps where step 2's anchor cannot be resolved
- **WHEN** the Executor runs
- **THEN** step 3 MUST NOT execute, the `output` file MUST NOT be written, and the `AnchorError` from step 2 MUST be propagated unchanged


<!-- @trace
source: macdoc-docx-workflow-cli
updated: 2026-06-01
code:
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - Package.swift
  - .remember/logs/autonomous/save-133659.log
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - .remember/logs/autonomous/save-132859.log
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - CLAUDE.md
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - Package.resolved
  - Sources/MacDocCLI/MacDoc.swift
-->

---
### Requirement: Phase-2c-pending step types compile but warn at runtime

Step types whose backing `OOXMLEdit` / `WordEdit` Reducer cases have not yet shipped (per ooxml-swift#71 Phase 2c follow-up) SHALL be accepted by the manifest decoder and SHALL be represented as concrete step type values. When the Executor encounters such a step at runtime, it SHALL emit a warning to stderr in the form `"warn: step type '<step_type>' has no Reducer support yet (tracker: ooxml-swift#71); skipping"` and continue to the next step. The exit code SHALL NOT be set to non-zero solely because of skipped pending steps.

The full Phase-2c-pending step type list SHALL include: `insert_image`, `insert_table`, `set_cell_text`, `insert_equation`. This list SHALL be updated by a future change when each step type's Reducer case ships.

#### Scenario: insert_image step is decoded but skipped with warning

- **GIVEN** a manifest containing `{ "type": "insert_image", "path": "fig.png", "anchor": { "after_text": "Figure 1" } }`
- **WHEN** the Executor processes this step
- **THEN** stderr MUST receive a warning line containing the substring `insert_image` AND `ooxml-swift#71`
- **AND** the step's effect on the output document MUST be zero (no `<a:blip>` reference added)
- **AND** the Executor MUST continue to subsequent steps

#### Scenario: Manifest with only Phase-2c-pending steps still produces valid output

- **GIVEN** a baseline document and a manifest whose `steps` array contains only `insert_image` and `insert_table` steps
- **WHEN** the Executor runs
- **THEN** the output document MUST be byte-equivalent (post-c14n) to the baseline document
- **AND** stderr MUST contain warnings for each skipped step
- **AND** the exit code MUST be 0


<!-- @trace
source: macdoc-docx-workflow-cli
updated: 2026-06-01
code:
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - Package.swift
  - .remember/logs/autonomous/save-133659.log
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - .remember/logs/autonomous/save-132859.log
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - CLAUDE.md
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - Package.resolved
  - Sources/MacDocCLI/MacDoc.swift
-->

---
### Requirement: Verify post-condition modes assert document invariants

When a manifest's optional `verify` object is present, the Executor SHALL evaluate each present post-condition after applying all steps. Failure of any post-condition SHALL produce a `VerifyError` containing the failed condition name and observed value, and SHALL cause a non-zero exit code from the `apply` and `verify` subcommands.

Phase 1 post-condition modes SHALL include:

- `expected_images: Int` — number of unique `<a:blip>` references in the output document body
- `expected_paragraphs_min: Int` — minimum paragraph count in document body (inclusive lower bound)
- `expected_bookmarks_min: Int` — minimum bookmark count (inclusive lower bound)
- `libxml2_valid: Bool` — whether the OOXML parts parse without error (Phase 1 uses Foundation `XMLParser`; a future change MAY swap to native libxml2)
- `byte_preserved_parts: [String]` — glob-pattern list of OOXML container parts whose post-c14n bytes MUST be byte-equal between baseline and output

#### Scenario: expected_images post-condition succeeds when count matches

- **GIVEN** a baseline with 5 images, a manifest that adds 0 images, and verify `{ "expected_images": 5 }`
- **WHEN** the Executor verifies
- **THEN** the verify step MUST pass with no error

#### Scenario: byte_preserved_parts fails when header changes

- **GIVEN** a manifest with verify `{ "byte_preserved_parts": ["word/header*.xml"] }` and steps that modify a body paragraph (no header change intended)
- **WHEN** the Executor verifies and the post-c14n bytes of `word/header1.xml` are byte-equal between baseline and output
- **THEN** verify MUST pass

##### Example: byte_preserved_parts failure surface

- **GIVEN** baseline contains `word/header1.xml` and `word/header2.xml`, manifest has `byte_preserved_parts: ["word/header*.xml"]`
- **WHEN** the executor's apply phase inadvertently modifies `word/header2.xml` (e.g., by drifting timestamps in the headers ZIP entry)
- **THEN** the `VerifyError` MUST name `word/header2.xml` as the violating part AND include a diff summary `"baseline: 1024 bytes, output: 1028 bytes, post-c14n bytes differ at offset N"`

#### Scenario: libxml2_valid passes when output XML parses cleanly

- **GIVEN** a verify `{ "libxml2_valid": true }`
- **WHEN** the output document's `word/document.xml` parses without error via Foundation `XMLParser`
- **THEN** verify MUST pass

#### Scenario: Verify failure produces non-zero exit on the apply subcommand

- **GIVEN** a manifest with verify `{ "expected_images": 5 }` against a baseline with 3 images and steps that add 0 images
- **WHEN** `macdoc docx apply` is invoked
- **THEN** the verify post-condition MUST fail with `VerifyError.imageCountMismatch(expected: 5, observed: 3)`
- **AND** the CLI exit code MUST be non-zero


<!-- @trace
source: macdoc-docx-workflow-cli
updated: 2026-06-01
code:
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - Package.swift
  - .remember/logs/autonomous/save-133659.log
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - .remember/logs/autonomous/save-132859.log
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - CLAUDE.md
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - Package.resolved
  - Sources/MacDocCLI/MacDoc.swift
-->

---
### Requirement: macdoc docx subcommand exposes four operations

The `macdoc docx` top-level subcommand SHALL be registered as the 6th subcommand on `MacDocCLI` and SHALL declare exactly four inner subcommands: `apply`, `plan`, `verify`, `diff`. The `Docx` subcommand file SHALL be `Sources/MacDocCLI/MacDoc+Docx.swift` and SHALL delegate all business logic to `DocxWorkflowLib`; the file SHALL NOT contain manifest decoding, anchor resolution, Edit construction, or verification logic directly.

Inner subcommand surfaces SHALL be:

- `macdoc docx apply <manifest.json> --in <baseline.docx> --out <output.docx>` — runs the full executor + verify chain.
- `macdoc docx plan <manifest.json> --in <baseline.docx>` — resolves anchors and prints planned Edit sequence; no `output` write.
- `macdoc docx verify --in <baseline.docx> --out <output.docx> --manifest <manifest.json>` — runs only the verify chain against two existing documents (skip apply).
- `macdoc docx diff <a.docx> <b.docx>` — prints structural differences between two documents using foundation diff machinery.

#### Scenario: macdoc docx --help lists four inner subcommands

- **WHEN** `macdoc docx --help` is run
- **THEN** stdout MUST list exactly the four subcommand names `apply`, `plan`, `verify`, `diff` (in any documented order)

#### Scenario: apply with valid manifest writes output and exits 0

- **GIVEN** a baseline.docx, a valid manifest.json with at least one runtime-functional step, and a writable output.docx path
- **WHEN** `macdoc docx apply manifest.json --in baseline.docx --out output.docx` is invoked
- **THEN** output.docx MUST be written, MUST be a valid OOXML container, AND the CLI exit code MUST be 0

#### Scenario: plan does not write output

- **GIVEN** a manifest with steps that would mutate the baseline
- **WHEN** `macdoc docx plan manifest.json --in baseline.docx` is invoked
- **THEN** no file MUST be written to the working directory
- **AND** stdout MUST contain a representation of the planned Edit sequence (one line per resolved step)


<!-- @trace
source: macdoc-docx-workflow-cli
updated: 2026-06-01
code:
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - Package.swift
  - .remember/logs/autonomous/save-133659.log
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - .remember/logs/autonomous/save-132859.log
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - CLAUDE.md
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - Package.resolved
  - Sources/MacDocCLI/MacDoc.swift
-->

---
### Requirement: DocxWorkflowLib library boundary is independently consumable

The Phase 1 implementation SHALL place all manifest decoding, anchor resolution, Edit construction, executor orchestration, and verification logic in a separate Swift package `packages/docx-workflow-swift/` exposing a single library product `DocxWorkflowLib`. The `MacDocCLI` Docx subcommand SHALL depend on this library via SwiftPM. The library product SHALL be importable by other Swift packages (e.g., che-word-mcp integration tests) without depending on `MacDocCLI`.

The library SHALL depend on `word-builder-swift` (which re-exports the foundation `OOXMLSwift` surface) and SHALL use `OOXMLSwift.WordDocument` as the runtime document handle for Phase 1 — this is forced by the v1.0.0 addressing gap (LensDocument's `inner: WordDocument` is private, so downstream consumers cannot extract paragraph `ElementID`s from a `LensDocument` value). It SHALL NOT introduce a parallel `WorkflowDocument` or similar handle type, and SHALL NOT duplicate the 5-method `LensDocument` surface.

A future word-builder-swift change exposing a public paragraph-iteration / ID-extraction surface MAY let a Phase 2 of DocxWorkflowLib use `LensDocument` as the primary handle while preserving the same caller-facing CLI behavior. This Phase 1 design is forward-compatible.

#### Scenario: DocxWorkflowLib can be imported without MacDocCLI

- **GIVEN** a third-party Swift package that adds `packages/docx-workflow-swift` as a path or url dependency
- **WHEN** the package writes `import DocxWorkflowLib` and references `Manifest`, `Executor`, `Verifier`, `AnchorError`, `VerifyError`
- **THEN** the types MUST resolve without requiring `import MacDocCLI`

#### Scenario: Library uses the foundation's WordDocument as the runtime handle

- **WHEN** the Executor's apply method runs internally
- **THEN** it MUST construct an `OOXMLSwift.WordDocument` via `OOXMLSwift.DocxReader.read(from: baselineURL, wireTreeBackedViews: true)`, fold the planned Edit sequence via the foundation's `WordDocument.apply(_:)` method, and write the result via `OOXMLSwift.DocxWriter.writeData(...)` to the output URL
- **AND** it MUST NOT define a parallel `WorkflowDocument` or similar handle type
- **AND** it MUST NOT duplicate `LensDocument`'s 5-method surface; consumers wanting a `LensDocument` handle can construct one from the emitted output file via `LensDocument(reading: outputURL)`

##### Implementation note: LensDocument addressing gap (Phase 1)

word-builder-swift v1.0.0's `LensDocument` hides its `inner: OOXMLSwift.WordDocument` behind a private field (per `word-builder-swift-lens-migration` design.md Decision 2). The Phase 1 DocxWorkflowLib Executor would need to extract paragraph `ElementID`s from the document state to resolve text anchors against an evolving body (per the "Executor applies steps in manifest order" Requirement). Because `LensDocument` exposes no such accessor, Phase 1 goes directly through `OOXMLSwift.WordDocument`. The user-visible CLI contract is unchanged — both paths produce a valid `.docx` at the output URL — but the internal handle is `WordDocument`, not `LensDocument`. A future word-builder-swift change (tracker to be filed in a separate Spectra) MAY add a public `paragraphRefs()` or equivalent surface that lets Phase 2 of DocxWorkflowLib use `LensDocument` directly.

<!-- @trace
source: macdoc-docx-workflow-cli
updated: 2026-06-01
code:
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - Package.swift
  - .remember/logs/autonomous/save-133659.log
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - .remember/logs/autonomous/save-132859.log
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - CLAUDE.md
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - Package.resolved
  - Sources/MacDocCLI/MacDoc.swift
-->