## ADDED Requirements

### Requirement: insert_text_as_revision wraps inserted text in <w:ins>

The MCP tool `insert_text_as_revision` SHALL accept `doc_id` + `paragraph_index` + `position` (character offset within the paragraph) + `text` + optional `author` + optional `date` (ISO 8601).

The tool SHALL guard that `is_track_changes_enabled() == true`. When false, the tool SHALL return error `track_changes_not_enabled` without modifying the document.

The tool SHALL allocate a fresh revision id via `WordDocument.allocateRevisionId()`. The inserted text run is added to the paragraph's runs at the requested position, and a `Revision(type: .insertion, id: <allocated>, author: <resolved>, date: <provided or now>, ...)` entry is appended to `paragraph.revisions`. The writer (existing `Revision.toXML`) emits `<w:ins w:id="$id" w:author="$author" w:date="$date">` wrapping the new run on save.

The tool SHALL resolve `author` via 3-tier fallback: (1) explicit arg if provided and non-empty, (2) `revisions.settings.author` if track changes was enabled with an author, (3) literal `"Unknown"`.

The tool SHALL return error `out_of_bounds` when `paragraph_index` or `position` is invalid.

#### Scenario: Insert "Hello " at position 0 of paragraph 0

- **GIVEN** a document with paragraph 0 containing run text "World"
- **AND** `enable_track_changes(author: "Claude AI")` was called
- **WHEN** the tool is invoked with `paragraph_index: 0, position: 0, text: "Hello "`
- **THEN** paragraph 0's runs become ["Hello ", "World"]
- **AND** paragraph 0's revisions contain one entry with `type=.insertion`, `author="Claude AI"`, `id` allocated by `allocateRevisionId`
- **AND** save output XML wraps the "Hello " run in `<w:ins w:id="$id" w:author="Claude AI" w:date="$iso">`

#### Scenario: Insert without enabling track changes

- **GIVEN** track changes is disabled
- **WHEN** the tool is invoked with any args
- **THEN** the tool returns `{"error": "track_changes_not_enabled"}`
- **AND** the document is unchanged

### Requirement: delete_text_as_revision wraps deleted text in <w:del>

The MCP tool `delete_text_as_revision` SHALL accept `doc_id` + `paragraph_index` + `start` (inclusive character offset) + `end` (exclusive character offset) + optional `author` + optional `date`.

The tool SHALL guard track changes enabled (returns `track_changes_not_enabled` when off).

The tool SHALL allocate a fresh revision id, identify the runs covering `[start, end)` within the paragraph (using existing `TextReplacementEngine` flatten-then-map logic), and append a `Revision(type: .deletion, ...)` to `paragraph.revisions`. The writer substitutes `<w:t>` with `<w:delText>` automatically when emitting deleted runs (existing Revision.toXML behavior).

The tool SHALL operate within a single paragraph only. Cross-paragraph delete (paragraph mark deletion) is OUT OF SCOPE — the tool SHALL return `out_of_bounds` if `start` or `end` exceeds the paragraph's text length.

#### Scenario: Delete "World" from "Hello World"

- **GIVEN** paragraph 0 with text "Hello World" (single run); track changes enabled
- **WHEN** the tool is invoked with `paragraph_index: 0, start: 6, end: 11`
- **THEN** paragraph 0's revisions contain one entry with `type=.deletion`, `originalText: "World"`, allocated id
- **AND** save output XML emits `<w:del w:id="$id" w:author="..." w:date="...">` wrapping a run containing `<w:delText>World</w:delText>`
- **AND** the deletion is visible in Word as redline

#### Scenario: Out-of-bounds end

- **WHEN** the tool is invoked with `start: 0, end: 9999` on a paragraph with text length 11
- **THEN** the tool returns `{"error": "out_of_bounds", "end": 9999}`

### Requirement: move_text_as_revision emits paired moveFrom + moveTo

The MCP tool `move_text_as_revision` SHALL accept `doc_id` + `from_paragraph_index` + `from_start` + `from_end` + `to_paragraph_index` + `to_position` + optional `author` + optional `date`.

The tool SHALL allocate two consecutive revision ids (N and N+1). It SHALL append `Revision(type: .moveFrom, id: N, ...)` at the source paragraph and `Revision(type: .moveTo, id: N+1, ...)` at the destination paragraph. The writer emits `<w:moveFrom>` and `<w:moveTo>` blocks accordingly.

The tool SHALL guard track changes enabled.

The tool SHALL operate on single-paragraph source range; if `from_start` to `from_end` spans multiple paragraphs, return `out_of_bounds`.

#### Scenario: Move "World" from paragraph 0 to paragraph 1

- **GIVEN** paragraph 0 text "Hello World"; paragraph 1 text "Greetings"; track changes enabled
- **WHEN** the tool is invoked with `from_paragraph_index: 0, from_start: 6, from_end: 11, to_paragraph_index: 1, to_position: 0`
- **THEN** paragraph 0's revisions contain `type=.moveFrom`, id=N
- **AND** paragraph 1's revisions contain `type=.moveTo`, id=N+1
- **AND** the new ids are consecutive (allocated by two `allocateRevisionId` calls)

### Requirement: format_text accepts as_revision arg

The MCP tool `format_text` SHALL accept an optional `as_revision: bool` argument (default `false`).

When `as_revision: false`, the tool's behavior matches v3.11.x exactly (silent format mutation).

When `as_revision: true`, the tool SHALL guard track changes enabled (returns `track_changes_not_enabled` when off) and divert the format change through `WordDocument.applyRunPropertiesAsRevision(...)`. The writer emits the run's `<w:rPr>` containing `<w:rPrChange w:id="$id" w:author="..." w:date="..."><w:rPr>...prior props...</w:rPr></w:rPrChange>` so Word UI shows the format change as a tracked revision.

#### Scenario: Bold a run as a revision

- **GIVEN** paragraph 0 has a run with text "important" and no bold; track changes enabled
- **WHEN** `format_text(paragraph_index: 0, run_index: 0, bold: true, as_revision: true)` is called
- **THEN** the run is now bold
- **AND** the run's properties carry an `<w:rPrChange>` recording the prior (non-bold) state
- **AND** Word UI displays this as a tracked formatting change

#### Scenario: format_text with as_revision=true but track changes off

- **GIVEN** track changes is disabled
- **WHEN** `format_text(...as_revision: true)` is called
- **THEN** the tool returns `{"error": "track_changes_not_enabled"}`
- **AND** the document is unchanged
- **AND** track changes is NOT auto-enabled (no side effects)

### Requirement: set_paragraph_format accepts as_revision arg

The MCP tool `set_paragraph_format` SHALL accept an optional `as_revision: bool` argument (default `false`).

When `as_revision: true`, the tool SHALL guard track changes enabled and divert through `WordDocument.applyParagraphPropertiesAsRevision(...)`. The writer emits the paragraph's `<w:pPr>` containing `<w:pPrChange w:id="$id" w:author="..." w:date="..."><w:pPr>...prior props...</w:pPr></w:pPrChange>`.

#### Scenario: Change paragraph alignment as a revision

- **GIVEN** paragraph 0 has alignment `left`; track changes enabled
- **WHEN** `set_paragraph_format(paragraph_index: 0, alignment: "center", as_revision: true)` is called
- **THEN** the paragraph alignment is now `center`
- **AND** the paragraph's properties carry a `<w:pPrChange>` recording the prior alignment (`left`)

