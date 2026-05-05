## 1. Lock open items into spec scenarios

These tasks resolve the seven items deferred from spectra-discuss into final spec scenarios. Each task adds a corresponding Requirement + Scenarios block to `specs/mdocx-grammar/spec.md` once the open item is reviewed and accepted (or amended) by the proposal reviewer. Sequential per item but the seven items themselves are independent and parallelizable.

- [x] 1.1 Review and lock Open Item 1: Style reference shape — typed enum with define-on-first-use; add corresponding Requirement + Scenarios to mdocx-grammar spec
- [x] 1.2 [P] Review and lock Open Item 2: Table grammar — three-layer Table / TableRow / TableCell mirror; add Requirement + Scenarios
- [x] 1.3 [P] Review and lock Open Item 3: Lists (numbered / bullet) — numPr-reference grammar with NumberingDefinition; add Requirement + Scenarios
- [x] 1.4 [P] Review and lock Open Item 4: Hyperlinks — container with target enum (anchor / url / mailto / bookmark); add Requirement + Scenarios
- [x] 1.5 [P] Review and lock Open Item 5: Bookmarks (paired markers, possibly cross-paragraph) — container default plus BookmarkStart / BookmarkEnd escape hatch; add Requirement + Scenarios
- [x] 1.6 [P] Review and lock Open Item 6: `save(to:)` semantics — atomic three-file write of docx + oplog.jsonl + snapshot.json; add Requirement + Scenarios
- [x] 1.7 [P] Review and lock Open Item 7: Reverse CLI shape — `macdoc word reverse <docx> --to-mdocx <out> [--from-oplog]`; add Requirement + Scenarios

## 2. Spec validation across all locked decisions

- [x] 2.1 Validate that the eight locked Decisions in design.md are each reflected in mdocx-grammar spec scenarios: Decision 1: Inline grammar = flat `Run` + implicit `String`; Decision 2: Special characters as standalone children (`Tab`, `Break`, `NoBreakHyphen`); Decision 3: Naming = OOXML term-of-art; Decision 4: OOXML-mirror principle as default naming policy; Decision 5: No semantic shortcuts (no `Heading1`-`6`, no `Bold(...)`, no `Quote(...)`); Decision 6: `Section` as DSL container despite OOXML marker structure; Decision 7: Component-aware op log (Option γ: `BeginComponent` / `EndComponent`); Decision 8: AI as default author — cross-cutting principle
- [x] 2.2 [P] Validate that all eight ADDED Requirements in mdocx-grammar spec — File extension and dual-extension pattern, Flat Run with implicit String literal inline grammar, Special-character inline atoms as standalone children, OOXML-mirror element naming, No semantic shortcuts for OOXML-style attributes, Section as DSL container with compile-time marker inversion, Component-aware op log via BeginComponent and EndComponent, Mandatory explicit identifiers on structural elements — each carry at least one Scenario with a concrete Example block (SBE)
- [x] 2.3 Update docs/swift-as-document-source.md to cross-reference openspec/specs/mdocx-grammar/spec.md as the canonical grammar contract once this change archives, and link from .claude/rules/extension-first-dsl.md "已註冊副檔名" table to the spec

## 3. Module scaffold (Phase 7 entry point)

These tasks land the empty WordDSLSwift module so Phase 7 of word-aligned-state-sync (which implements the spec) has a clean starting target. No implementation logic in these tasks — only file structure and package declarations.

- [x] 3.1 Add WordDSLSwift product and target declarations to packages/ooxml-swift/Package.swift; depend on existing OOXMLSwift target
- [x] 3.2 [P] Create empty WordDSLSwift module file skeleton (one Swift file per top-level DSL element type from the spec — WordDocument, Section, Paragraph, Run, Tab, Break, NoBreakHyphen, Hyperlink, Bookmark, Table, TableRow, TableCell, WordComponent, WordBuilder); each file contains only the empty type declaration with a header comment pointing to specs/mdocx-grammar/spec.md as the source of truth for Phase 7 implementation
- [x] 3.3 [P] Create WordDSLSwiftTests target with placeholder test that verifies the module compiles cleanly and all top-level type names are reachable
