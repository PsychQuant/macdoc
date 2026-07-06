# ooxml-operation-reducer Specification

## Purpose

TBD - created by archiving change 'operation-reducer-impl'. Update Purpose after archive.

## Requirements

### Requirement: Pure replay of operation log to tree

`OperationReducer.materialize(log: OperationLog, base: XmlTree) throws -> XmlTree` SHALL be a pure function: same `(log, base)` input always produces the same output `XmlTree`. The reducer SHALL NOT mutate the caller's `base` argument; the returned tree is a deep copy with all log ops applied.

The reducer SHALL apply `log.entries` in source-array order. For each entry, the reducer SHALL translate the `Operation` case into the appropriate `XmlNode` / `XmlTree` mutation primitive call (e.g., `setText` op replaces the target node's `<w:t>` children with the new text; `updateAttribute` op calls `node.setAttribute`).

The reducer SHALL throw a typed `ReducerError` when an op cannot be applied. The `base` deep copy is discarded on throw — partial trees do not leak to the caller.

#### Scenario: same input produces same output

- **GIVEN** an `OperationLog` `log` with two `setText` entries and a synthesized `XmlTree` `base`
- **WHEN** `OperationReducer.materialize(log: log, base: base)` is called twice with the same arguments
- **THEN** both returned trees SHALL fingerprint-equal via `XmlNode.normalizedFingerprint()`

#### Scenario: caller's base tree is not mutated

- **GIVEN** a synthesized `XmlTree` `base` with a `<w:p>` root
- **WHEN** the reducer is called with a log containing a `setText` op targeting the root
- **THEN** the returned tree SHALL contain the new text
- **AND** the original `base` tree SHALL be unchanged (root's children identical to pre-call state)


<!-- @trace
source: operation-reducer-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143700.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-071551.log
-->


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
### Requirement: Time-travel state snapshots

`OperationReducer.state(log: OperationLog, base: XmlTree, at point: ReplayPoint) throws -> XmlTree` SHALL materialize the tree state at a specific replay point. `ReplayPoint` SHALL be an `Equatable, Sendable` enum with these cases:

- `.latest` — equivalent to `materialize(log:base:)` (replay all entries)
- `.index(Int)` — replay `log.entries[0..<N]` (first N entries)
- `.timestamp(Date)` — replay every entry whose `LogEntry.timestamp <= cutoff`, in source-array order

`.index(0)` SHALL return a deep copy of `base` unchanged. `.index(log.entries.count)` SHALL be equivalent to `.latest`. Out-of-range index (`< 0` or `> log.entries.count`) SHALL throw `ReducerError.malformedOp(opID: <some opID>, reason: "index out of range")`.

`.timestamp` SHALL preserve source-array order; timestamps in the log are not guaranteed monotonically increasing because batch transactions may share a timestamp.

#### Scenario: index 0 returns base unchanged

- **GIVEN** a log with 3 entries and a base tree
- **WHEN** `state(log:base: at: .index(0))` is called
- **THEN** the returned tree SHALL fingerprint-equal `base`

#### Scenario: index equal to entries.count is identical to latest

- **GIVEN** a log with 3 entries and a base tree
- **WHEN** both `state(log:base: at: .index(3))` and `state(log:base: at: .latest)` are called
- **THEN** the two returned trees SHALL fingerprint-equal each other

#### Scenario: timestamp filters entries by cutoff

- **GIVEN** a log with 3 entries at timestamps `[t0, t1, t2]` (t0 < t1 < t2) and a base tree
- **WHEN** `state(log:base: at: .timestamp(t1))` is called
- **THEN** the returned tree SHALL be the result of replaying entries[0] and entries[1] only (entry[2] excluded because its timestamp > cutoff)


<!-- @trace
source: operation-reducer-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143700.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-071551.log
-->


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
### Requirement: Undo operation reverses its target

`OperationReducer.undo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree` SHALL materialize the tree as if the entry with `opID == targetOpID` had never been applied. The intervening entries (those after the target in `log.entries`) SHALL see the world without the target's effect, NOT see the target's effect followed by an inversion.

In Phase 2b, undo SHALL be supported for these op cases:
- `setText` (inverse: replace text with the value of the most recent prior `setText` entry for the same ElementID; if none, replace with empty string)
- `setParagraphStyle` (inverse: same logic on `styleId`)

For all other op cases, including `.unknown`, undo SHALL throw `ReducerError.cannotUndo(targetOpID:)`.

If no entry matches `targetOpID`, undo SHALL throw `ReducerError.cannotUndo(targetOpID:)` with that same opID.

#### Scenario: undo of setText reverts text

- **GIVEN** a log with two entries: opA `setText(target=X, text="Old")` and opB `setText(target=X, text="New")`
- **WHEN** `OperationReducer.undo(targetOpID: opB.opID, log: log, base: base)` is called
- **THEN** the returned tree SHALL contain the text `"Old"` at element X (the value before opB)

#### Scenario: undo of unsupported op throws

- **GIVEN** a log entry with op `.insertTable(at: ..., table: ...)`
- **WHEN** `undo` is called targeting that entry's opID
- **THEN** the call SHALL throw `ReducerError.cannotUndo(targetOpID:)`

#### Scenario: undo of nonexistent opID throws

- **GIVEN** an `OperationLog` and a UUID that matches no entry
- **WHEN** `undo` is called with that UUID
- **THEN** the call SHALL throw `ReducerError.cannotUndo(targetOpID:)`


<!-- @trace
source: operation-reducer-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143700.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-071551.log
-->


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
### Requirement: Redo reapplies an undone operation

`OperationReducer.redo(_ targetOpID: UUID, log: OperationLog, base: XmlTree) throws -> XmlTree` SHALL undo a prior `Operation.undo(targetOpID:)` log entry. The reducer walks the log; finds the `.undo` entry whose `targetOpID` matches the argument; on materialize, SKIPS that `.undo` entry so the original op stays in effect.

If no `.undo` entry references `targetOpID`, redo SHALL throw `ReducerError.cannotRedo(targetOpID:)`.

#### Scenario: redo restores the original op's effect

- **GIVEN** a log with three entries: opA `setText(target=X, text="Original")`, opB `undo(targetOpID: opA.opID)`, opC `setText(target=Y, text="Other")`
- **WHEN** `OperationReducer.redo(targetOpID: opA.opID, log: log, base: base)` is called
- **THEN** the returned tree SHALL contain the text `"Original"` at element X (opB skipped)
- **AND** the returned tree SHALL contain the text `"Other"` at element Y (opC applied normally)

#### Scenario: redo without matching undo throws

- **GIVEN** an `OperationLog` with no `.undo` entries
- **WHEN** `redo` is called with any UUID
- **THEN** the call SHALL throw `ReducerError.cannotRedo(targetOpID:)`


<!-- @trace
source: operation-reducer-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143700.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-071551.log
-->


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
### Requirement: Blame returns the operation that last touched an element

`OperationReducer.blame(elementID: ElementID, log: OperationLog) -> LogEntry?` SHALL return the most recent `LogEntry` in `log.entries` whose op references the given `ElementID`. The reducer SHALL walk `log.entries` in REVERSE order and return on first match.

If no entry's op touches the given ElementID, blame SHALL return `nil`.

`.unknown` ops SHALL never count as touching any ElementID (opaque payload).

#### Scenario: blame returns the most recent touching op

- **GIVEN** a log with three entries: opA `setText(target=X, text="A")`, opB `setText(target=Y, text="B")`, opC `setText(target=X, text="C")`
- **WHEN** `OperationReducer.blame(elementID: X, log: log)` is called
- **THEN** the returned `LogEntry` SHALL be opC (most recent op touching X)

#### Scenario: blame returns nil for untouched element

- **GIVEN** a log whose entries' ops never reference ElementID Z
- **WHEN** `OperationReducer.blame(elementID: Z, log: log)` is called
- **THEN** the returned value SHALL be `nil`


<!-- @trace
source: operation-reducer-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143700.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-071551.log
-->


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
### Requirement: Snapshot caching avoids full replay on every read

`OperationReducerCache` SHALL be an `actor` exposing `materialize(log: OperationLog, base: XmlTree) async throws -> XmlTree`. The cache SHALL store the last `(logLength, materializedTree)` pair keyed by `ObjectIdentifier(base.root)`. On a cache hit where `cached.logLength <= log.entries.count`, the cache SHALL replay only the tail (`log.entries[cached.logLength..<log.entries.count]`) starting from the cached materialized tree (deep-copied) instead of replaying from `base` from scratch.

The cache SHALL invalidate implicitly when:
- A different `base.root` ObjectIdentifier is encountered (different cache key)
- `cached.logLength > log.entries.count` (defensively — append-only API prevents this, but JSONL re-load could trigger it)

There SHALL NOT be a public `invalidate()` API — the cache is implicit and self-managing.

The cache SHALL NOT persist across process restarts. Disk-backed caching is a separate Phase 2c concern (sidecar `<docx>.snapshot.json` files).

#### Scenario: tail-replay on cache hit

- **GIVEN** an empty `OperationReducerCache`, a log with 5 entries, and a base tree
- **WHEN** `cache.materialize(log: log, base: base)` is called
- **AND** then `log.append(...)` is called to add 2 more entries
- **AND** then `cache.materialize(log: log, base: base)` is called again
- **THEN** the second call SHALL return the same fingerprint as a fresh `OperationReducer.materialize(log: log, base: base)` would
- **AND** the second call SHALL be tail-replay (only the new 2 entries replayed) — verifiable by injecting a counter into a test op

#### Scenario: cache miss on different base identity

- **GIVEN** a populated cache for `baseA`
- **WHEN** `cache.materialize(log: log, base: baseB)` is called with a different base whose root is a distinct `ObjectIdentifier`
- **THEN** the cache SHALL fall back to full materialize and return the correct result


<!-- @trace
source: operation-reducer-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143700.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-071551.log
-->


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
### Requirement: Apply errors are reported, not swallowed

`OperationReducer` SHALL surface a typed `ReducerError` for any op application failure. The error type SHALL have at least these cases:

- `elementNotFound(opID: UUID, elementID: ElementID)` — the op references an ElementID not present in the tree at replay time
- `malformedOp(opID: UUID, reason: String)` — the op's payload is structurally invalid (e.g., negative row index, out-of-range `.index` ReplayPoint)
- `cannotRedo(targetOpID: UUID)` — `redo` invoked but no matching `.undo` entry exists
- `cannotUndo(targetOpID: UUID)` — `undo` invoked but the target op cannot be inverted (unsupported op kind, opaque `.unknown`, or no matching entry)

The reducer SHALL NOT swallow errors silently. The reducer SHALL NOT log to stderr in lieu of throwing — every failure surfaces to the caller.

#### Scenario: elementNotFound throws when target ID is missing

- **GIVEN** a log entry `setText(target: nonexistentID, text: "x")` and a base tree that contains no node with `nonexistentID`
- **WHEN** `OperationReducer.materialize(log: log, base: base)` is called
- **THEN** the call SHALL throw `ReducerError.elementNotFound(opID: <that entry's opID>, elementID: nonexistentID)`

#### Scenario: malformedOp throws for out-of-range index

- **GIVEN** a log with 3 entries
- **WHEN** `OperationReducer.state(log: log, base: base, at: .index(5))` is called
- **THEN** the call SHALL throw `ReducerError.malformedOp(opID: ..., reason: "index out of range")`


<!-- @trace
source: operation-reducer-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143700.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-071551.log
-->


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
### Requirement: OperationReducerTests pinned coverage

A new test file `Tests/OOXMLSwiftTests/OperationReducerTests.swift` SHALL be added with at least 12 XCTestCase methods pinning the requirements above:

1. `testMaterialize_pureFunction` — same input twice produces same output
2. `testMaterialize_doesNotMutateBase` — caller's base tree unchanged
3. `testMaterialize_appliesSetText` — setText op produces expected text
4. `testState_indexZeroReturnsBaseUnchanged`
5. `testState_indexEqualToCountIsLatest`
6. `testState_timestampFilters`
7. `testState_outOfRangeIndexThrows`
8. `testUndo_setTextReverts`
9. `testUndo_unsupportedOpThrows`
10. `testRedo_restoresOriginalOpEffect`
11. `testBlame_returnsMostRecentTouchingOp`
12. `testCache_tailReplayOnHit`
13. `testReducerError_elementNotFoundOnMissingTarget`

The tests SHALL pass GREEN against the implementation in the same release (no `#if false` gate phase).

#### Scenario: OperationReducerTests passes GREEN

- **WHEN** `swift test --filter OperationReducerTests` runs against this change
- **THEN** every test method SHALL pass
- **AND** the test runner SHALL report at least 12 passing tests with 0 failures

<!-- @trace
source: operation-reducer-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-143700.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-071551.log
-->

---
### Requirement: Reducer is pure relative to its inputs

The reducer SHALL NOT touch the file system, network, environment, or wall-clock time during replay. Operation timestamps embedded in the log are data, not side-effect sources.

#### Scenario: No I/O during replay

- **WHEN** `materialize(log:base:)` runs in a sandbox that traps file and network calls
- **THEN** no traps fire; replay completes purely in memory

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