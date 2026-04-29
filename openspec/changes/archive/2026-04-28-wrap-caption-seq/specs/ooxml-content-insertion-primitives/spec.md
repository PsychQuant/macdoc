## ADDED Requirements

### Requirement: Document.wrapCaptionSequenceFields converts plain-text caption number portions to SEQ-field runs

`WordDocument.wrapCaptionSequenceFields(...)` SHALL provide a lib-layer entry point for bulk-converting plain-text caption number portions into `<w:fldSimple>`-bearing SEQ-field runs across paragraphs whose `flattenedDisplayText()` matches a user-supplied regex with one numeric capture group. The method SHALL be reusable by both the MCP wrapper (`wrap_caption_seq`) and any other Swift consumer of ooxml-swift.

The method signature SHALL be:

```swift
public mutating func wrapCaptionSequenceFields(
    pattern: NSRegularExpression,
    sequenceName: String,
    format: SequenceField.Format = .arabic,
    scope: TextScope = .body,
    insertBookmark: Bool = false,
    bookmarkTemplate: String? = nil
) throws -> WrapCaptionResult
```

The method SHALL throw `WrapCaptionError.patternMissingCaptureGroup` if `pattern.numberOfCaptureGroups != 1`. It SHALL throw `WrapCaptionError.bookmarkTemplateMissing` if `insertBookmark == true` and (`bookmarkTemplate == nil` OR `bookmarkTemplate` does not contain literal `${number}`).

The method SHALL return `WrapCaptionResult`:

```swift
public struct WrapCaptionResult: Equatable, Sendable {
    public let matchedParagraphs: Int
    public let fieldsInserted: Int
    public let paragraphsModified: [Int]
    public let skipped: [SkippedParagraph]
}

public struct SkippedParagraph: Equatable, Sendable {
    public let paragraphIndex: Int
    public let reason: String
    public let container: String?  // nil for body; reserved for "all" scope cross-container labelling
}
```

The method SHALL be idempotent — paragraphs whose `runs[].rawXML` or `fieldSimples` already contain a `SEQ {sequenceName}` field SHALL be reported in `skipped` with `reason = "already wraps SEQ {sequenceName}"` and SHALL NOT be double-wrapped.

The method SHALL preserve the captured numeric digits as the SEQ field's `cachedResult` so Word renders the original numbering on first open before F9 recalculation; subsequent F9 SHALL recompute counters from `SEQ {sequenceName}` field state, producing the field-driven truth.

The method SHALL emit `<w:fldSimple w:instr=" SEQ {sequenceName} \* {format-flag} ">{captured}</w:fldSimple>` via the existing `SequenceField.toFieldXML()` helper — no new XML construction code paths.

When `insertBookmark == true`, the method SHALL wrap the rewritten SEQ-field run in `<w:bookmarkStart w:name="{template-substituted}" w:id="<unique>">` (immediately before the SEQ-field run) and `<w:bookmarkEnd w:id="<same-unique>">` (immediately after). `${number}` in `bookmarkTemplate` SHALL be substituted with the captured numeric verbatim.

The method's traversal SHALL respect `scope`:

- `.body` walks `body.children` only, recursing into `.table` cells (rows[].cells[].paragraphs + cell.nestedTables) and `.contentControl(_, children:)` mirroring the surface-walker pattern from `Document.replaceText`.
- `.all` additionally walks headers, footers, footnotes, and endnotes — mirroring `WordDocument.updateAllFields(isolatePerContainer:)` part traversal. Container-labelled paragraph indices (e.g., `container = "header:default"`) SHALL be returned in `paragraphsModified` and `skipped`.

In Phase 1 (initial v0.21.0 release), the lib MAY land with `scope: .body` only and throw `WrapCaptionError.scopeNotImplemented(.all)` when `.all` is requested; full part-container walking lands in a Phase 1.x patch alongside the MCP wrapper integration test that exercises it.

#### Scenario: TextScope is a new shared enum or reused if it already exists

##### Example:

GIVEN the ooxml-swift codebase before this change

WHEN the implementer searches for an existing `TextScope` type

THEN if a type matching `enum TextScope { case body, all }` already exists, the implementer SHALL reuse it; otherwise a new `Models/TextScope.swift` SHALL be added with exactly two cases (`.body`, `.all`)

AND `WordDocument.updateAllFields(isolatePerContainer:)` SHALL NOT be refactored to use `TextScope` in this change (scope creep deferred)

#### Scenario: Idempotent skip detection covers both fldSimple and rawXML SEQ emissions

##### Example:

GIVEN a document containing one paragraph whose `paragraph.fieldSimples` includes `FieldSimple(instr: " SEQ Figure \\* ARABIC ", ...)` AND another paragraph whose `paragraph.runs[i].rawXML` contains `<w:fldChar w:fldCharType="begin"/>...<w:instrText>SEQ Figure \\* ARABIC</w:instrText>...<w:fldChar w:fldCharType="end"/>` (the rawXML emission style used by `insertCaption`)

WHEN `wrapCaptionSequenceFields(pattern: ..., sequenceName: "Figure")` is called against both paragraphs (matching pattern hits)

THEN both paragraphs SHALL appear in `skipped` with `reason = "already wraps SEQ Figure"`

AND neither paragraph SHALL be modified
