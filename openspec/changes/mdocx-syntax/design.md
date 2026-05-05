## Context

`word-aligned-state-sync` (sibling Spectra change, currently at Phase 0 = ooxml-swift v0.30.0) introduces an event-sourced architecture for `.docx` editing: `OperationLog` is the source of truth, `Paragraph` / `Run` / `Table` become typed views over an `XmlNode` tree plus op emitters, and `WordImport` lifts Word edits into operations.

Phase 7 of that change introduces an authoring DSL — the surface humans (and AI) write to produce / modify Word documents. The DSL was sketched in `docs/swift-as-document-source.md` but its grammar was not pinned in a Spectra spec.

This change pins the grammar contract. After it lands and is finalised, Phase 7 implementation has a normative spec (`specs/mdocx-grammar/spec.md`) instead of prose-only design notes.

The discussion that produced this change is captured in:
- `docs/swift-as-document-source.md` — narrative DSL design (will keep, but link to the spec)
- `.claude/rules/extension-first-dsl.md` — file-extension naming rule + AI-as-default-author principle
- `docs/docx-libraries-comparison.md` — comparison vs docx-js / python-docx / pandoc

A spectra-discuss session converged on 7 foundational decisions and 7 open items deferred to this design phase (review).

## Goals / Non-Goals

**Goals:**

- Pin the `.mdocx` DSL grammar so Phase 7 implementation has a normative spec.
- Codify OOXML-mirror naming as the default DSL element-naming policy, with the recorded exception path (Section-as-container) explicitly documented.
- Codify AI-as-default-author as the design constraint that justifies verbosity, explicit-ID burden, and absence of Markdown layer.
- Lock the seven foundational decisions from the spectra-discuss session into spec scenarios so reverse-direction transcoder behavior is determined.
- Surface the seven deferred items (style references, tables, lists, hyperlinks, bookmarks, save semantics, reverse CLI shape) as open items in this design with my recommended direction for proposal review.

**Non-Goals:**

- Implementing the DSL itself (Phase 7 work, blocked on this spec being finalised).
- Modifying `word-builder-swift` — it keeps its docx.js 1:1 mirror role; `WordDSLSwift` is a parallel module.
- Modifying `ooxml-script-transcode` spec — that spec describes transcoder behavior; this change supplies the syntax surface the transcoder reads / writes.
- Designing `.mpdf` / `.mbib` / `.mpptx` syntax — only `.mdocx` here. Future siblings reuse the principles.
- Tooling work (IDE syntax highlighting, file association registration, `macdoc word watch` REPL).
- Conflict resolution policy at the op-log level (covered by `ooxml-word-sync` capability in word-aligned-state-sync).

## Decisions

### Decision 1: Inline grammar = flat `Run` + implicit `String`

Within a paragraph body, plain `String` literals implicitly construct an unstyled `Run`; any non-default formatting requires an explicit `Run("text", bold: true, ...)`.

```swift
Paragraph(id: "ch1-intro") {
    "本章探討"                              // → implicit Run("本章探討")
    Run("意識本質", bold: true)              // explicit Run for any formatting
    "的議題。"
    Run("跟物質。", bold: true, italics: true, color: "#663300")
}
```

**Rationale**: One rule for the writer (string for plain, `Run` for formatted). Reverse direction is 1:1: an OOXML `<w:r>` with no rPr emits a String literal; any rPr present emits an explicit `Run(...)`. Multi-format runs have no special syntax — same `Run(...)` shape, more arguments.

**Alternatives considered:**

- *Wrapper components for single format* (`Bold("X")` / `Italic("X")` etc.). Rejected: introduces case-by-case rule (when to use wrapper vs `Run`), complicates reverse direction (multiple valid emissions for `<w:r w:b="true">`), and adds a wrapper enumeration (`Bold` / `Italic` / `Underline` / ...) the AI must memorize.
- *Modifier chain* (`"X".bold().italic()`). Rejected: chain length ambiguity, weak typing, awkward multi-format, doesn't compose cleanly with custom `WordComponent`.

### Decision 2: Special characters as standalone children (`Tab`, `Break`, `NoBreakHyphen`)

Tab stops, line breaks, no-break hyphens, and similar OOXML inline atoms are first-class children inside paragraph result builders, parallel to `Run` and `String`.

