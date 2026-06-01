## ADDED Requirements

### Requirement: Layer 3 consumers compose multi-step authoring flows via the re-exported Edit surface

`word-builder-swift` SHALL support the Layer 3 consumer pattern (per `ooxml-edit-isomorphism-foundation` ADR-009) wherein a consumer package depends on `WordBuilderSwift`, uses a single `import WordBuilderSwift` to access `LensDocument`, `Edit`, `OOXMLEdit`, `WordEdit`, `WordRange`, `ParagraphRef`, `EditError`, plus the foundation types (`WordDocument`, `DocxReader`, `DocxWriter`), and composes multi-step authoring workflows by chaining `LensDocument.apply([Edit])` calls. The `word-builder-swift` capability SHALL NOT add any new public API to support this pattern; the existing five-method `LensDocument` surface plus the `@_exported import OOXMLSwift` re-export already cover it. This requirement codifies the contract so that downstream Layer 3/4 capabilities (e.g., `docx-workflow-cli`, future R-emitter capabilities) can cite a normative anchor when describing their dependency.

#### Scenario: Layer 3 consumer reads, applies a sequence, and emits

- **GIVEN** a third-party Swift package that depends on `word-builder-swift` v1.0.0 and writes `import WordBuilderSwift`
- **WHEN** the consumer code constructs a sequence of `WordEdit` / `OOXMLEdit` cases and calls `try LensDocument(reading: url).apply(edits as [any Edit]).emit(to: outURL)` where `edits` is a `[any Edit]`
- **THEN** the call MUST type-check and execute against the v1.0.0 surface without requiring `import OOXMLSwift` separately, AND the resulting `.docx` MUST contain the cumulative effect of all runtime-functional Edits applied in order

#### Scenario: Layer 3 consumer surfaces Phase 2c gaps via the same try? idiom as the v1.0.0 examples

- **GIVEN** a Layer 3 consumer (e.g., `DocxWorkflowLib`) that needs to apply an Edit case whose Reducer is not yet shipped (per ooxml-swift#71 Phase 2c follow-up)
- **WHEN** the consumer wraps that Edit in `try?` with a comment naming the tracker (per the `examples/03-table-3x3.swift` precedent in v1.0.0)
- **THEN** the consumer code MUST compile against the v1.0.0 surface and MUST NOT require any new API from `word-builder-swift`; the gap-handling pattern is consumer-side, not library-side

##### Example: Layer 3 try? idiom for pending Reducer cases

- **GIVEN** a consumer that wants to apply a hypothetical `OOXMLEdit.insertTable(at: anchor, rows: 3, columns: 3)` whose Reducer is pending
- **WHEN** the consumer writes
  ```swift
  let withTable = try? doc.apply(OOXMLEdit.insertTable(at: anchor, rows: 3, columns: 3))
  let final = withTable ?? doc
  ```
- **THEN** the code MUST type-check against v1.0.0, MUST execute without throwing at the `try?` site even when the Reducer case is unimplemented, and the consumer's downstream code MUST receive a non-nil document via the nil-coalescing operator
