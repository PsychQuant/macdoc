## Context

macdoc's existing docx writer is `OOXMLSwift.DocxWriter`, a low-level model-to-file writer used internally by `md-to-word-swift`, `html-to-word-swift`, and `tex-to-docx-swift`. There is no fluent public API for developers who want to write docx files programmatically from Swift code. The parallel already exists on the markdown side: `markdown-swift` ships both low-level primitives and a `MarkdownBuilder` fluent API (captured in the `markdown-builder` spec).

Users (per the 2026-04-06 conversation on issue #71) want the equivalent of `docx.js` (dolanmiu/docx, npm `docx@9.6.1`) — a declarative API where you pass nested options objects and get a `.docx` back. The npm `docx` package has been cloned to `reference/docx-js/` (MIT, shallow) to serve as the single source of truth for API naming and shape.

**Stakeholders**: Swift developers writing scripts or services that produce Word documents; authors of future macdoc converters who might want a fluent alternative to raw `OOXMLSwift` model construction.

**Constraints**:

- Must stay within macdoc's native-macOS policy (no external deps beyond what `OOXMLSwift` already uses).
- Must not refactor existing converters — they are producing stable output and changing them would widen blast radius.
- Must version-mirror `docx.js` so "which docx.js version does this correspond to" is answerable at a glance.
- MIT-licensed reference code in `reference/docx-js/` is read-only; no code copying, only API shape alignment.

## Goals / Non-Goals

**Goals:**

- Ship `word-builder-swift` as a new standalone Swift package under `PsychQuant/word-builder-swift`.
- Public API mirrors `docx.js` 9.6.x top-level types 1:1 — same class names (`Document`, `Paragraph`, `TextRun`, `Table`), same option field names where Swift allows, same constructor shapes.
- Extend `OOXMLSwift.DocxWriter` with an in-memory `writeData(_:) throws -> Data` method so `Packer.toData()` can return bytes without touching disk.
- Phase 1 covers the subset needed to write a body of text, headings, and tables into a single section.
- Ship five runnable examples translated directly from `docx.js` README snippets so users can see API correspondence.

**Non-Goals:**

- Multi-section documents, headers/footers, numbering, hyperlinks, bookmarks, footnotes, images, checkboxes, textboxes, TOCs, core properties, or global styles — all deferred to Phase 2+.
- Refactor of `md-to-word-swift` / `html-to-word-swift` / `tex-to-docx-swift` to use `word-builder-swift`.
- Swift `@resultBuilder` DSL sugar (`Document { ... }` trailing closure form).
- `Packer.toStream()` streaming output.
- `macdoc convert --to docx file.swift` runtime Swift compilation.

## Decisions

### Decision: API mirrors docx.js naming 1:1

**Approach**: Public types in `WordBuilderSwift` module use the same names as `docx.js` exports from `src/index.ts` (`Document`, `Paragraph`, `TextRun`, `Table`, `TableRow`, `TableCell`, `Packer`, `HeadingLevel`, `AlignmentType`). Option field names on those types match the TypeScript `IXxxOptions` field names.

**Why**: The only compelling reason to ship this package is "a `docx.js` user can translate their code to Swift line-by-line." Any renaming for Swift aesthetics defeats that goal.

**Alternatives considered**:

- *Swift-native naming* (e.g., `WordDocument`, `TextBlock`): rejected — diverges from the mirror and makes the package redundant with `OOXMLSwift`.
- *Namespaced prefix* (e.g., `WBS.Document`): rejected — adds friction without value once the user imports `WordBuilderSwift`.

### Decision: Options use Swift struct init parameters with defaults

**Approach**: Every type accepts its configuration as an init parameter list with defaults:

```swift
Paragraph(
    heading: HeadingLevel? = nil,
    alignment: AlignmentType? = nil,
    children: [ParagraphChild] = [],
    spacing: Spacing? = nil
)
```

**Why**: `docx.js` users pass `{ heading: ..., children: [...] }` options objects. Swift init params with defaults are the closest language-level equivalent, preserving field names and ordering. Callers get type checking, autocomplete, and can omit fields the same way.

**Alternatives considered**:

- *Result builder DSL* (`@resultBuilder`): rejected — diverges from `docx.js` shape, splits documentation into "builder form" vs "options form," and complicates the tutorial.
- *Configuration struct passed as single argument* (`Paragraph(options: ParagraphOptions(...))`): rejected — adds a wrapping layer with no upside.

### Decision: TextRun is a String-overload convenience wrapper over Run

**Approach**: Ship both `Run` (full options) and `TextRun` (`TextRun(String)` and `TextRun(text:bold:italics:...)`). `TextRun` is a shim that forwards to `Run`.

**Why**: `docx.js` `src/file/paragraph/run/text-run.ts:24` does exactly this. Users mostly write `new TextRun("hello")` or `new TextRun({ text: "hello", bold: true })`; forcing them to always call `Run(text: ...)` would break the mirror.

**Alternatives considered**:

- *Single `TextRun` type only*: rejected — users who want to build custom run types (symbol runs, footnote-reference runs) in future phases expect `Run` as the base class.
- *Single `Run` type only*: rejected — breaks the `TextRun` mental model from `docx.js`.

### Decision: Packer is a static-method facade over DocxWriter.writeData

**Approach**:

```swift
public enum Packer {
    public static func toData(_ document: Document) throws -> Data
    public static func toFile(_ document: Document, url: URL) throws
    public static func toBase64String(_ document: Document) throws -> String
}
```

Internally, `Document` is converted to an `OOXMLSwift.WordDocument` and passed to `DocxWriter.writeData(_:)`.

**Why**: `docx.js` `Packer.toBuffer(doc)` / `.toBase64String(doc)` are free functions on a namespace, not instance methods. Swift `enum` with `static` methods is the idiomatic equivalent (prevents accidental instantiation).

**Alternatives considered**:

- *Instance method on `Document`* (`doc.toData()`): rejected — diverges from `docx.js`.
- *Global functions*: rejected — pollutes the module namespace.

### Decision: OOXMLSwift.DocxWriter gains writeData

**Approach**: The existing `write(_:to: URL)` does: create tempDir → write XML files into dirs → zip dirs → copy zip to target URL. Refactor the pipeline into two phases: (1) "build the zip archive" returning a `Data`, (2) "write the Data to URL." `write(_:to:)` calls both; `writeData(_:)` calls only the first.

**Why**: `Packer.toData()` is a first-class `docx.js` API (`Packer.toBuffer(doc)` returns `Promise<Buffer>`). Without in-memory output, `word-builder-swift` would either fork the writer logic or write-then-read through a tempfile — both ugly. This is a mechanical refactor of the existing zip step.

**Alternatives considered**:

- *Keep `DocxWriter` unchanged, tempfile dance inside `Packer`*: rejected — two I/O round trips per call and a tempfile cleanup burden.
- *Fork `DocxWriter` into `word-builder-swift`*: rejected — two implementations to keep in sync.

### Decision: Phase 1 accepts [Section] but only emits sections[0]

**Approach**: `Document(sections:)` takes `[Section]`. In Phase 1, the converter takes `sections.first` (or throws `WordBuilderError.emptyDocument` if empty) and flattens its children into the body. A `#warning` or deprecation note tags multi-section input as Phase-2-only.

**Why**: `ooxml-swift` models sections via paragraph-break properties in a flat body, not via a section-object array. Properly mapping multi-section documents with per-section headers, footers, and page setup is Phase-2 work. But the API shape must accept `[Section]` from day one or Phase 2 breaks the published interface.

**Alternatives considered**:

- *Phase 1 accepts only `Section` singular*: rejected — forces a source-breaking change in Phase 2.
- *Phase 1 emits all sections*: rejected — Phase 1 would overrun its ~500 LoC budget and delay shipping.

### Decision: Version 0.9.x tracks docx.js 9.6.x

**Approach**: First release `0.9.0` corresponds to `docx.js` `9.6.x`. When `docx.js` bumps to `9.7.x`, our next release is `0.9.1` (patch) until we add new mirrored API, then `0.10.0` (minor tracking `9.7.x`). Major `0.x.y` → `1.0.0` only when the package covers all of `docx.js` and is production-stable.

**Why**: The user's first question is "which `docx.js` version does this mirror?" The version number answers directly. Patch is independent because bugfixes in our code don't correspond to `docx.js` releases.

**Alternatives considered**:

- *Exact mirror (`9.6.1` → our `9.6.1`)*: rejected — jumping to `9.x` implies production maturity we don't have.
- *Independent semver*: rejected — user has to cross-reference a compatibility table.

## Risks / Trade-offs

**API drift vs `docx.js` over time** → Mitigation: pin `reference/docx-js/` to a specific tag (`9.6.1` at time of this change). Re-clone to a new tag only as a deliberate update, not automatically.

**Swift-TS impedance mismatch on option shapes** (TS `readonly` arrays, union types, `type | undefined`) → Mitigation: Phase 1 ships five concrete examples, and if any of those examples expose awkward translations, capture the awkwardness in `design.md` as a documented departure from the mirror rather than re-designing the API.

**`ooxml-swift` `writeData` refactor breaks existing converters** → Mitigation: keep `write(_:to: URL)` signature unchanged. `writeData` is a new method; `write` calls it internally then writes the bytes to the URL. Existing callers see identical behaviour. Add an integration test in `ooxml-swift` that round-trips a document through both APIs and diffs the output bytes.

**Naming collision: `OOXMLSwift` already exports a `Paragraph` and `WordBuilderSwift` also exports `Paragraph`** → Mitigation: users import *either* `WordBuilderSwift` *or* `OOXMLSwift`, not both. Document this explicitly in `word-builder-swift` README. If a caller really needs both, Swift module-qualified names (`OOXMLSwift.Paragraph`) disambiguate.

**Maintenance of two parallel APIs** (low-level `OOXMLSwift` + high-level `WordBuilderSwift`) → Accepted: `OOXMLSwift` is the converter-internal layer, `WordBuilderSwift` is the author-facing layer. Two layers is the cost of keeping the mirror clean; merging would entangle them.

**Phase 1 can't write a "pretty" docx because it lacks headers/footers/numbering** → Accepted: Phase 1 is a scaffold for shape validation. The first end-user "is it pretty enough" test is Phase 2 when Header/Footer/Numbering ship.

## Migration Plan

Phase 1 is net-new package; no migration of existing callers. Rollout:

1. Land `OOXMLSwift.DocxWriter.writeData(_:)` as a standalone PR in `PsychQuant/ooxml-swift`. Tag `0.x.y+1`.
2. Create `PsychQuant/word-builder-swift` repo with initial commit. Tag `0.9.0`.
3. Update `PsychQuant/macdoc` `Package.swift` to pin `word-builder-swift from: "0.9.0"`. This enables `import WordBuilderSwift` for future CLI features but adds no user-visible CLI changes in Phase 1.

Rollback: if Phase 1 reveals fatal design flaws, yank `word-builder-swift 0.9.0` from the `PsychQuant` org (or mark deprecated), remove the `macdoc` dependency, and reopen issue #71 with findings. `OOXMLSwift.writeData` stays — it's useful independent of `word-builder-swift`.

## Open Questions

None — all six open questions from issue #71's diagnosis were resolved in the `/spectra-discuss` round (version strategy, naming, Phase 1 scope, writeData PR timing, single-section first, PsychQuant org repo location). If implementation surfaces new questions, they will be captured in `tasks.md` as blockers and escalated via comment on #71.