```swift
Paragraph(id: "p1") {
    "Header"
    Tab()
    "Right-aligned by tab stop"
    Break()
    "Continued on new line"
}
```

**Rationale**: These are structurally distinct from `Run` (no text content, no formatting properties — pure inline atoms). Modeling them as standalone children matches the OOXML structure (`<w:tab/>`, `<w:br/>` are sibling children of `<w:r>` content) and keeps op-log emission clean (`{op: "InsertTab", in: "p1", at: ...}` without polluting `Run`'s op shape).

**Alternatives considered:**

- *Run static factory methods* (`Run.tab()`, `Run.break_()`). Rejected: forces these atoms through `Run`'s shape even though they lack text/formatting, complicating the `Run` data model and reverse-emission rules.

### Decision 3: Naming = OOXML term-of-art

DSL element names use OOXML / typesetting terms-of-art (`Run`, `Paragraph`, `Section`, `Table`, `Hyperlink`, `Bookmark`) not invented or domain-translated names (`Format`, `Span`, `Block`, etc.).

**Rationale**: Cross-library consistency (docx-js, python-docx, Apache POI, OpenXML SDK all use these terms) means AI training data has high signal density for these names. Reverse direction maps OOXML elements back to DSL with no naming translation step.

**Alternatives considered:**

- *`Format` instead of `Run`*. Rejected: `Format` semantically refers to formatting properties alone (the `<w:rPr>` content), not the text-plus-formatting bundle that `<w:r>` represents. Using `Format` for the bundle creates confusion when properties bundles need their own type.
- *`Span` instead of `Run`*. Rejected: HTML lineage doesn't carry into OOXML; reverse direction would translate `<w:r>` to `Span` without semantic gain.
- *`Text` instead of `Run`*. Rejected: collides with SwiftUI `Text`; ambiguous level (`Paragraph` also has text content).

### Decision 4: OOXML-mirror principle as default naming policy

DSL element names mirror OOXML element names where 1:1 correspondence exists; deviations require explicit justification (recorded as exceptions in this design or future changes).

**Recorded exception**: `Section` as a DSL container (Decision 6) — OOXML uses sectPr-marker pattern, but DSL container is more natural for AI authoring; compiler bridges the gap.

**Rationale**: This makes adding new DSL elements mechanical (look up the OOXML element, use its name) and keeps reverse direction trivial (OOXML element → DSL element by name lookup). When deviating, the exception is documented so future contributors know the policy is intentionally bent, not forgotten.

**Alternatives considered:**

- *Domain-translated names* (`Block` for `Paragraph`, `Span` for `Run`, etc.). Rejected: forces the reverse-transcoder to maintain a translation table, AI to learn two vocabularies (OOXML when reading docs, DSL when writing).
- *No principle* (case-by-case naming). Rejected: leads to inconsistency over time as new elements are added by different authors.

### Decision 5: No semantic shortcuts (no `Heading1`-`6`, no `Bold(...)`, no `Quote(...)`)

DSL has no convenience wrappers that map onto OOXML elements that don't exist as distinct classes. Headings are `Paragraph(style: .heading1)`, bold text is `Run("X", bold: true)`, list items are `Paragraph(style: .listItem, numbering: ..., level: ...)`.

**Rationale**: OOXML doesn't have `<w:heading>` — headings are `<w:p w:pStyle="Heading1">`. Adding `Heading1(...)` to the DSL would create reverse-direction ambiguity (same OOXML element could emit `Heading1("X")` or `Paragraph(style: .heading1) { "X" }`). Rejecting shortcuts keeps reverse 1:1.

The verbosity cost falls on the reader (slightly more characters to parse `Paragraph(style: .heading1) { "X" }` vs `Heading1("X")`) but is zero cost for AI as the default author (Decision 8 / cross-cutting principle).

**Alternatives considered:**

- *Allow semantic shortcuts but pin reverse direction to one canonical form*. Rejected: the moment a shortcut exists, AI sometimes generates the shortcut and sometimes generates the canonical form. Reverse-direction normalization across re-runs makes diff churn rather than reducing it.

### Decision 6: `Section` as DSL container despite OOXML marker structure

DSL writes:

```swift
Section(id: "front", type: .continuous) {
    Paragraph(...)
    Paragraph(...)
}
Section(id: "main", type: .nextPage) {
    Paragraph(...)
}
```

Compiler inverts this into the OOXML pattern where each section's properties live as a sentinel `<w:sectPr>` element after its last paragraph (or within the final paragraph's `<w:pPr>` for non-terminal sections).

