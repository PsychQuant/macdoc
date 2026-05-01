## Context

macdoc already exposes `convert --to docx` routes for format conversion and imports `word-builder-swift` as a dependency. It also has adjacent OOXML packages in the workspace, and `che-word-mcp` already proves the lower-level `.docx` mutation engine for interactive agent workflows. The missing layer is a deterministic CLI workflow that lets an agent declare a desired document edit as data, inspect the planned operations, run the edit, and verify the result without owning an MCP session.

Issue #92 changed direction from a standalone `dxedit` executable to an integrated `macdoc docx` command family. That direction keeps the user-facing product compact while preserving the option to add a thin wrapper after the manifest schema has production mileage.

## Goals / Non-Goals

**Goals:**

- Add one `macdoc docx` namespace covering build, patch, apply, plan, verify, and diff.
- Define one Codable JSON manifest model shared by CLI commands and tests.
- Put parsing, planning, execution, readback verification, and structural diff logic in an importable Swift library target.
- Preserve source documents by writing a separate output file by default.
- Keep generated fixtures synthetic and small enough for stable CI.

**Non-Goals:**

- Ship a public `dxedit` binary in Phase 1.
- Add YAML parsing or a YAML dependency in Phase 1.
- Commit private thesis, manuscript, advisor-review, or client documents as fixtures.
- Replace `che-word-mcp` session tools, autosave behaviour, comment-thread workflows, or interactive MCP editing.
- Guarantee Microsoft Word visual rendering fidelity in Phase 1.

## Decisions

### Use `macdoc docx` as the Phase 1 product surface

The CLI surface will be `macdoc docx build`, `macdoc docx patch`, `macdoc docx apply`, `macdoc docx plan`, `macdoc docx verify`, and `macdoc docx diff`. A future `dxedit` wrapper can delegate to the same library after users have exercised the schema. This avoids asking agents to choose between two tools while the contract is still being shaped.

Alternative considered: create `dxedit` first and wire macdoc later. Rejected because it would force documentation, issue triage, and plugin instructions to teach a second command before the manifest model is stable.

### Keep workflow logic in `DocxWorkflowLib`

Create a new library target with the public entry points `DocxManifest`, `DocxWorkflowPlanner`, `DocxWorkflowExecutor`, `DocxWorkflowVerifier`, and `DocxWorkflowDiffer`. `MacDocCLI` translates ArgumentParser options into URLs and calls the library. Tests cover the library directly first, then add CLI smoke tests for argument routing and exit behaviour.

Alternative considered: implement everything inside `Sources/MacDocCLI`. Rejected because manifest execution and verification need importable APIs for tests, future MCP/tool wrappers, and a future `dxedit` wrapper.

### Use JSON-first Codable manifests

Phase 1 accepts JSON manifests only. The manifest includes `schemaVersion`, `workflow`, optional `input`, optional `template`, optional `output`, ordered `steps`, and `checks`. CLI arguments can override `input`, `template`, and `output`; the effective resolved paths appear in `plan` output so automation logs are reproducible.

Alternative considered: accept YAML immediately for author comfort. Rejected because the repo does not need another parser dependency before the schema stabilizes, and JSON maps cleanly to Swift Codable tests.

### Separate build, patch, and apply semantics

Build starts from an empty document model and uses `word-builder-swift` concepts for sections, paragraphs, runs, tables, images, and equations where the package exposes stable model coverage. Patch starts from a template document and targets explicit placeholders such as text tokens or content controls. Apply starts from an existing document and runs ordered operations such as text replacement or insertion against resolved anchors.

Alternative considered: make every operation a generic apply step. Rejected because creation, placeholder filling, and source mutation have different safety checks and error messages.

### Make planning mandatory inside every execution path

Execution first builds the same operation plan that `macdoc docx plan` prints, then runs that plan. Anchor misses, duplicate placeholder matches that are not explicitly allowed, unsupported step types, and invalid path resolution fail before writing the output file.

Alternative considered: execute directly and report partial results. Rejected because agent workflows need deterministic failure before file writes.

### Verify by OOXML readback and manifest checks

`verify` reads the output `.docx` after execution and enforces checks declared in the manifest: required text, forbidden text, expected replacement counts, required image relationship count, and successful readback. It also reports the executed operation summary from the plan when available.

Alternative considered: rely on process exit code and non-empty output. Rejected because #92 is about agent quality; a non-empty document is not enough evidence that the intended edit landed.

### Diff at a Word-aware structural level

`diff` compares extracted document text and selected structure metadata rather than raw zip bytes. The first pass reports paragraph text additions/removals, table count changes, image relationship count changes, and field/equation count changes when the reader exposes those values. Raw ZIP byte diff is not the default because unrelated archive ordering or relationship id churn would create noisy output.

Alternative considered: shell out to a generic binary diff. Rejected because it is unusable for agent review of `.docx` edits.

## Risks / Trade-offs

- [Risk] OOXML reader/writer coverage is lower than the full Microsoft Word surface. → Mitigation: Phase 1 supports a constrained operation set, returns explicit unsupported-step errors, and relies on existing OOXML preservation tests for source round-trip safety.
- [Risk] JSON manifests are less pleasant to hand-write than YAML. → Mitigation: keep schemaVersion 1 compact, document examples, and defer YAML until the workflow has stable users.
- [Risk] Build, patch, and apply can drift into three separate engines. → Mitigation: all three produce a normalized `DocxOperationPlan` before execution, and verify/diff consume shared readback summaries.
- [Risk] Directly depending on transitive OOXML products can create package resolution ambiguity. → Mitigation: add explicit root package dependencies for the Word/OOXML products used by `DocxWorkflowLib` instead of relying on transitive imports.
