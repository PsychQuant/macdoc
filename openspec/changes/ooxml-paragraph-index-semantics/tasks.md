## 1. API Surface

- [ ] 1.1 Audit `WordDocument` integer mutators and list every body-child, top-level paragraph, and recursive paragraph index entry point.
- [ ] 1.2 Implement shared validation helpers for body child indexes and top-level paragraph indexes in `Document.swift`.
- [ ] 1.3 Implement explicit body-child APIs so Body-child mutation APIs expose body-child index semantics.
- [ ] 1.4 Implement explicit paragraph-index APIs so Top-level paragraph mutation APIs expose paragraph-index semantics.

## 2. Deprecation and Documentation

- [ ] 2.1 Apply the design decision Use explicit labels instead of changing same-signature semantics immediately by preserving existing ambiguous method behavior.
- [ ] 2.2 Apply the design decision Introduce body-child APIs and preserve ambiguous methods during one minor release by adding deprecation messages that name body-child replacements.
- [ ] 2.3 Apply the design decision Introduce paragraph-index APIs for paragraph-only operations by adding deprecation messages that name paragraph-index replacements.
- [ ] 2.4 Ensure Ambiguous legacy index APIs preserve behavior during deprecation with source-level warning tests.
- [ ] 2.5 Apply the design decision Document recursive paragraph reads as non-index-compatible by updating `getParagraphs()` documentation.
- [ ] 2.6 Ensure Recursive paragraph reads are not mutation indexes in public documentation and migration notes.

## 3. Tests and Downstream Migration

- [ ] 3.1 Add tests for body-child insert/update/delete behavior around tables and content controls.
- [ ] 3.2 Add tests for top-level paragraph mutation behavior around tables and nested paragraphs.
- [ ] 3.3 Add tests proving deprecated ambiguous APIs keep minor-release runtime behavior.
- [ ] 3.4 Update `che-word-mcp` callers to use explicit body-child or paragraph-index APIs.
- [ ] 3.5 Run full `swift test` in `packages/ooxml-swift` and the relevant `che-word-mcp` test suite.
