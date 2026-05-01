## Why

Agent-driven Word editing currently spans multiple mental models: `macdoc convert --to docx` creates converted documents, `word-builder-swift` can build new documents from Swift code, and `che-word-mcp` exposes lower-level mutation tools. Issue #92 needs a first-class `macdoc docx` workflow so agents can build, patch, apply, plan, verify, and diff `.docx` edits from a stable manifest contract instead of choosing between a separate `dxedit` binary and ad-hoc MCP calls.

## What Changes

- Add an integrated `macdoc docx` command namespace for deterministic Word document workflows.
- Define JSON-first Codable manifests for three workflow families:
  - build: create a new `.docx` from declarative sections, paragraphs, tables, images, and equations using the `word-builder-swift` model where applicable.
  - patch: fill or replace placeholders in a template `.docx` without treating the document as a blank build.
  - apply: mutate an existing `.docx` through ordered manifest steps and write a separate output document by default.
- Add companion planning and validation commands under the same namespace:
  - plan: parse the manifest and source document, resolve anchors/placeholders, and print the operations that would run.
  - verify: read back the output document and enforce manifest-declared checks.
  - diff: compare two `.docx` files at a Word-aware structural/text level suitable for CLI review.
- Keep manifest decoding, planning, execution, verification, and diffing in an importable Swift library target; keep `MacDocCLI` as the thin command layer.
- Treat a standalone `dxedit` executable as a future compatibility wrapper, not the Phase 1 product surface.

## Non-Goals

- No standalone public `dxedit` binary in Phase 1.
- No YAML manifest dependency in Phase 1; JSON is the required input format.
- No private thesis, manuscript, or advisor-review documents committed as fixtures.
- No attempt to make `macdoc docx` replace `che-word-mcp` session tools, autosave semantics, or interactive MCP editing workflows.
- No visual Microsoft Word rendering verification in Phase 1; verification is based on OOXML readback and structural assertions.

## Capabilities

### New Capabilities

- `docx-workflow-cli`: The integrated `macdoc docx` command namespace, manifest contract, library/CLI boundary, dry-run planning, execution, verification, and structural diff behaviour.

### Modified Capabilities

(none)

## Impact

- Affected specs: docx-workflow-cli
- Affected code:
  - New: Sources/DocxWorkflowLib/
  - New: Tests/DocxWorkflowLibTests/
  - New: Sources/MacDocCLI/MacDoc+Docx.swift
  - New: Tests/MacDocCLITests/DocxWorkflowCommandTests.swift
  - Modified: Package.swift
  - Modified: Sources/MacDocCLI/MacDoc.swift
  - Modified: README.md
  - Modified: CONVERSIONS.md
- Related dependencies and systems:
  - Uses existing `word-builder-swift` for new document build semantics where it already covers the requested document model.
  - Uses existing OOXML/Word packages for readback, mutation, and preservation instead of inventing a second `.docx` engine inside the CLI target.
  - Tracks GitHub issue #92.
