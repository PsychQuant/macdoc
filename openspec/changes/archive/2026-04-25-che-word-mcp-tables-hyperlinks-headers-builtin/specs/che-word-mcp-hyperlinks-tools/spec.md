## ADDED Requirements

### Requirement: insert_url_hyperlink inserts an external URL link

The MCP tool `insert_url_hyperlink` SHALL accept `doc_id` + `paragraph_index` + `url` + `text` + optional `tooltip` + optional `history` (default `true`).

The tool SHALL emit `<w:hyperlink r:id="$rId">` referencing a `Target="$url" TargetMode="External"` relationship in the paragraph's relationships.

When `tooltip` is provided, emit `w:tooltip="$tooltip"`.

When `history` is `false`, emit `w:history="0"`.

The tool SHALL ensure the `Hyperlink` character style exists in `word/styles.xml` — creating it (color #0563C1, single underline, type character) when absent.

#### Scenario: External URL with tooltip

- **WHEN** the tool is invoked with `paragraph_index: 0, url: "https://example.com", text: "Example", tooltip: "Visit example"`
- **THEN** the paragraph contains `<w:hyperlink r:id="rId$N" w:tooltip="Visit example">` with run text "Example"
- **AND** the relationships file maps rId$N to `Target="https://example.com" TargetMode="External"`
- **AND** `word/styles.xml` contains a `Hyperlink` character style

### Requirement: insert_bookmark_hyperlink inserts an internal anchor link

The MCP tool `insert_bookmark_hyperlink` SHALL accept `doc_id` + `paragraph_index` + `anchor` (the bookmark name) + `text` + optional `tooltip`.

The tool SHALL emit `<w:hyperlink w:anchor="$anchor">` (no `r:id` — internal links don't need a relationship).

The tool SHALL NOT validate that the bookmark exists in the document (forward references are valid OOXML).

The tool SHALL ensure the `Hyperlink` character style exists.

#### Scenario: Internal bookmark link

- **WHEN** the tool is invoked with `paragraph_index: 0, anchor: "ChapterTwo", text: "See Chapter 2"`
- **THEN** the paragraph contains `<w:hyperlink w:anchor="ChapterTwo">` with run text "See Chapter 2"
- **AND** the paragraph's hyperlink does NOT have an `r:id` attribute

### Requirement: insert_email_hyperlink inserts a mailto link

The MCP tool `insert_email_hyperlink` SHALL accept `doc_id` + `paragraph_index` + `email` + `text` + optional `tooltip` + optional `subject`.

The tool SHALL emit `<w:hyperlink r:id="$rId">` referencing a `Target="mailto:$email?subject=$subject" TargetMode="External"` relationship.

When `subject` is omitted, the URL is `mailto:$email` only.

The tool SHALL ensure the `Hyperlink` character style exists.

#### Scenario: Email link with subject

- **WHEN** the tool is invoked with `paragraph_index: 0, email: "support@example.com", text: "Contact us", subject: "Question"`
- **THEN** the relationship target is `mailto:support@example.com?subject=Question`

### Requirement: list_hyperlinks surfaces type and tooltip per entry

The MCP tool `list_hyperlinks` SHALL include the following fields in each entry:

- `type`: one of `"url"` / `"bookmark"` / `"email"` (derived from rId target prefix or presence of w:anchor)
- `target`: the URL / anchor name / email address (without `mailto:` prefix for emails)
- `tooltip`: the `w:tooltip` attribute value or `null` if absent
- `history`: boolean from `w:history` attribute (default `true`)
- `text`: the text content inside the hyperlink

#### Scenario: List mixed-type hyperlinks

- **GIVEN** a document with one URL hyperlink, one bookmark hyperlink, one email hyperlink
- **WHEN** the tool is invoked
- **THEN** the response is an array with three entries, each with `type` field set to `"url"` / `"bookmark"` / `"email"` respectively

