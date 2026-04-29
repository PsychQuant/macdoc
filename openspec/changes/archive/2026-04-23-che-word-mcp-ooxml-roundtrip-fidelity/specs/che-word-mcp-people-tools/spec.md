## ADDED Requirements

### Requirement: list_people MCP tool returns all comment author records from people.xml

The `che-word-mcp` server SHALL provide a `list_people(doc_id: String)` MCP tool returning an array of person descriptors. Each descriptor SHALL contain `{ person_id: String, display_name: String, email: String?, color: String?, provider_id: String? }` parsed from `<w15:person>` elements in `word/people.xml`. The `person_id` is the `<w15:person w15:author="...">` attribute value (typically a display name string), `email` and `color` come from the optional `<w15:presenceInfo>` child element, and `provider_id` is the `providerId` attribute when present. Documents without `people.xml` SHALL return an empty array.

#### Scenario: List people from document with three authors

- **WHEN** `list_people(doc_id: "x")` is called and `people.xml` declares three `<w15:person>` entries with author values `"Adam Kuo"`, `"Reviewer A"`, `"Reviewer B"`
- **THEN** the result has length 3 and includes descriptors with `display_name` matching each author value

#### Scenario: List people on document without people.xml returns empty array

- **WHEN** `list_people(doc_id: "x")` is called and the source ZIP has no `word/people.xml`
- **THEN** the result is an empty array

### Requirement: add_person MCP tool creates a new person record

The `che-word-mcp` server SHALL provide an `add_person(doc_id: String, display_name: String, email: String?, color: String?)` MCP tool that creates a new `<w15:person>` element in `people.xml`. When `people.xml` does not yet exist in the source ZIP, the tool SHALL create it (and add the corresponding `<Override>` entry in `[Content_Types].xml` and `<Relationship>` in `_rels/document.xml.rels`). The tool SHALL return `{ person_id: String }` containing the assigned author identifier (defaults to `display_name` when not already taken; otherwise appends a numeric suffix).

#### Scenario: Add person to document without people.xml creates the part

- **WHEN** `add_person(doc_id: "x", display_name: "Adam Kuo", email: "adam@example.com")` is called and `people.xml` does not exist
- **AND** the document is then saved and reread
- **THEN** the saved `.docx` contains `word/people.xml`
- **AND** the saved `[Content_Types].xml` contains an `<Override>` entry for `/word/people.xml`
- **AND** the saved `_rels/document.xml.rels` contains a `<Relationship>` whose `Target` is `people.xml`
- **AND** `list_people` returns one descriptor with `display_name == "Adam Kuo"`

#### Scenario: Add person with duplicate display_name appends numeric suffix

- **WHEN** `add_person(doc_id: "x", display_name: "Adam")` is called twice
- **THEN** the first call returns `person_id == "Adam"`
- **AND** the second call returns `person_id == "Adam_2"` (or another collision-free variant)

### Requirement: update_person MCP tool partially updates a person record

The `che-word-mcp` server SHALL provide an `update_person(doc_id: String, person_id: String, display_name: String?, email: String?, color: String?)` MCP tool that updates the named person record. Only the fields passed as arguments SHALL be modified. Unknown `person_id` SHALL return an error.

#### Scenario: Update only email field

- **WHEN** `update_person(doc_id: "x", person_id: "Adam Kuo", email: "new@example.com")` is called
- **AND** the document is then saved and reread
- **THEN** `list_people` for that descriptor shows `email == "new@example.com"`
- **AND** `display_name` and `color` remain unchanged

### Requirement: delete_person MCP tool removes a person record

The `che-word-mcp` server SHALL provide a `delete_person(doc_id: String, person_id: String)` MCP tool that removes the `<w15:person>` element from `people.xml`. When the deleted person is referenced as `<w:author>` in any `comments.xml` entry, the tool SHALL preserve the comment but the deleted author resolves to "Unknown Author" on next Word open. The tool SHALL return `{ comments_orphaned: Int }` reporting the number of comments whose author no longer has a person record.

#### Scenario: Delete person referenced by 2 comments

- **WHEN** `delete_person(doc_id: "x", person_id: "Adam Kuo")` is called and `comments.xml` has 2 comments authored by "Adam Kuo"
- **THEN** the result has `comments_orphaned == 2`
- **AND** `list_people` no longer includes a descriptor with `person_id == "Adam Kuo"`
- **AND** the 2 comments still exist in `comments.xml` with their original author string