**Rationale**: Container syntax is far more natural for AI authoring (and human reading). The OOXML marker pattern is a historical XML 1.0 artifact (no nested-friendly tooling at the time) — semantically a section IS a container of paragraphs. Compiler does the inversion at serialization time; DSL stays clean.

**Alternatives considered:**

- *Strict OOXML structure* (paragraphs siblings of `SectionMarker(...)`). Rejected: AI would constantly produce ill-structured documents (forgetting the marker pattern), and the DSL becomes a thin wrapper over XML rather than a writing-facing tool.
- *Hybrid* (allow both). Rejected: two valid representations means non-determinism in reverse direction.

### Decision 7: Component-aware op log (Option γ: `BeginComponent` / `EndComponent`)

Custom `WordComponent` types emit a pair of op-log entries that bracket the operations produced by the component's body:

```jsonl
{"op": "BeginComponent", "type": "Summary", "id": "ch1-summary"}
{"op": "InsertParagraph", "id": "ch1-summary-frame", "in": "ch1-summary", "at": 0}
{"op": "SetRuns", "id": "ch1-summary-frame", "runs": [...]}
{"op": "EndComponent", "id": "ch1-summary"}
```

Reverse direction recognises the `BeginComponent` / `EndComponent` envelope and reconstructs the call site as `Summary(id: "ch1-summary") { ... }`.

**Rationale**: AI iteration depends on reverse direction returning `.mdocx` source that preserves the component hierarchy AI wrote. Without component metadata in the op log, reverse flattens components into raw paragraphs, and AI's next round-trip loses the component abstraction.

**Risk acknowledged**: This adds two op types (`BeginComponent`, `EndComponent`) that have no OOXML element correspondence — a deliberate exception to the OOXML-mirror principle at the op-log level (not at the DSL level). The exception is justified by AI workflow but should be flagged to anyone scanning the op-log for a clean OOXML round-trip.

**Alternatives considered:**

- *α (opaque component)* — single op-log entry per component with derived child IDs by naming convention. Rejected: rigid naming rule, collision risk, partial reverse fidelity.
- *β (transparent component)* — component disappears from op log entirely. Rejected: AI cannot reconstruct component structure on next round-trip; component abstraction is lost.
- *Compile-time macro* — components fully expand at Swift compile time, op log sees only raw ops. Rejected: same problem as β at the op-log layer.

### Decision 8: AI as default author — cross-cutting principle

