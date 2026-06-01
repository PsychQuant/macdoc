## Why

Two real-world workflows hit the limits of going through `che-word-mcp`'s stdio JSON-RPC transport: (a) **replicable docx-edit pipelines** (template population, batch caption fix-ups, content backfill against different baselines) currently require either re-driving 30+ MCP calls manually per run or writing fragile shell wrappers; (b) **`che-word-mcp` integration testing** has `open → save` round-trip coverage but lacks scriptable edit-path tests with non-trivial sequences. Both need a declarative way to describe a docx edit plan and execute it against `ooxml-swift` directly, with MCP and this CLI as two front-ends on the same library.

ADR-009 of `ooxml-edit-isomorphism-foundation` (macdoc#99) frames this work as the **Layer 3 DSL front-end** to the foundation: a YAML/JSON manifest compiles to a `WordEdit` script. With word-builder-swift v1.0.0 lens-model migration just shipped (2026-06-01), the ergonomic adapter layer (`LensDocument` + `@_exported import OOXMLSwift`) is now stable, making this the right moment to author the Layer 3 manifest-driven CLI on top.

The prior PR #94 attempt at this work was closed without merging on 2026-05-25 and its openspec change artifact has been deleted; this proposal authors a fresh design on top of the now-shipped foundation rather than retrofitting that closed attempt.

## What Changes

- **NEW capability `docx-workflow-cli`**: declarative manifest schema (JSON-Codable Phase 1) + ordered-step executor + verifier + dry-run plan output + diff over `LensDocument.apply`.
- **NEW Swift package `packages/docx-workflow-swift/`**: library target `DocxWorkflowLib` (Manifest decoding + AnchorResolver + EditPlanner + Executor + Verifier) that depends on word-builder-swift v1.0.0.
- **NEW `macdoc docx` subcommand cluster on `MacDocCLI`**: thin command wrappers `apply` / `plan` / `verify` / `diff` that delegate to `DocxWorkflowLib`. No standalone `dxedit` binary — distribution stays inside the existing `macdoc` CLI to preserve the one-binary, many-subcommands invariant.
- **NEW spec capability `docx-workflow-cli`**: normative requirements for manifest schema, anchor resolution semantics (multi-match = FAIL, zero-match = FAIL, exact substring), executor ordering, verify post-condition modes, and `try?` idiom for Phase 2c Reducer-pending step types.
- **MODIFIED capability `word-builder-swift`** (light touch): no API surface change; the spec gains a "Layer 3 consumer pattern" reference scenario showing how `DocxWorkflowLib` consumes `LensDocument` + Edit cases.

## Non-Goals

- **No YAML manifest support in Phase 1.** JSON-Codable first; YAML deferred until real usage proves YAML's ergonomics outweigh the extra dep (`Yams`). Reversible.
- **No standalone `dxedit` binary.** Subcommand-only on `macdoc`. A future change can extract `dxedit` if a CLI-toolkit family (`dxedit / pxedit / pptedit`) gains traction.
- **No table-mutation / image-insertion / equation-insertion step types in Phase 1 runtime-functional set.** Spec lists call shapes; executor wraps these in `try?` with explanatory comments referencing ooxml-swift#71 (per word-builder-swift v1.0.0 precedent established in `examples/03-table-3x3.swift`).
- **No archive-first auto-snapshot integration in Phase 1.** Tracked for Phase 3.
- **No che-word-mcp boundary refactor** to expose `WordEdit` directly through MCP — that is a separate Spectra change citing the same foundation per ADR-009 deferrals.
- **No replacement or deprecation of `che-word-mcp` MCP transport.** MCP and `macdoc docx` are peers per ADR-009; both can be used in the same project.

## Capabilities

### New Capabilities

- `docx-workflow-cli`: manifest schema + anchor resolution + executor + verifier + plan/diff for declarative docx-edit workflows on top of word-builder-swift v1.0.0.

### Modified Capabilities

- `word-builder-swift`: add reference scenario showing Layer 3 consumer pattern (DocxWorkflowLib reading + applying Edits + emitting). No requirement removal or behavior change.

## Impact

- Affected specs:
  - NEW: `openspec/specs/docx-workflow-cli/spec.md`
  - MODIFIED: `openspec/specs/word-builder-swift/spec.md` (add one reference scenario for Layer 3 consumer pattern)
- Affected code:
  - New:
    - `packages/docx-workflow-swift/Package.swift`
    - `packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift`
    - `packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift`
    - `packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift`
    - `packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift`
    - `packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift`
    - `packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift`
    - `packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift`
    - `packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift`
    - `packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift`
    - `Sources/MacDocCLI/MacDoc+Docx.swift`
  - Modified:
    - `Package.swift` (root macdoc — add `packages/docx-workflow-swift` path dependency + `DocxWorkflowLib` product on `MacDocCLI` target)
    - `Sources/MacDocCLI/MacDoc.swift` (register `Docx.self` in `subcommands`)
  - Removed: (none — clean break already happened at v1.0.0 of word-builder-swift)
