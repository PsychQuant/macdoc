## Why

`word-aligned-state-sync` (sibling Spectra change) introduces an event-sourced architecture for `.docx` editing — `OperationLog` is the source of truth, `Paragraph` / `Run` / `Table` become typed views over an `XmlNode` tree plus op emitters, and `WordImport` lifts Word edits into operations. Phase 7 of that change ships an authoring DSL written by AI (the primary author for this DSL) so a user can hand AI a goal like "redraft chapter 3" and get a Swift script that, when executed, produces the docx + its op log.

The DSL surface itself was unspecified at the broader change level. This change pins the DSL syntax: file extension, element vocabulary, inline grammar, component model, identity semantics, and the principle of choosing OOXML-mirror naming over human-friendly shortcuts because AI as the default author inverts the ergonomics math (verbosity is free for AI; reverse-direction determinism is non-negotiable).

Two coordinated docs already capture the design discussion (`docs/swift-as-document-source.md`, `.claude/rules/extension-first-dsl.md`); this change formalises the seven foundational decisions plus seven open items into a Spectra spec so Phase 7 implementation has a normative grammar contract instead of prose-only design notes.

## What Changes

- **NEW**: `.mdocx` file extension family (`.mdocx`, future `.mpdf`, `.mbib`, `.mpptx`) under the `m`-prefix convention. Dual-extension default: `mydoc.mdocx.swift` so Swift toolchain treats it as ordinary Swift while macdoc CLI / file watchers dispatch on the `.mdocx` segment.
- **NEW**: `WordDSLSwift` module (separate from `word-builder-swift`, which keeps its docx.js 1:1 mirror role for one-way docx authoring). Provides `WordDocument`, `Section`, `Paragraph`, `Run`, `Tab`, `Break`, `NoBreakHyphen`, `Table`, `TableRow`, `TableCell`, `Hyperlink`, `Bookmark` as result-builder DSL elements, plus `@WordBuilder` result builder and `WordComponent` protocol for user-defined composition.
- **NEW**: Inline grammar — flat `Run` with formatting flags plus implicit `String` literal as plain `Run`. Special characters (`Tab`, `Break`, `NoBreakHyphen`) are standalone children parallel to `Run` / `String`. No `Bold(...)` / `Italic(...)` / `Heading1(...)` semantic shortcuts; everything goes through `Run` parameters or `Paragraph(style: .X)`.
- **NEW**: Component-aware op log — custom `WordComponent` types emit `BeginComponent` and `EndComponent` operations bracketing their body so the reverse direction (`docx + oplog → .mdocx`) can rebuild component hierarchy faithfully. AI-iteration workflow depends on this: AI re-reads current state and must see component structure, not flattened paragraphs.
- **NEW**: Mandatory explicit `id:` parameter on every structural element (`Section`, `Paragraph`, `WordComponent` instances). Compiler rejects element instantiation without `id:`. ID maps directly to `<w:p w14:paraId>` / `<w:bookmarkId>` / generated UUID; required so Word edits can target Swift-side elements without positional ambiguity.
- **NEW**: Section-as-container — DSL writes `Section { ... }` as a true container even though OOXML uses `<w:sectPr>` marker pattern at the end of each section's paragraph run. Compiler inverts container syntax into OOXML marker form on serialization.
- **NEW**: OOXML-mirror naming principle — DSL element names mirror OOXML element names where 1:1 correspondence exists (`Run` ↔ `<w:r>`, `Paragraph` ↔ `<w:p>`, `Table` ↔ `<w:tbl>`, etc.). Recorded as design rule for future DSL element additions.
- **NEW**: AI-as-default-author principle — design rule recorded in `.claude/rules/extension-first-dsl.md`. Verbosity, explicit-ID burden, and absence of Markdown layer are net wins because AI is the primary author and human editing is a secondary use case.
- **NON-BREAKING**: `word-builder-swift` continues unchanged — its docx.js mirror role serves "from-scratch one-way docx generation" use case. `WordDSLSwift` is a separate module for "AI-authored Word-aligned DSL" use case.
- **NON-BREAKING**: Existing `ooxml-script-transcode` capability (in `word-aligned-state-sync` change) covers the forward and reverse transcoder behavior. This change supplies the syntax surface that transcoder reads / writes; spec deltas to `ooxml-script-transcode` are out of scope for this change.

## Capabilities

### New Capabilities

- `mdocx-grammar`: The `.mdocx` DSL surface — file extension contract, element vocabulary (`WordDocument`, `Section`, `Paragraph`, `Run`, `Tab`, `Break`, `NoBreakHyphen`, `Hyperlink`, `Bookmark`, `Table` family), inline grammar (Option A: flat `Run` + implicit `String`), result builder (`@WordBuilder`), component model (`WordComponent` protocol with γ component-aware op-log emission), explicit-ID requirement, OOXML-mirror naming convention, no-shortcut policy, Section-as-container compiler inversion. Becomes the normative grammar specification Phase 7 implementation conforms to.

### Modified Capabilities

(none)

## Impact

- Affected specs: new `mdocx-grammar` capability
- Affected code:
  - New: packages/ooxml-swift/Sources/WordDSLSwift/ (entire new module under ooxml-swift; `WordDocument.swift`, `Section.swift`, `Paragraph.swift`, `Run.swift`, `Tab.swift`, `Break.swift`, `NoBreakHyphen.swift`, `Hyperlink.swift`, `Bookmark.swift`, `Table.swift`, `WordComponent.swift`, `WordBuilder.swift`)
  - New: packages/ooxml-swift/Tests/WordDSLSwiftTests/ (DSL grammar conformance + component-aware op-log emission tests)
  - Modified: packages/ooxml-swift/Package.swift (add WordDSLSwift product / target)
  - Modified: docs/swift-as-document-source.md (link to formal spec; keep narrative)
  - Modified: .claude/rules/extension-first-dsl.md (already updated; cross-link to new capability)
- Affected docs:
  - New: openspec/changes/mdocx-syntax/specs/mdocx-grammar/spec.md (this change)
  - Modified after merge: openspec/specs/mdocx-grammar/spec.md (canonical capability after archive)
- Affected workflow: Phase 7 of word-aligned-state-sync depends on this spec being archived before Phase 7 implementation begins; if this change lands first, Phase 7 inherits a complete grammar contract; if Phase 7 starts before this lands, contract drift is likely.