Every grammar decision in this change resolves trade-offs by treating AI as the primary author of `.mdocx` files. Verbosity is free (AI doesn't tire), explicit-ID requirement is friction-free (AI is consistent), Markdown layer (rejected in `docs/swift-as-document-source.md` §3.5) provides no ergonomic benefit but introduces determinism risk.

**Recorded as a design rule** in `.claude/rules/extension-first-dsl.md` ("Identify default author first" section). When designing future DSLs, the first question is "who writes it?" — the answer reorders all subsequent trade-offs.

**Rationale**: Without this principle pinned, future contributors will see verbosity (`Paragraph(style: .heading1) { Run("X", bold: true) }`) and propose shortcuts that re-introduce reverse-direction ambiguity. The principle is the load-bearing reason every decision in this change went in the verbose-but-deterministic direction.

## Grammar reference (composition tree)

Non-normative quick-reference card for "what nests in what". The normative contract lives in `specs/mdocx-grammar/spec.md` Requirements + Scenarios; this tree summarises the legal child sets at each layer. Notation: `[A | B]*` = zero or more of either; `[X]+` = one or more; `→` = container body; `└─` = nesting.

```
WordDocument                                       (top-level result builder entry)
  └─ [Section]+                                    (one or more required)
       └─ [Paragraph | Table | Hyperlink | Bookmark | WordComponent]*
            ├─ Paragraph body : [String | Run | Tab | Break | NoBreakHyphen | Hyperlink | Bookmark]*
            │                   (String literal → implicit unstyled Run)
            ├─ Run             : leaf  (text + optional format flags: bold / italics / color / font / size / ...)
            ├─ Tab             : leaf  (no children, no text)
            ├─ Break           : leaf  (no children, no text)
            ├─ NoBreakHyphen   : leaf  (no children, no text)
            ├─ Hyperlink       : container → [String | Run | Tab | Break]*    (inline content only)
            ├─ Bookmark        : container → [Paragraph body]*                (default form)
            │                    or paired-marker form: BookmarkStart / BookmarkEnd as siblings of Paragraph
            ├─ Table           → [TableRow]+
            │                     └─ TableCell  → [Paragraph]+
            │                           └─ Paragraph body (recursive — same legal child set as above)
            └─ WordComponent   : user-defined type whose `body` expands to any of the above
                                 (op log brackets the expansion with BeginComponent / EndComponent)
```

**Reading hints:**

- `WordComponent` is the only extension point. Library users define new structural building blocks by conforming a type to `WordComponent` and writing its `body` from the legal element set above. The op log's `BeginComponent` / `EndComponent` envelope (Decision 7) preserves the component identity through reverse round-trip.
- `Section` exists at the DSL level only. At serialisation it inverts to OOXML's marker-pattern (`<w:sectPr>` after the section's last paragraph) per Decision 6.
- Style references (Open Item 1 → spec Requirement) attach to `Paragraph` and `Run` via a typed `WordStyle` enum, not nested in this composition tree.
- Lists (Open Item 3 → spec Requirement) reuse `Paragraph(style: .listItem, numbering: ..., level: ...)` — there is no `List` / `ListItem` container in this tree.

## Risks / Trade-offs

- *AI workflow becomes a hard dependency* → Mitigation: Spec scenarios for reverse direction (next artifact: `mdocx-grammar` spec) lock the contract; if AI workflow proves impractical, rework is contained to Phase 7 implementation, not this contract.
- *OOXML-mirror principle invites bikeshed on each new element* → Mitigation: Decision 4 records the principle + the one acceptable deviation pattern (Section-as-container with explicit justification). Future elements either match OOXML naming or document why not.
- *Component-aware op log diverges from OOXML* → Mitigation: Decision 7 acknowledges the divergence at op-log level only (not DSL or final docx); spec scenario will assert that `BeginComponent` / `EndComponent` round-trip to byte-equal output (no docx artifacts from the component metadata).
- *Verbosity may discourage human authors* → Acknowledged as acceptable: human authors are explicitly the secondary use case (Decision 8). If human authoring becomes a primary use case later, a separate convenience layer can be added without touching this grammar (it would be a parallel DSL, like `word-builder-swift` is parallel to `WordDSLSwift`).
- *Open items deferred (next section) may break the locked decisions* → Mitigation: each open item below has a recommended direction noted; if proposal review reveals one breaks an existing locked decision, that locked decision will be re-opened explicitly.

## Open Questions

These items have a recommended direction but require proposal review before being locked into spec scenarios. They are deferred from the discuss-mode session to keep momentum and converge here.

### Open Item 1: Style reference shape

**Recommendation**: Typed enum with define-on-first-use.

```swift
extension WordStyle {
    static let titleBrown = WordStyle(font: "Noto Serif TC", fontSize: 36, color: "#663300", bold: true)
}

Paragraph(id: "title", style: .titleBrown) { "賽斯書輕導讀" }
```

First reference to `.titleBrown` emits `{op: "DefineStyle", id: "titleBrown", ...}`; subsequent references re-use.

**Why recommended**: Type-safe, IDE auto-complete, matches Decision 5 (no shortcuts — style is the only way to differentiate paragraph kinds).

**To review**: do we permit `style: "titleBrown"` raw-string fallback for incrementally adopting? Probably no — breaks reverse-direction determinism.

### Open Item 2: Table grammar

**Recommendation**: Mirror OOXML three-layer structure.

```swift
Table(id: "tbl1", style: .standardTable) {
    TableRow(id: "tbl1-r0") {
        TableCell(id: "tbl1-r0-c0") { Paragraph(id: "tbl1-r0-c0-p0") { "Header A" } }
        TableCell(id: "tbl1-r0-c1") { Paragraph(id: "tbl1-r0-c1-p0") { "Header B" } }
    }
    TableRow(id: "tbl1-r1") { ... }
}
```

