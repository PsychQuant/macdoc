# ooxml-script-transcode Specification

## Purpose

The bidirectional codec between a `.docx` package and `.mdocx.swift` rebuild-script source, plus the execution of those scripts back into a package.

Three concerns live here. **Export** lifts an existing document into a script: the raw part channel carries every XML part verbatim as a byte-equal floor, and the reverse extractor upgrades parts to typed DSL form only where a trial rebuild proves the upgrade byte-equal. **Import** parses a script back into an operation log. **Execution** replays that log onto an empty authoring document, writes the package, and — when the caller supplies a reference — compares the rebuilt part set for Stage-B byte equality.

Every consumer of the script pipeline calls these entry points rather than reimplementing them. `macdoc word reverse` and `macdoc word render` on the CLI, and che-word-mcp's `export_script` / `get_script_coverage` / `execute_script` tools, are argument-parsing shells over this module; that shared implementation is what makes the two faces agree by construction rather than by convention.

## Requirements

### Requirement: Operation log to Swift script export

The library SHALL provide `ScriptExporter.exportSwift(log:)` that emits a runnable Swift source file whose execution against an empty `OperationLog` reproduces the input log byte-equal.

#### Scenario: Exported script is runnable Swift

- **GIVEN** an `OperationLog` containing operations
- **WHEN** `exportSwift(log:)` runs
- **THEN** the returned String compiles as a Swift source file with `import WordDSLSwift` and a top-level `let document = WordDocument { ... }` declaration conforming to `mdocx-grammar`, whose execution emits the operations

#### Scenario: Round-trip log → script → log preserves operations

- **GIVEN** an input `OperationLog L`
- **WHEN** `L'` is reconstructed from `ScriptImporter.parse(ScriptExporter.exportSwift(log: L))`
- **THEN** every operation in `L'` matches the corresponding operation in `L` for `op_type`, `payload`, and `source` fields (`op_id` and `timestamp` may differ since they regenerate)


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
### Requirement: Swift script to operation log import

The library SHALL provide `ScriptImporter.parse(source:)` that reads a Swift source string conforming to the exporter's grammar and returns the equivalent `OperationLog`.

#### Scenario: Hand-written script imports successfully

- **GIVEN** a Swift script (mdocx-grammar canonical form):
  ```swift
  import WordDSLSwift

  let document = WordDocument {
      Section(id: "main") {
          Paragraph(id: "p-title", style: .heading1) { "Title" }
          Paragraph(id: "p-intro") { "Body intro" }
      }
  }
  ```
- **WHEN** `ScriptImporter.parse(source:)` runs
- **THEN** the returned log contains operations equivalent to `[defineStyle(heading1), appendParagraph(in: nil, "Title", styleId: "Heading1"), insertParagraphAfter(after: p-title, "Body intro")]` (canonical names per `ooxml-operation-log`)

#### Scenario: Malformed script raises structured error

- **WHEN** the import receives a Swift source that does not conform to the exporter grammar (e.g., contains arbitrary side-effecting code)
- **THEN** `ScriptImporter.parse` throws `TranscodeError.unsupportedSyntax(line:column:reason:)` with a precise location


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
### Requirement: Build a docx end-to-end from a Swift script

The library SHALL support construction of a complete docx file from a Swift script with no prior docx as input. An empty `WordDocument { }` declaration SHALL initialize an empty document; the script body populates it; `WordDocument.save(to:)` writes the resulting docx (atomic three-file write per `mdocx-grammar`).

#### Scenario: Empty document save produces valid docx

- **WHEN** `WordDocument { }.save(to: url)` runs
- **THEN** the resulting `url` is a valid docx readable by Word: `[Content_Types].xml`, `_rels/.rels`, `word/_rels/document.xml.rels`, `word/document.xml` are all present and well-formed

#### Scenario: Script-built docx round-trips byte-equal

