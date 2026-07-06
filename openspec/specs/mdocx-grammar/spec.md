# mdocx-grammar Specification

## Purpose

Pin the grammar of `.mdocx` — the embedded Swift DSL (result builder + protocol-conforming types) that authors use to produce and modify `.docx` files in macdoc. This spec is the normative contract for the surface authors (primarily AI; secondarily humans) write against, and for the reverse transcoder that lifts existing OOXML back into DSL source. Implementation lives in `packages/ooxml-swift/Sources/WordDSLSwift/` and is delivered by `word-aligned-state-sync` Phase 7.

This is the first reference implementation of the [`embedded-dsl-spec-pattern`](../embedded-dsl-spec-pattern/spec.md) capability: every Requirement below is expressed as Scenarios + SBE Examples (no EBNF / PEG), and the composition tree visualisation lives in the originating change's `design.md` rather than here. Future embedded DSL specs (`.mpdf`, `.mbib`, `.mpptx`) inherit the same shape contract.

## Related rules and contracts

- File-extension naming and dual-extension pattern (`.mdocx` / `.mdocx.swift`) — see `.claude/rules/extension-first-dsl.md`
- Embedded-DSL spec shape (Requirements + Scenarios + SBE Examples + non-normative composition tree, no EBNF) — see `.claude/rules/embedded-dsl-spec-pattern.md` and `openspec/specs/embedded-dsl-spec-pattern/spec.md`
- Narrative DSL design rationale — see `docs/swift-as-document-source.md`

## Requirements

### Requirement: File extension and dual-extension pattern

The `.mdocx` DSL SHALL use the dual-extension filename pattern `<name>.mdocx.swift` as the canonical on-disk form. The `.mdocx` segment MUST signal that the file is a macdoc Word-document authoring script; the `.swift` suffix MUST allow the standard Swift toolchain (Xcode, SourceKit-LSP, `swift build`) to treat the file as ordinary Swift source without per-project configuration.

A pure `.mdocx` filename without the trailing `.swift` MUST be accepted by `macdoc` CLI dispatch, but file-association registration with editors and the Swift toolchain is NOT REQUIRED for that form.

#### Scenario: dual-extension file recognised by Swift toolchain

- **WHEN** an author saves a script as `chapter1.mdocx.swift`
- **THEN** `swift build` and SourceKit-LSP treat the file as a Swift source file with full IDE support
- **AND** `macdoc word render chapter1.mdocx.swift` dispatches the file as a Word-DSL script

#### Scenario: pure-extension file recognised by macdoc CLI only

- **WHEN** an author saves a script as `chapter1.mdocx` (without `.swift` suffix)
- **THEN** `macdoc word render chapter1.mdocx` dispatches the file as a Word-DSL script
- **AND** the Swift toolchain MUST NOT be expected to provide IDE features without manual file-association


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Flat Run with implicit String literal inline grammar

Within any paragraph result-builder body, plain `String` literals MUST be implicitly converted to an unstyled `Run` containing that text. Any non-default formatting (bold, italics, color, font, size, etc.) MUST be expressed as an explicit `Run("text", <flag>: <value>, ...)` call. The DSL MUST NOT provide single-format wrapper components such as `Bold(...)` or `Italic(...)`.

#### Scenario: plain string compiles to unstyled Run

- **WHEN** the body contains the literal `"本章探討"`
- **THEN** the compiler emits one `Run` operation with text `本章探討` and no formatting properties

#### Scenario: explicit Run carries multiple format flags

- **WHEN** the body contains `Run("意識本質", bold: true, italics: true, color: "#663300")`
- **THEN** the compiler emits one `Run` operation with text `意識本質` and the three formatting properties

##### Example: mixed inline content

- **GIVEN** a paragraph body of `"本章探討"; Run("意識本質", bold: true); "的議題。"`
- **WHEN** the script executes
- **THEN** three operations are emitted: `Run("本章探討")`, `Run("意識本質", bold: true)`, `Run("的議題。")` in that order

#### Scenario: reverse direction emits string for unstyled, Run for styled

- **WHEN** an OOXML `<w:r>` element has no `<w:rPr>` child
- **THEN** the reverse transcoder emits a String literal in the source
- **AND** when an OOXML `<w:r>` element has any `<w:rPr>` child the reverse transcoder MUST emit `Run("text", ...)` with the corresponding format flags


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Special-character inline atoms as standalone children

