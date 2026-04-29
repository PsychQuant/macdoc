## ADDED Requirements

### Requirement: list_comment_threads MCP tool returns parent-child comment hierarchy

The `che-word-mcp` server SHALL provide a `list_comment_threads(doc_id: String)` MCP tool returning an array of thread descriptors. Each descriptor SHALL contain `{ root_comment_id: Int, replies: [Int], resolved: Bool, durable_id: String? }` where `root_comment_id` is the integer ID from `comments.xml` of the topmost comment in a reply chain, `replies` lists the integer IDs of descendant comments in document order, `resolved` reflects the `<w15:commentEx w15:done="1">` flag from `commentsExtended.xml`, and `durable_id` is the `<w16cid:commentId paraId="...">` value from `commentsIds.xml` when present. Comments without any reply or parent SHALL appear as standalone threads with empty `replies` array.

#### Scenario: Threaded comments grouped by parent

- **WHEN** `list_comment_threads(doc_id: "x")` is called on a document where `commentsExtended.xml` declares comment `5` as parent of comments `6` and `7`
- **THEN** the result contains exactly one descriptor with `root_comment_id == 5` and `replies == [6, 7]`
- **AND** that descriptor does NOT also list 6 or 7 as their own root

#### Scenario: Resolved status reflects commentsExtended done flag

- **WHEN** `list_comment_threads` is called and comment `3` has `<w15:commentEx w15:done="1">` in `commentsExtended.xml`
- **THEN** the descriptor with `root_comment_id == 3` has `resolved == true`

### Requirement: get_comment_thread MCP tool returns full tree for a root comment

The `che-word-mcp` server SHALL provide a `get_comment_thread(doc_id: String, root_comment_id: Int)` MCP tool returning a recursive tree `{ comment_id, author, text, created_at, replies: [<recursive>] }`. Replies SHALL appear in document order. Unknown `root_comment_id` SHALL return an error.

#### Scenario: Get comment thread returns full reply tree

- **WHEN** `get_comment_thread(doc_id: "x", root_comment_id: 5)` is called and the thread has 2 direct replies (6 and 7) where 7 has a nested reply (9)
- **THEN** the result has `comment_id == 5` and `replies` of length 2
- **AND** `replies[1].comment_id == 7` and `replies[1].replies` of length 1 with `comment_id == 9`

### Requirement: sync_extended_comments MCP tool repairs comments triplet consistency

The `che-word-mcp` server SHALL provide a `sync_extended_comments(doc_id: String)` MCP tool that ensures every comment in `comments.xml` has a corresponding entry in `commentsExtended.xml` (with `paraId` and `done` flag, defaulting `done="0"` if missing) AND in `commentsIds.xml` (with a generated `<w16cid:commentId>` UUID-based durable id when missing). Comments present in `commentsExtended.xml` or `commentsIds.xml` but absent from `comments.xml` SHALL be removed from the extended files. The tool SHALL return `{ added_extended: Int, added_ids: Int, removed_orphans: Int }`.

#### Scenario: Sync adds missing extended entries

- **WHEN** `comments.xml` has 5 comments and `commentsExtended.xml` is empty (e.g., after a v3.1.0 round-trip stripped it)
- **AND** `sync_extended_comments(doc_id: "x")` is called
- **THEN** the result has `added_extended == 5`
- **AND** `commentsExtended.xml` contains 5 `<w15:commentEx>` entries with `done="0"`

#### Scenario: Sync removes orphan extended entries

- **WHEN** `comments.xml` has 3 comments and `commentsExtended.xml` has 5 (2 orphans)
- **AND** `sync_extended_comments(doc_id: "x")` is called
- **THEN** the result has `removed_orphans == 2`