- **GIVEN** a Swift script that builds a docx and saves to `script_output.docx`
- **WHEN** the docx is opened in Word, saved without edits, and re-read by ooxml-swift
- **THEN** the re-read content matches the original script's output for every typed view (no Word-side rejection, no schema warnings)


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
### Requirement: Stable script formatting for diff readability

The exported Swift script SHALL use a stable, deterministic formatting (consistent indentation, predictable line ordering, deterministic comment placement) so that two logs differing by one operation produce scripts that differ by one localized hunk in `git diff`.

#### Scenario: Adding one operation produces one-hunk diff

- **GIVEN** logs `L1` of length N and `L2 = L1 + [op_new]` of length N+1
- **WHEN** `exportSwift(L1)` and `exportSwift(L2)` are diffed
- **THEN** the diff contains exactly one inserted block corresponding to `op_new`; no other lines change


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
### Requirement: Script export covers all operation types in the log

The exporter SHALL produce a Swift representation for every operation type defined by `ooxml-operation-log`. When an unknown future op_type is encountered, the exporter SHALL emit a comment marker and the raw JSON payload, preserving forward compatibility.

#### Scenario: Unknown op_type round-trips via raw form

- **GIVEN** a log containing an operation with `op_type: "future_op_v2"` not recognized by the current exporter
- **WHEN** `exportSwift(log:)` runs and the result is parsed back via `ScriptImporter.parse`
- **THEN** the unknown operation reappears in the resulting log byte-equal in its `payload` field

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
### Requirement: All-parts raw channel

The rebuild script SHALL be able to carry every XML part of the source package verbatim: sibling parts (styles.xml, settings.xml, theme, fontTable, numbering, headers/footers, rels, [Content_Types].xml, …) ride the script through a raw part channel that preserves their bytes exactly. Executing the script SHALL emit each carried part byte-equal. The raw channel is the byte-equality floor of the dual-track contract (`format-alignment-pipeline`); parts later upgraded to typed DSL leave the raw channel only when byte equality is preserved.

#### Scenario: sibling part round-trips verbatim

- **GIVEN** a source docx whose styles.xml contains 16 styles with docDefaults and latentStyles
- **WHEN** the script produced by word reverse executes
- **THEN** the rebuilt styles.xml is byte-equal to the source


<!-- @trace
source: format-alignment-engine
updated: 2026-07-08
code:
  - mcp/che-word-mcp
-->

---
### Requirement: DSL-form coverage measurement

The transcoder SHALL measure and report DSL-form coverage: for each XML part, the byte count rebuilt through typed DSL projection versus the raw channel, and the aggregate percentage across all parts. The measurement SHALL be exposed programmatically (for tests and baselines) and via `macdoc word reverse --coverage` output.

#### Scenario: baseline report

- **WHEN** word reverse runs with coverage reporting on a paragraphs-only extraction
- **THEN** the report lists per-part DSL/raw byte splits and the aggregate percentage, and records which content classes remain on the raw channel


<!-- @trace
source: format-alignment-engine
updated: 2026-07-08
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Reverse extraction covers the five format layers

Reverse engineering SHALL extract, in DSL form where byte equality permits: run-level formatting (fonts including eastAsia, size, underline, color, vertical alignment), paragraph-level formatting (spacing, indentation, alignment, numbering reference), section-level properties (page size, margins, orientation, columns, headers/footers references), and table structure — in addition to the already-shipped text + styleId extraction. Structural-role inference is explicitly out of scope (strict mode only).

#### Scenario: CJK run formatting survives the DSL channel

- **GIVEN** a source run with eastAsia font ＭＳ ゴシック and size 21 half-points
- **WHEN** run-level extraction is upgraded to the DSL channel and the script re-executes
- **THEN** the rebuilt run's rPr is byte-equal to the source

#### Scenario: two-column section round-trips

- **GIVEN** a source with a second section carrying `w:cols num="2"`
- **WHEN** section extraction lands and the script re-executes
- **THEN** the rebuilt sectPr is byte-equal and the visual-diff harness confirms the two-column layout

