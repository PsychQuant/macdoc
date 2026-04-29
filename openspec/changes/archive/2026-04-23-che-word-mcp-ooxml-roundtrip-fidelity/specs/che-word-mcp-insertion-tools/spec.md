## ADDED Requirements

### Requirement: insert_comment auto-syncs commentsExtended, commentsExtensible, commentsIds, and people.xml

The `che-word-mcp` server's `insert_comment` MCP tool SHALL, in addition to writing the new `<w:comment>` to `comments.xml`, also: (1) write a corresponding `<w15:commentEx>` entry to `commentsExtended.xml` (creating the part if absent) with `done="0"` and a generated `paraId`, (2) write a corresponding `<w16cid:commentId>` entry to `commentsIds.xml` (creating the part if absent) with a generated UUID-based `durableId`, (3) when the comment author is not yet present in `people.xml`, create a `<w15:person>` record (creating `people.xml` if absent). Creating any new part SHALL also add the matching `[Content_Types].xml` Override and `_rels/document.xml.rels` Relationship via `RelationshipIdAllocator`.

#### Scenario: Insert comment by new author creates person record

- **WHEN** `insert_comment(doc_id: "x", author: "Adam Kuo", text: "Looks good")` is called and `people.xml` had no entry for "Adam Kuo"
- **AND** the document is then saved and reread
- **THEN** the saved `comments.xml` contains the new `<w:comment>` with `w:author="Adam Kuo"`
- **AND** the saved `commentsExtended.xml` contains a `<w15:commentEx>` for the new comment with `done="0"`
- **AND** the saved `commentsIds.xml` contains a `<w16cid:commentId>` with a UUID durable id
- **AND** the saved `people.xml` contains a `<w15:person w15:author="Adam Kuo">` entry

#### Scenario: Insert comment by existing author does not duplicate person record

- **WHEN** `insert_comment(doc_id: "x", author: "Adam Kuo", text: "Second comment")` is called after a first comment by "Adam Kuo" already created the person record
- **THEN** the saved `people.xml` still contains exactly one `<w15:person w15:author="Adam Kuo">` entry (no duplicate)

### Requirement: reply_to_comment writes parent reference to commentsExtended

The `che-word-mcp` server's `reply_to_comment` MCP tool SHALL write the reply as a new `<w:comment>` in `comments.xml` AND ALSO write a `<w15:commentEx>` entry in `commentsExtended.xml` whose `<w15:parentCommentId>` element references the parent comment's paraId. The reply SHALL also trigger the same `commentsIds.xml` and `people.xml` syncing as `insert_comment`.

#### Scenario: Reply creates parent reference in commentsExtended

- **WHEN** `reply_to_comment(doc_id: "x", parent_comment_id: 5, author: "Reviewer", text: "Disagree")` is called
- **AND** the document is then saved and reread
- **THEN** the saved `commentsExtended.xml` contains a `<w15:commentEx>` for the new reply with `<w15:parentCommentId w15:val="<parent paraId>">`

### Requirement: resolve_comment sets done flag in commentsExtended

The `che-word-mcp` server's `resolve_comment` MCP tool SHALL set the `done="1"` attribute on the `<w15:commentEx>` entry corresponding to the named comment ID in `commentsExtended.xml`. The comment text in `comments.xml` SHALL remain unchanged. The tool SHALL return an error if `commentsExtended.xml` does not contain an entry for the comment (e.g., the document has been round-tripped through a pre-fix version that stripped the part) — callers SHALL run `sync_extended_comments` first in that case.

#### Scenario: Resolve flips done attribute to 1

- **WHEN** `resolve_comment(doc_id: "x", comment_id: 5)` is called and the corresponding `<w15:commentEx>` had `done="0"`
- **AND** the document is then saved and reread
- **THEN** the saved `commentsExtended.xml`'s entry for comment 5 has `done="1"`

#### Scenario: Resolve when commentsExtended is missing returns sync hint error

- **WHEN** `resolve_comment(doc_id: "x", comment_id: 5)` is called and `commentsExtended.xml` does not contain an entry for comment 5
- **THEN** the tool returns an error whose message contains both `commentsExtended` and `sync_extended_comments`

### Requirement: delete_comment removes entries from all four comment-related parts

The `che-word-mcp` server's `delete_comment` MCP tool SHALL remove the `<w:comment>` from `comments.xml` AND ALSO the corresponding entries from `commentsExtended.xml`, `commentsExtensible.xml`, and `commentsIds.xml` when present. The tool SHALL also remove `<w:commentRangeStart>`, `<w:commentRangeEnd>`, and `<w:commentReference>` markers from `document.xml`. When the deleted comment is the parent of replies in `commentsExtended.xml`, the replies SHALL be left orphaned (their `<w15:parentCommentId>` references SHALL NOT be re-targeted).

#### Scenario: Delete comment removes from all four parts

- **WHEN** `delete_comment(doc_id: "x", comment_id: 5)` is called and entries for comment 5 exist in all four parts
- **AND** the document is then saved and reread
- **THEN** none of `comments.xml`, `commentsExtended.xml`, `commentsExtensible.xml`, `commentsIds.xml` contain an entry referencing comment ID 5
- **AND** `document.xml` no longer contains `<w:commentReference w:id="5">` markers

### Requirement: add_header and add_footer use RelationshipIdAllocator for collision-free rIds

The `che-word-mcp` server's `add_header` and `add_footer` MCP tools SHALL allocate the new header/footer's relationship Id via `RelationshipIdAllocator.allocate()` rather than the prior naive `headers.count + footers.count + ...` counter at `DocxWriter.swift:238`. This ensures the new rId does not collide with any preserved original Relationship Id in `_rels/document.xml.rels`.

#### Scenario: Add header on document with preserved high rId returns non-colliding rId

- **WHEN** the original `_rels/document.xml.rels` contains `<Relationship Id="rId99"...>` (a high preserved ID) and the typed model has 0 headers
- **AND** `add_header(doc_id: "x", text: "New header")` is called
- **THEN** the returned `header_id` is `"rId100"` or higher (not `"rId1"`)
- **AND** the saved `_rels/document.xml.rels` contains both `<Relationship Id="rId99"...>` (preserved) and `<Relationship Id="rId100"...>` (newly added)

### Requirement: update_header and update_footer preserve original part filename

The `che-word-mcp` server's `update_header` and `update_footer` MCP tools SHALL update the existing header/footer part's content in place (overwriting the existing `header*.xml` or `footer*.xml` file in `archiveTempDir`) WITHOUT changing the part's filename or relationship Id. This preserves cross-references in `document.xml` and prevents orphaning the relationship.

#### Scenario: Update header preserves filename and rId

- **WHEN** the document has `header3.xml` with rId `"rId4"` and `update_header(doc_id: "x", header_id: "rId4", text: "Updated header")` is called
- **AND** the document is then saved and reread
- **THEN** the saved `.docx` still contains `word/header3.xml` (same filename)
- **AND** the saved `_rels/document.xml.rels` still has `<Relationship Id="rId4" Target="header3.xml"...>`
- **AND** `header3.xml`'s content reflects the new text