**Why recommended**: Matches `<w:tbl><w:tr><w:tc><w:p/>...</w:tc></w:tr>...</w:tbl>` 1:1; AI can pattern-match.

**To review**: ID auto-derivation for cells (rows × cols can be hundreds of explicit IDs); merge syntax (`vMerge` / `gridSpan`); table styles vs inline cell properties.

### Open Item 3: Lists (numbered / bullet)

**Recommendation**: Mirror OOXML — lists are paragraphs with `numPr` reference, not nested DSL containers.

```swift
NumberingDefinition(id: "myList", style: .bullet)

Paragraph(id: "li1", style: .listItem, numbering: .myList, level: 0) { "Item 1" }
Paragraph(id: "li2", style: .listItem, numbering: .myList, level: 0) { "Item 2" }
Paragraph(id: "li3", style: .listItem, numbering: .myList, level: 1) { "Sub-item 2.1" }
```

**Why recommended**: OOXML-faithful. Nested-list DSL (`List { Item; Item; List { Item } }`) would require compile-time flattening to `numPr` paragraphs and a complex reverse-direction inverse — breaks alignment determinism.

**To review**: this contradicts the "lists are nested" intuition humans bring; AI doesn't care, but spec writers and reviewers will. Worth the OOXML-mirror cost?

### Open Item 4: Hyperlinks

**Recommendation**: Container, with target type discriminated by enum.

```swift
Paragraph(id: "p1") {
    "see "
    Hyperlink(to: .anchor("ch1-intro")) { "Chapter 1" }
    " or "
    Hyperlink(to: .url("https://example.com")) { "external" }
}
```

**Why recommended**: OOXML `<w:hyperlink>` is a container; matches.

**To review**: `Bookmark` reference vs anchor reference (does `.anchor("ch1-intro")` need to validate the bookmark exists at compile time?).

### Open Item 5: Bookmarks (paired markers, possibly cross-paragraph)

**Recommendation**: Default to container; provide escape hatch for cross-paragraph spans.

```swift
// Default (single-element span):
Bookmark(id: "intro-text") { "本章探討..." }

// Escape hatch (cross-paragraph):
BookmarkStart(id: "ch1-span")
Paragraph(...)
Paragraph(...)
BookmarkEnd(id: "ch1-span")
```

**Why recommended**: 95 % of bookmarks span a single element; container is natural. Cross-paragraph bookmarks exist but rare; explicit escape hatch keeps DSL honest about their existence.

**To review**: does this leak too much OOXML internals (`BookmarkStart` / `BookmarkEnd`) into the DSL surface? Alternative: `Bookmark(id:, spans: [...])` with array of element references, but that re-introduces positional ambiguity.

### Open Item 6: `save(to:)` semantics — atomic three-file write

**Recommendation**:

```swift
try doc.save(to: URL(fileURLWithPath: "賽斯書.docx"))
// Writes atomically:
//   賽斯書.docx
//   賽斯書.docx.oplog.jsonl
//   賽斯書.docx.snapshot.json
// Failure of any leaves all three at previous state.
```

**Why recommended**: All three files form one logical state (docx + history + snapshot for diff); partial success would corrupt sync.

**To review**: atomic-write strategy on macOS (write to .tmp + atomic rename × 3, or single-tmp-dir + rename); behavior if `.docx` is locked by Word (refuse write with structured error per `word-aligned-state-sync` Non-Goals).

### Open Item 7: Reverse CLI shape

**Recommendation**:

```bash
macdoc word reverse <docx> --to-mdocx <output.mdocx.swift> [--from-oplog]
```

`--from-oplog` (default true if `.docx.oplog.jsonl` exists alongside) replays the oplog to current state; without it, reverse-engineers the docx-only state.

**Why recommended**: matches existing `macdoc convert` CLI pattern; explicit `--from-oplog` toggle gives author control over "current state" vs "docx-only initial state".

**To review**: should reverse refuse to overwrite an existing `.mdocx.swift` without `--force`? Probably yes (avoid accidental author work loss).