<!-- @trace
source: format-alignment-engine
updated: 2026-07-08
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Form-gap measurement names the first offending form

When typed extraction of a part bails to the raw channel, the transcoder SHALL record a structured form-gap: the part path, the XML path to the first offending node or attribute, and the content-class tag. The reverse result SHALL expose these records programmatically so tests and baselines can enumerate exactly which form blocks an upgrade. An upgraded part SHALL have no form-gap record.

#### Scenario: bail names the offending attribute

- **GIVEN** a document.xml whose third paragraph carries a `w:rsidR` attribute the vocabulary does not yet support
- **WHEN** reverse runs and the part stays raw
- **THEN** the result contains a form-gap naming that paragraph's XML path and the offending attribute

#### Scenario: upgraded part reports no gaps

- **WHEN** a document.xml passes the trial-rebuild byte-equal gate and upgrades
- **THEN** its form-gap list is empty


<!-- @trace
source: word-canonical-forms
updated: 2026-07-09
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Word-canonical form vocabulary

Reverse extraction SHALL recognize, and the rebuild path SHALL re-serialize byte-equal, the following Word-authored forms in addition to the writer's own forms: document root elements with arbitrary namespace declarations and `mc:Ignorable` (order-preserved), paragraph- and run-level revision-session-id attributes (rsid family, order-preserved, semantically opaque), and `xml:space="preserve"` on text elements. Long-tail rPr/pPr/sectPr elements SHALL be added measurement-first: each class enters the vocabulary only with a corresponding upgrade-class regression pin, and a form the serializer cannot reproduce byte-equal SHALL stay on the raw channel per the existing gate — no canonical-form exemptions.

#### Scenario: real template document.xml upgrades

- **GIVEN** the env-gated real template whose document.xml uses only supported vocabulary
- **WHEN** reverse runs and the script re-executes
- **THEN** document.xml is rebuilt through the DSL channel byte-equal and per-part coverage for it reports 100%

#### Scenario: rsid attributes round-trip

- **GIVEN** a source paragraph carrying `w:rsidR` and `w:rsidRDefault` attributes
- **WHEN** the paragraph is extracted and rebuilt
- **THEN** the rebuilt `<w:p>` carries the same attributes with the same values in the same order

#### Scenario: unsupported long-tail form stays raw with attribution

- **GIVEN** a document.xml containing an element outside the supported vocabulary
- **WHEN** reverse runs
- **THEN** the part stays on the raw channel, Stage B remains green, and the form-gap report names the element


<!-- @trace
source: word-canonical-forms
updated: 2026-07-09
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Content slots work on upgraded real templates

A real Word document whose document.xml has upgraded to the DSL channel SHALL accept slot designation: the slotted script executes with caller-provided content producing a docx whose non-slot parts are byte-equal to the reference and whose designated positions carry the new content with the reference's formatting intact.

#### Scenario: title and body slots on the real template

- **GIVEN** the env-gated real template upgraded to the DSL channel with paragraphs designated title and body
- **WHEN** the slotted script executes with new title and body text
- **THEN** the output docx carries the new text in those positions, sibling parts byte-equal to the reference, and the reference's styles and section layout intact

<!-- @trace
source: word-canonical-forms
updated: 2026-07-09
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Authoring path emits transcoder-canonical document.xml

Documents built through the authoring API (create-from-scratch `WordDocument` plus paragraph append/insert with plain or formatted runs) and saved by the docx writer SHALL produce a `word/document.xml` that reverse extraction upgrades to the DSL channel, restricted to the extractor's current canonical subset (pure-paragraph content). The writer SHALL emit compact element-only structure (no whitespace-only text nodes between elements), and the create-from-scratch document root SHALL declare the full Word-canonical namespace cloud (every namespace declaration plus `mc:Ignorable`, values and attribute order captured from the real-Word baseline fixture). Conformance SHALL be achieved entirely on the writer side: the extractor's gates (element-only strictness, paraId requirement, byte-equal trial, minimal authoring-default root vocabulary) remain unchanged, and the extractor SHALL NOT synthesize missing attributes or normalize whitespace to admit non-canonical input.