Tab stops (`Tab()`), line breaks (`Break()`), no-break hyphens (`NoBreakHyphen()`), and other OOXML inline atoms that have no text content and no formatting properties MUST be expressible as standalone children within the paragraph result builder, parallel to `Run` and `String`. They MUST NOT be modeled as static factory methods on `Run`.

#### Scenario: Tab and Break compose with Run and String

- **WHEN** a paragraph body contains `"Header"; Tab(); "Right-aligned"; Break(); "Continued"`
- **THEN** the emitted operations include the runs and, between them, `insertTab` / `insertBreak` ops in declaration order (canonical shapes in `ooxml-operation-log`)

##### Example: standalone atom op shapes

| Source | Emitted op (canonical, per `ooxml-operation-log`) |
| ------ | ------------------------------------------------- |
| `Tab()` | `insertTab(in: <run-id>)` — appended in declaration order |
| `Break()` | `insertBreak(in: <run-id>)` |
| `NoBreakHyphen()` | `insertNoBreakHyphen(in: <run-id>)` |

`in:` addresses a run (`<w:r>`) — atoms are only schema-valid inside runs. A standalone atom with no preceding run in the paragraph causes the reducer to synthesize an empty wrapping `<w:r>` (rule pinned in `ooxml-operation-log`).


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: OOXML-mirror element naming

DSL element names MUST mirror OOXML element names where a 1:1 correspondence exists. Specifically: `Run` ↔ `<w:r>`, `Paragraph` ↔ `<w:p>`, `Table` ↔ `<w:tbl>`, `TableRow` ↔ `<w:tr>`, `TableCell` ↔ `<w:tc>`, `Hyperlink` ↔ `<w:hyperlink>`, `Bookmark` ↔ `<w:bookmarkStart>`/`<w:bookmarkEnd>` pair.

Deviations from this naming policy (such as `Section` as a DSL container — see separate requirement) MUST be documented as exceptions with explicit justification in the design artifact for the change that introduces them. New DSL elements added in future changes MUST follow this naming policy by default.

#### Scenario: new element added by future change conforms

- **WHEN** a future change adds a DSL element corresponding to OOXML `<w:caption>`
- **THEN** the new DSL element MUST be named `Caption` unless the introducing change documents and justifies an alternative name

#### Scenario: reverse direction has no naming translation step

- **WHEN** the reverse transcoder reads an OOXML `<w:tbl>` element
- **THEN** it emits a `Table(...)` call without consulting a translation table


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: No semantic shortcuts for OOXML-style attributes

The DSL MUST NOT provide convenience wrapper components for paragraph kinds that OOXML expresses through the `<w:pStyle>` attribute (such as headings, quotes, captions, list items). Headings MUST be written as `Paragraph(style: .heading1)`, quotes as `Paragraph(style: .quote)`, list items as `Paragraph(style: .listItem, ...)`.

The DSL MUST NOT provide single-format wrapper components for inline formatting that OOXML expresses through `<w:rPr>` flags (such as `Bold`, `Italic`, `Underline`). All inline formatting MUST go through `Run("text", <flag>: <value>, ...)`.

#### Scenario: heading written as Paragraph with style

- **WHEN** an author writes a level-1 heading
- **THEN** the source MUST be `Paragraph(id: "h1", style: .heading1) { "Title text" }`
- **AND** there MUST NOT be a `Heading1("Title text")` form available

#### Scenario: bold text written as Run with flag

- **WHEN** an author writes a bold inline phrase
- **THEN** the source MUST be `Run("text", bold: true)`
- **AND** there MUST NOT be a `Bold("text")` form available

#### Scenario: reverse direction emits canonical form only

- **WHEN** the reverse transcoder reads `<w:p w:pStyle="Heading1">...</w:p>`
- **THEN** it emits exactly `Paragraph(style: .heading1) { ... }` and never an alternate shortcut form


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Section as DSL container with compile-time marker inversion

