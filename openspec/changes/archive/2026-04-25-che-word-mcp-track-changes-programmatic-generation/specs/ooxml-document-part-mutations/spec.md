## ADDED Requirements

### Requirement: WordDocument exposes revision id allocator

The `WordDocument` model SHALL expose `allocateRevisionId() -> Int` that returns `max(existing_revision_ids) + 1`, or `1` if no revisions exist anywhere in the document tree.

The method SHALL scan revisions across all sources: body paragraphs (`Paragraph.revisions`), headers, footers, footnotes, and endnotes.

The method SHALL match the v0.15.0 SDT id allocator pattern (`allocateSdtId`) for consistency.

#### Scenario: Empty document

- **GIVEN** a document with no revisions anywhere
- **WHEN** `allocateRevisionId()` is called
- **THEN** the return value is `1`

#### Scenario: Existing revisions in body

- **GIVEN** a document with revision ids [1, 2, 3] across body paragraphs
- **WHEN** `allocateRevisionId()` is called
- **THEN** the return value is `4`

### Requirement: WordDocument exposes revision-generating mutations

The `WordDocument` model SHALL expose 5 new mutation methods that wrap text/format changes with revision metadata:

- `insertTextAsRevision(text: String, atParagraph: Int, position: Int, author: String?, date: Date?) throws -> Int`
- `deleteTextAsRevision(atParagraph: Int, start: Int, end: Int, author: String?, date: Date?) throws -> Int`
- `moveTextAsRevision(fromParagraph: Int, fromStart: Int, fromEnd: Int, toParagraph: Int, toPosition: Int, author: String?, date: Date?) throws -> (fromId: Int, toId: Int)`
- `applyRunPropertiesAsRevision(atParagraph: Int, atRunIndex: Int, newProperties: RunProperties, author: String?, date: Date?) throws -> Int`
- `applyParagraphPropertiesAsRevision(atParagraph: Int, newProperties: ParagraphProperties, author: String?, date: Date?) throws -> Int`

All 5 methods SHALL guard `isTrackChangesEnabled()`. When disabled, they SHALL throw `WordError.trackChangesNotEnabled`.

All 5 methods SHALL allocate revision id(s) via `allocateRevisionId()` (single id for insert/delete/format; two consecutive ids for move).

All 5 methods SHALL resolve the author argument using a 3-tier fallback chain: (1) explicit non-nil non-empty arg, (2) `revisions.settings.author`, (3) `"Unknown"`.

All 5 methods SHALL mark `word/document.xml` dirty.

The methods SHALL throw `WordError.invalidIndex(index)` when paragraph_index, run_index, position, start, or end is out of bounds.

The methods SHALL return the allocated revision id (or pair, for move) so callers can correlate.

#### Scenario: Insert text as revision when track changes enabled

- **GIVEN** a document with track changes enabled (author: "Reviewer A")
- **AND** paragraph 0 with run text "Hello"
- **WHEN** `insertTextAsRevision(text: " World", atParagraph: 0, position: 5, author: nil, date: nil)` is called
- **THEN** the return value is the allocated revision id (e.g., 1)
- **AND** paragraph 0's runs include the new " World" text
- **AND** paragraph 0's revisions array contains a new entry with `type=.insertion`, `author="Reviewer A"`, `id=1`
- **AND** `word/document.xml` is marked dirty

#### Scenario: Generator throws when track changes disabled

- **GIVEN** a document with track changes disabled
- **WHEN** any generator method is called
- **THEN** the method throws `WordError.trackChangesNotEnabled`
- **AND** the document is unchanged
- **AND** track changes remains disabled (no side effect)

#### Scenario: Move allocates two consecutive ids

- **GIVEN** a document with track changes enabled and no existing revisions
- **WHEN** `moveTextAsRevision(...)` is called
- **THEN** the return value is `(fromId: 1, toId: 2)`
- **AND** paragraph at `fromParagraph` has a `Revision(type: .moveFrom, id: 1, ...)` entry
- **AND** paragraph at `toParagraph` has a `Revision(type: .moveTo, id: 2, ...)` entry