#### Scenario: pure-paragraph authoring document upgrades to the DSL channel

- **WHEN** a document is created from scratch via the authoring API, paragraphs are appended through the authoring chokepoints, the document is saved, and reverse extraction runs on the saved package
- **THEN** the coverage report lists `word/document.xml` with `channel: dsl` and per-part DSL coverage 100%

#### Scenario: exported script rebuilds the authoring document byte-equal

- **WHEN** the script exported from such a document is executed to rebuild a docx
- **THEN** the rebuilt `word/document.xml` bytes equal the source part bytes exactly

#### Scenario: authoring output contains no inter-element whitespace

- **WHEN** an authoring-built document is saved
- **THEN** parsing `word/document.xml` yields element-only children under `w:document` and `w:body` with no text nodes between elements

#### Scenario: create-from-scratch root carries the full Word-canonical cloud

- **WHEN** a document with no captured root attributes is saved and reverse extraction runs
- **THEN** the root open tag matches the baseline fixture's namespace cloud byte-for-byte, the operation log contains one `setDocumentRoot` operation reproducing that cloud, and the part still upgrades to the DSL channel

#### Scenario: bypassing the authoring chokepoints stays on the raw channel

- **WHEN** a paragraph is injected into the body without passing through the authoring chokepoints and the saved document is reverse-extracted
- **THEN** the part stays on the raw channel and the form-gap report names `paragraph-no-paraId` with the located path


<!-- @trace
source: authoring-canonical-conformance
updated: 2026-07-18
code:
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - cli/FastOCR
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-verify/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/umbrella-open/SKILL.md
  - .codex/hooks.json
  - mcp/che-word-mcp
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
-->

---
### Requirement: Authoring chokepoints stamp w14:paraId

The paragraph authoring chokepoints (append and both insert variants) SHALL stamp a generated `w14:paraId` on any incoming paragraph whose paraId is nil and SHALL preserve a caller-supplied value verbatim. Generated values SHALL be 8 uppercase hexadecimal characters whose numeric value lies strictly between 0x00000000 and 0x80000000 (exclusive), SHALL be unique among all paragraph paraIds in the target document, and SHALL come from an injectable generator so tests can pin deterministic sequences. Paragraphs parsed from existing packages SHALL keep their source state: a source paragraph without paraId SHALL NOT gain one from loading or re-saving the document.

#### Scenario: appended paragraph receives a generated paraId

- **WHEN** a paragraph with nil paraId is appended through an authoring chokepoint
- **THEN** the serialized `<w:p>` opening tag carries `w14:paraId` with a conforming generated value

##### Example: generated value format

- **GIVEN** a document whose existing paragraphs use paraIds `11111111` and `2AB4C9F0`
- **WHEN** the generator produces the next paraId
- **THEN** the value matches `[0-9A-F]{8}`, differs from both existing values, and its numeric value is greater than 0x00000000 and less than 0x80000000

#### Scenario: caller-supplied paraId is preserved

- **WHEN** a paragraph whose paraId is preset to `3F2A0001` is inserted through an authoring chokepoint
- **THEN** the serialized paragraph carries exactly `w14:paraId="3F2A0001"`

#### Scenario: two insertions never collide

- **WHEN** two paragraphs with nil paraId are inserted into the same document
- **THEN** their generated paraIds differ

#### Scenario: no backfill on round-trip of legacy documents

- **WHEN** an existing package whose paragraphs lack `w14:paraId` is opened and saved without paragraph edits
- **THEN** no paragraph in the written `word/document.xml` gains a `w14:paraId` attribute

<!-- @trace
source: authoring-canonical-conformance
updated: 2026-07-18
code:
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - cli/FastOCR
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-verify/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/umbrella-open/SKILL.md
  - .codex/hooks.json
  - mcp/che-word-mcp
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
-->