`Section { ... }` MUST behave as a true result-builder container at the DSL level. The compiler MUST invert this container syntax into the OOXML pattern at serialization time, where each section's properties live as a `<w:sectPr>` element after the section's last paragraph (or within the final paragraph's `<w:pPr>` for non-terminal sections).

#### Scenario: container syntax serialises to marker-pattern OOXML

- **WHEN** the source contains two sequential `Section { ... }` blocks
- **THEN** the emitted `word/document.xml` contains all paragraphs as siblings with two `<w:sectPr>` markers: one inside the last paragraph of the first section's `<w:pPr>`, and one as a direct child of `<w:body>` after the second section's last paragraph

##### Example: two-section serialisation

- **GIVEN** the source:
  ```swift
  Section(id: "front", type: .continuous) { Paragraph(id: "f1") { "Front matter" } }
  Section(id: "main", type: .nextPage) { Paragraph(id: "m1") { "Main body" } }
  ```
- **WHEN** the script saves the docx
- **THEN** `word/document.xml` contains, in order: `<w:p w14:paraId="f1"><w:pPr><w:sectPr w:type="continuous"/></w:pPr>...</w:p>`, `<w:p w14:paraId="m1">...</w:p>`, `<w:sectPr w:type="nextPage"/>`

#### Scenario: reverse direction reconstructs container syntax

- **WHEN** the reverse transcoder reads the OOXML output of the previous example
- **THEN** it emits two `Section` blocks with `id` recovered from the section markers' adjacent paragraphs and `type` recovered from the `<w:type>` attribute


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Component-aware op log via BeginComponent and EndComponent

A user-defined type conforming to `WordComponent` MUST emit a paired `beginComponent` and `endComponent` operation (canonical shapes in `ooxml-operation-log`) bracketing all operations produced by its body. The `beginComponent` op MUST carry the component's runtime type name and its `id`; the `endComponent` op MUST carry the same `id`.

The reverse transcoder MUST recognise the `beginComponent`/`endComponent` envelope in the op log and reconstruct the component invocation in the output source. The `beginComponent` and `endComponent` operations MUST NOT produce any element in the final OOXML output (they are op-log metadata only — the documented exception to OOXML-mirror op naming).

#### Scenario: component body wrapped in op-log envelope

- **GIVEN** a custom component `Summary` that, when expanded, produces one `Paragraph(id: "sum-frame", style: .summaryFrame)` containing a `Run("note text")`
- **WHEN** an author writes `Summary(id: "ch1-summary") { "note text" }`
- **THEN** the op log contains, in order: `beginComponent(type: "Summary", id: "ch1-summary")`, `appendParagraph(in: "ch1-summary", id: "sum-frame", style: "summaryFrame")`, `setRuns(target: "sum-frame", runs: [{text: "note text"}])`, `endComponent(id: "ch1-summary")` (canonical names per `ooxml-operation-log`)

#### Scenario: reverse direction reconstructs component invocation

- **WHEN** the reverse transcoder reads the op log produced by the previous scenario
- **THEN** it emits exactly `Summary(id: "ch1-summary") { "note text" }` and MUST NOT emit the flattened `Paragraph(...) { ... }` form

#### Scenario: component metadata produces no OOXML artifact

- **WHEN** the docx is serialised from the op log produced by the first scenario above
- **THEN** the resulting `word/document.xml` MUST NOT contain any element corresponding to `beginComponent` or `endComponent`
- **AND** byte-equal round-trip MUST hold for the docx output across multiple component-instance invocations


<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->

---
### Requirement: Mandatory explicit identifiers on structural elements

Every structural DSL element (`Section`, `Paragraph`, every `WordComponent` subtype, `Bookmark`, `Hyperlink` when used as anchor target, `Table`, `TableRow`, `TableCell`) MUST be instantiated with an explicit `id:` parameter at the call site. The compiler MUST refuse to compile any DSL source where a structural element omits the `id:` parameter.

The `id:` value MUST map to the corresponding OOXML stable identifier on serialisation (`w14:paraId` for paragraphs, `w:bookmarkId` for bookmarks, generated UUID stored as `w14:textId` or vendor extension where OOXML lacks a native stable ID).

#### Scenario: missing id parameter is a compile error

- **WHEN** an author writes `Paragraph { "text" }` without an `id:` argument
- **THEN** Swift compilation fails with a clear error message indicating that `id:` is required

#### Scenario: explicit id maps to OOXML stable identifier

- **WHEN** an author writes `Paragraph(id: "ch1-intro") { "本章探討" }`
- **THEN** the serialised OOXML element is `<w:p w14:paraId="ch1-intro">...</w:p>` (with `ch1-intro` byte-equal in the attribute value)

#### Scenario: reverse direction recovers the same id verbatim

- **WHEN** the reverse transcoder reads `<w:p w14:paraId="ch1-intro">...</w:p>`
- **THEN** it emits `Paragraph(id: "ch1-intro") { ... }` with `ch1-intro` byte-equal as the `id:` argument


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Style references via typed enum with define-on-first-use

Paragraph and Run style references MUST use a typed `WordStyle` enum value (e.g., `style: .heading1`). Raw-string style names (e.g., `style: "heading1"`) MUST NOT be accepted. The first occurrence of a `WordStyle` value in an executed script MUST emit a `DefineStyle` operation carrying the style's properties; subsequent occurrences of the same `WordStyle` value MUST emit only a style-reference identifier and MUST NOT re-emit `DefineStyle`.

#### Scenario: typed enum required, raw string rejected

- **WHEN** an author writes `Paragraph(id: "p1", style: .heading1) { "Title" }`
- **THEN** the source compiles successfully
- **AND** when an author writes `Paragraph(id: "p1", style: "heading1") { "Title" }`
- **THEN** Swift compilation fails with a type-mismatch error indicating `WordStyle` is required

#### Scenario: first reference emits DefineStyle, subsequent re-use

- **GIVEN** a `WordStyle` value `.titleBrown` defined as `WordStyle(font: "Noto Serif TC", fontSize: 36, color: "#663300", bold: true)`
- **WHEN** two paragraphs both reference `style: .titleBrown`
- **THEN** the op log contains exactly one `DefineStyle(id: "titleBrown", font: "Noto Serif TC", fontSize: 36, color: "#663300", bold: true)` operation
- **AND** the op log contains two paragraph operations whose style-reference identifier is `titleBrown`

##### Example: define-on-first-use op sequence

- **GIVEN** the source:
  ```swift
  Paragraph(id: "h1", style: .titleBrown) { "Title" }
  Paragraph(id: "h2", style: .titleBrown) { "Subtitle" }
  ```
- **WHEN** the script executes
- **THEN** the op log contains, in order: `DefineStyle(id: "titleBrown", ...)`, `InsertParagraph(id: "h1", style: "titleBrown", ...)`, `InsertParagraph(id: "h2", style: "titleBrown", ...)`


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Table grammar mirrors OOXML three-layer structure

Tables MUST be expressed as a three-layer DSL container hierarchy: `Table` containing `TableRow` children, each `TableRow` containing `TableCell` children, each `TableCell` containing block-level content (`Paragraph` and nested elements). DSL element names MUST mirror OOXML: `Table` ↔ `<w:tbl>`, `TableRow` ↔ `<w:tr>`, `TableCell` ↔ `<w:tc>`. Each `Table`, `TableRow`, and `TableCell` MUST carry an explicit `id:` parameter.

#### Scenario: three-layer table compiles to mirror OOXML

- **WHEN** an author writes a 1-row 2-cell table:
  ```swift
  Table(id: "tbl1") {
      TableRow(id: "tbl1-r0") {
          TableCell(id: "tbl1-r0-c0") { Paragraph(id: "tbl1-r0-c0-p0") { "A" } }
          TableCell(id: "tbl1-r0-c1") { Paragraph(id: "tbl1-r0-c1-p0") { "B" } }
      }
  }
  ```
- **THEN** the serialised OOXML is `<w:tbl><w:tr><w:tc><w:p>A</w:p></w:tc><w:tc><w:p>B</w:p></w:tc></w:tr></w:tbl>` with stable IDs preserved on each element

#### Scenario: missing id on any of three layers is a compile error

- **WHEN** any of `Table`, `TableRow`, or `TableCell` is written without an `id:` argument
- **THEN** Swift compilation fails (per the Mandatory explicit identifiers requirement)


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Lists use Paragraph with numPr reference, not nested containers

Numbered lists and bullet lists MUST be expressed as `Paragraph` instances with `style: .listItem` plus an explicit `numbering:` reference and `level:` index. The DSL MUST NOT provide a nested `List { ListItem { ... } }` container form. Numbering definitions MUST be declared as standalone `NumberingDefinition` declarations and referenced by typed identifier.

#### Scenario: list paragraphs reference NumberingDefinition

- **GIVEN** a `NumberingDefinition(id: "bulletA", style: .bullet)` declaration in scope
- **WHEN** an author writes:
  ```swift
  Paragraph(id: "li1", style: .listItem, numbering: .bulletA, level: 0) { "Item 1" }
  Paragraph(id: "li2", style: .listItem, numbering: .bulletA, level: 0) { "Item 2" }
  Paragraph(id: "li3", style: .listItem, numbering: .bulletA, level: 1) { "Sub-item 2.1" }
  ```
- **THEN** each paragraph serialises to `<w:p><w:pPr><w:pStyle w:val="ListItem"/><w:numPr><w:ilvl w:val="<level>"/><w:numId w:val="<numId-of-bulletA>"/></w:numPr></w:pPr>...</w:p>`

#### Scenario: nested list container syntax is rejected

- **WHEN** an author attempts `List { Paragraph(...); Paragraph(...) }` or `List { ListItem("X") }`
- **THEN** Swift compilation fails because `List` and `ListItem` are not exposed types in the DSL


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Hyperlinks are containers with target enum

`Hyperlink` MUST be expressed as a result-builder container whose target is specified by a `to:` parameter of an `HyperlinkTarget` enum type. Supported cases MUST include `.url(String)` for external URLs, `.anchor(String)` for internal bookmark anchors, and `.mailto(String)` for email links. The hyperlink body MUST contain inline content (`String`, `Run`, `Tab`, `Break`).

#### Scenario: external URL hyperlink

- **WHEN** an author writes `Hyperlink(to: .url("https://example.com")) { "external" }`
- **THEN** the serialised OOXML adds a `<w:hyperlink r:id="<rId>">` containing `<w:r><w:t>external</w:t></w:r>` and a relationship entry of type hyperlink with target `https://example.com`

#### Scenario: internal anchor hyperlink

- **WHEN** an author writes `Hyperlink(to: .anchor("ch1-intro")) { "Chapter 1" }`
- **THEN** the serialised OOXML adds a `<w:hyperlink w:anchor="ch1-intro">` containing `<w:r><w:t>Chapter 1</w:t></w:r>`
- **AND** the validator MUST emit a warning if no element in the same document has `id: "ch1-intro"` matching the anchor target

##### Example: hyperlink composition inside paragraph

- **GIVEN** the source:
  ```swift
  Paragraph(id: "p1") {
      "see "
      Hyperlink(to: .anchor("ch1-intro")) { "Chapter 1" }
      " for context."
  }
  ```
- **WHEN** the script executes
- **THEN** the paragraph contains four ordered children: `Run("see ")`, `Hyperlink(to: .anchor("ch1-intro")) { Run("Chapter 1") }`, `Run(" for context.")` (the implicit string-to-Run conversion applies inside the hyperlink body)


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Bookmarks default to container with paired-marker escape hatch

`Bookmark` MUST be expressed as a result-builder container whose body is the bookmark span: `Bookmark(id: "intro") { ... }`. The container form covers the common case where a bookmark spans a contiguous element subtree. For cross-paragraph spans (where start and end markers are not in the same parent), the DSL MUST provide explicit `BookmarkStart(id:)` and `BookmarkEnd(id:)` standalone elements as an escape hatch, and the start/end IDs MUST match.

#### Scenario: container form spans single element

- **WHEN** an author writes `Bookmark(id: "intro-text") { Run("本章探討") }` inside a paragraph
- **THEN** the serialised OOXML wraps the run in `<w:bookmarkStart w:id="<n>" w:name="intro-text"/><w:r>本章探討</w:r><w:bookmarkEnd w:id="<n>"/>`

#### Scenario: cross-paragraph escape hatch using paired markers

- **WHEN** an author writes:
  ```swift
  BookmarkStart(id: "ch1-span")
  Paragraph(id: "p1") { "First paragraph." }
  Paragraph(id: "p2") { "Second paragraph." }
  BookmarkEnd(id: "ch1-span")
  ```
- **THEN** the serialised OOXML places the `<w:bookmarkStart>` before the first paragraph element and `<w:bookmarkEnd>` after the last paragraph element with matching `w:id` attributes

#### Scenario: mismatched start/end IDs is a compile error

- **WHEN** an author writes `BookmarkStart(id: "a")` followed by `BookmarkEnd(id: "b")` with no matching pair
- **THEN** the compiler emits a diagnostic indicating that `BookmarkStart(id: "a")` has no matching `BookmarkEnd(id: "a")`


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: save(to:) atomic three-file write

`WordDocument.save(to:)` MUST write three files atomically as a single logical state: `<name>.docx` (the OOXML container), `<name>.docx.oplog.jsonl` (append-only operation history), `<name>.docx.snapshot.json` (the current XmlNode tree snapshot used by `WordImport` for diff). On failure of any of the three writes, the file system MUST be left in the state before `save(to:)` was called (no partial output).

#### Scenario: successful save produces three files atomically

- **WHEN** `try doc.save(to: URL(fileURLWithPath: "賽斯書.docx"))` runs to completion
- **THEN** all three files exist on disk: `賽斯書.docx`, `賽斯書.docx.oplog.jsonl`, `賽斯書.docx.snapshot.json`
- **AND** all three files have content matching the document's current state

#### Scenario: failure during second-file write rolls back

- **GIVEN** the docx write succeeds but the oplog write fails (e.g., disk full, permission denied)
- **WHEN** `save(to:)` returns
- **THEN** none of the three files reflect the new state on disk
- **AND** any pre-existing versions of the three files remain at their previous content

#### Scenario: refuses to overwrite when target docx is locked by Word

- **GIVEN** Word is running and holds an exclusive lock on `賽斯書.docx`
- **WHEN** `try doc.save(to: ...)` is invoked
- **THEN** the call throws a structured error indicating the file is locked by Word
- **AND** none of the three files are modified


<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Reverse CLI shape — macdoc word reverse

The `macdoc` CLI MUST provide a `word reverse` subcommand that produces an `.mdocx.swift` source file from an existing docx. The signature MUST be `macdoc word reverse <docx-path> --to-mdocx <output-path> [--from-oplog] [--force]`. When `--from-oplog` is present (default true if a `<docx>.oplog.jsonl` sidecar exists alongside the docx), the reverse transcoder MUST replay the op log to obtain current state and emit DSL source for that state. When `--from-oplog` is absent or no sidecar exists, the reverse transcoder MUST reverse-engineer DSL source directly from the docx parts (no oplog input). The CLI MUST refuse to overwrite an existing `--to-mdocx` output file unless `--force` is supplied.

#### Scenario: reverse from docx + oplog reproduces current state DSL

- **GIVEN** a docx with an adjacent `賽斯書.docx.oplog.jsonl` containing operations that include Word-side edits
- **WHEN** `macdoc word reverse 賽斯書.docx --to-mdocx 賽斯書.mdocx.swift --from-oplog` runs
- **THEN** the output file `賽斯書.mdocx.swift` contains a DSL source that, when re-executed, produces a docx byte-equal to `賽斯書.docx` (including all Word-side edits replayed via the oplog)

#### Scenario: reverse from docx only reverse-engineers initial state

- **GIVEN** a docx with no `<docx>.oplog.jsonl` sidecar
- **WHEN** `macdoc word reverse 賽斯書.docx --to-mdocx 賽斯書.mdocx.swift` runs
- **THEN** the output file contains DSL source reverse-engineered from the docx parts directly
- **AND** stable IDs are recovered from `w14:paraId` / `w:bookmarkId` / `w:id` attributes byte-equal

#### Scenario: refuses to overwrite without --force

- **GIVEN** an existing `賽斯書.mdocx.swift` file
- **WHEN** `macdoc word reverse 賽斯書.docx --to-mdocx 賽斯書.mdocx.swift` runs (without `--force`)
- **THEN** the CLI exits with a non-zero status code and the existing file is unchanged
- **AND** the same command with `--force` overwrites the file successfully

<!-- @trace
source: mdocx-syntax
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144003.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093825.log
-->

---
### Requirement: Operation wire format is defined by ooxml-operation-log

The op names appearing in this spec's Scenarios and SBE Examples SHALL be read as references to the canonical operation taxonomy defined in `ooxml-operation-log` — the single normative home of the operation wire format (#128). This spec regulates the DSL surface and the reverse transcoder's behavior; it SHALL NOT define or restate operation shapes. Where an example historically showed a positional `at:` index, the index is derived display metadata: actual addressing is ID-based per `ooxml-operation-log`'s "ID-based operations, never positional indices" requirement — the DSL emits children in declaration order via `appendParagraph(in:)` / `insertParagraphAfter(after:)` anchoring.

#### Scenario: Example op names resolve to canonical taxonomy

- **WHEN** an SBE example in this spec names an emitted operation
- **THEN** the operation's authoritative shape (payload fields, addressing, JSONL form) is the one in `ooxml-operation-log`, and any discrepancy resolves in favor of `ooxml-operation-log`

<!-- @trace
source: word-aligned-state-sync
updated: 2026-07-06
code:
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-144618.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/AnchorResolver.swift
  - .remember/logs/autonomous/save-095118.log
  - plugins/macdoc/hooks/hooks.json
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-143020.log
  - Sources/MacDocCLI/MacDoc+Word.swift
  - .remember/logs/autonomous/save-133659.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093340.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-095142.log
  - plugins/che-pdf-mcp/bin/che-pdf-mcp-wrapper.sh
  - reference/README.md
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-144433.log
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - .remember/logs/autonomous/save-090944.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ExecutorTests.swift
  - .remember/logs/autonomous/save-092853.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGeneratorTests.swift
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - plugins/che-pptx-mcp/bin/che-pptx-mcp-wrapper.sh
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125453.log
  - mcp/che-pdf-mcp
  - .remember/logs/autonomous/save-070717.log
  - plugins/che-pptx-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-094627.log
  - .claude-plugin/marketplace.json
  - Package.swift
  - .remember/logs/autonomous/save-053409.log
  - plugins/che-pptx-mcp/README.md
  - plugins/macdoc/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-095621.log
  - README.md
  - .remember/logs/autonomous/save-093255.log
  - docs/lossless-conversion.md
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorDecodingTests.swift
  - Package.resolved
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-130300.log
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - mcp/che-pptx-mcp
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093039.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/DocxWorkflowLib.swift
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/VerifyAssertions.swift
  - packages/docx-workflow-swift/Package.swift
  - .github/PULL_REQUEST_TEMPLATE.md
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-093030.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Manifest.swift
  - .remember/logs/autonomous/save-093138.log
  - cli/FastOCR
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-095539.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Anchor.swift
  - plugins/che-word-mcp/CLAUDE.md
  - plugins/macdoc/skills/macdoc/SKILL.md
  - .remember/logs/autonomous/save-095047.log
  - plugins/che-word-mcp/README.md
  - Tests/MacDocCLITests/CLITestHelper.swift
  - Tests/MacDocCLITests/NoteHTMLConvertTests.swift
  - plugins/che-pdf-mcp/skills/che-pdf-mcp/SKILL.md
  - plugins/che-word-mcp/.claude-plugin/plugin.json
  - .remember/logs/autonomous/save-125949.log
  - plugins/che-word-mcp/.mcp.json
  - .github/skills/spectra-drift/SKILL.md
  - plugins/che-pdf-mcp/README.md
  - docs/stale-triage-chain-2026-05-25.md
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-132950.log
  - plugins/che-pdf-mcp/CHANGELOG.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/EditPlanner.swift
  - plugins/che-word-mcp/bin/che-word-mcp-wrapper.sh
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093013.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/ManifestDecodingTests.swift
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-132859.log
  - plugins/che-word-mcp/CHANGELOG.md
  - Sources/MacDocCLI/MacDoc.swift
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-143733.log
  - plugins/macdoc/hooks/session-start.sh
  - packages/docx-workflow-swift/CHANGELOG.md
  - .remember/logs/autonomous/save-144132.log
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifierTests.swift
  - plugins/che-pdf-mcp/.claude-plugin/plugin.json
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-144003.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-093149.log
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/Verifier.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/VerifyAssertionsDecodingTests.swift
  - plugins/che-pptx-mcp/.mcp.json
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - scripts/release-cli.sh
  - .remember/logs/autonomous/save-143856.log
  - CLAUDE.md
  - .remember/logs/autonomous/save-144708.log
  - Tests/MacDocCLITests/Fixtures/README.md
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-095546.log
  - .gitmodules
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-090656.log
  - packages/docx-workflow-swift/README.md
  - plugins/che-pptx-mcp/CHANGELOG.md
  - .remember/logs/autonomous/save-051714.log
  - plugins/che-pdf-mcp/.mcp.json
  - .remember/logs/autonomous/save-093825.log
  - Tests/MacDocCLITests/Fixtures/NoteFixtureGenerator.swift
  - plugins/macdoc/CHANGELOG.md
  - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - .remember/logs/autonomous/save-091107.log
  - docs/edit-algebra-cd-discipline.md
  - docs/structural-editing-paradigm.md
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-131902.log
  - .github/prompts/spectra-drift.prompt.md
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-050705.log
  - docs/docx-libraries-comparison.md
  - packages/docx-workflow-swift/Sources/DocxWorkflowLib/ParagraphSnapshot.swift
  - packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/AnchorResolverTests.swift
  - docs/stale-triage-chain-batch2-2026-05-25.md
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-143700.log
-->