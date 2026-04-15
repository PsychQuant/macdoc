## ADDED Requirements

### Requirement: Truncation policy via summarize parameter

The `che-word-mcp` server SHALL accept a `summarize: Bool` argument (default `false`) on every tool that returns potentially long text. When `summarize` is `false` or omitted, the server SHALL return complete text with no upper bound. When `summarize` is `true`, the server SHALL apply head+tail elision to any individual text entry whose length exceeds 5000 characters, formatted as the first 30 characters, the literal string ` [...] `, and the last 30 characters.

Tools subject to this policy on initial release: `get_revisions`, `compare_documents`, `export_revision_summary_markdown`, `compare_documents_markdown`, `export_comment_threads_markdown`.

#### Scenario: Default returns complete text

- **WHEN** a caller invokes `get_revisions` against a document containing a revision with 8000 characters of text and does not pass `summarize`
- **THEN** the response includes all 8000 characters of that revision's text uncut

#### Scenario: Summarize true elides long entries

- **WHEN** a caller invokes `get_revisions` with `summarize: true` against the same 8000-character revision
- **THEN** the response renders that revision's text as `<first 30 chars> [...] <last 30 chars>`

#### Scenario: Summarize true preserves short entries

- **WHEN** a caller invokes `get_revisions` with `summarize: true` against a revision with 200 characters
- **THEN** the response includes the 200 characters complete, with no elision applied

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
-->

---

### Requirement: full_text parameter is removed

The `get_revisions` and `compare_documents` MCP tools SHALL NOT accept a `full_text` argument. The previous `full_text: Bool = false` parameter on `get_revisions` is removed and its behavior is superseded by the inverted-default `summarize: Bool = false` parameter.

#### Scenario: Passing full_text is rejected

- **WHEN** a caller invokes `get_revisions` with `full_text: true` after this change ships
- **THEN** the MCP server rejects the call with an unknown-argument error pointing to the new `summarize` parameter name

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
-->

---

### Requirement: export_revision_summary_markdown tool

The `che-word-mcp` server SHALL expose a tool named `export_revision_summary_markdown` that returns a markdown document summarizing one `.docx` file's revisions and comments.

The tool SHALL accept these arguments:

- `source_path: String` (required) — path to the `.docx` file (Direct Mode)
- `doc_id: String` (optional) — alternative to `source_path` (Session Mode)
- `include_revisions: Bool` (default `true`)
- `include_comments: Bool` (default `true`)
- `group_by: String` (default `"author"`, valid: `"author"`, `"section"`, `"type"`, `"none"`)
- `summarize: Bool` (default `false`) — see truncation policy requirement

The tool SHALL return a markdown document containing: a level-1 heading with the file name, a stats section listing revision count, comment count, and per-author breakdown, a revisions table (when `include_revisions`), and a comments table (when `include_comments`).

#### Scenario: Per-doc summary with all defaults

- **WHEN** the tool is invoked with `source_path: "/path/to/v3.docx"` against a document with 16 revisions and 20 comments by 3 authors
- **THEN** the returned markdown contains a level-1 heading with `v3.docx`, a stats list with `Revisions: 16`, `Comments: 20`, and per-author counts, a revisions table with 16 rows, and a comments table with 20 rows

#### Scenario: Comments-only mode

- **WHEN** the tool is invoked with `include_revisions: false`
- **THEN** the returned markdown omits the revisions table heading and table entirely, retaining only the stats and comments sections

#### Scenario: Group by author

- **WHEN** the tool is invoked with `group_by: "author"` against a document with revisions from two authors
- **THEN** the revisions table is partitioned by author with one sub-heading per author and one table per partition

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
-->

---

### Requirement: compare_documents_markdown tool

The `che-word-mcp` server SHALL expose a tool named `compare_documents_markdown` that returns a markdown document presenting a cumulative change timeline across an ordered list of `.docx` files.

The tool SHALL accept these arguments:

- `documents: [{ path: String, label: String }]` (required, length >= 2) — ordered list of files
- `include_summary_table: Bool` (default `true`)
- `include_per_pair_diff: Bool` (default `true`)
- `diff_format: String` (default `"narrative"`, valid: `"narrative"`, `"table"`, `"raw"`)
- `summarize: Bool` (default `false`) — see truncation policy requirement

The tool SHALL return a markdown document containing: a level-1 heading "Manuscript Change Timeline", optional versions table (one row per document with revision count, comment count, net word delta), and one section per adjacent document pair showing the diff in the requested format.

#### Scenario: Five-document timeline

- **WHEN** the tool is invoked with five document refs (v1, v1_lay, v2, v2_lay, v3) and all defaults
- **THEN** the returned markdown contains the title heading, a versions table with 5 rows, and 4 pairwise sections (`v1 → v1_lay`, `v1_lay → v2`, `v2 → v2_lay`, `v2_lay → v3`)

#### Scenario: Less than two documents fails fast

- **WHEN** the tool is invoked with a single document or empty list
- **THEN** the server returns an error indicating at least 2 documents are required

#### Scenario: Summary table only mode

- **WHEN** the tool is invoked with `include_per_pair_diff: false`
- **THEN** the returned markdown contains the versions table but omits all pairwise diff sections

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
-->

---

### Requirement: export_comment_threads_markdown tool

The `che-word-mcp` server SHALL expose a tool named `export_comment_threads_markdown` that returns a markdown document presenting comments grouped into threads with parent-reply structure, optional author alias normalization, and optional `Old:` pattern detection.

The tool SHALL accept these arguments:

- `source_path: String` (required) or `doc_id: String` (Session Mode alternative)
- `author_aliases: [String: String]` (optional, default empty) — map from raw author name to canonical name
- `detect_old_pattern: Bool` (default `false`) — when `true`, scan reply text for the `Old: <quoted text>` pattern and annotate as informal reply
- `format: String` (default `"table"`, valid: `"table"`, `"threaded"`, `"narrative"`)
- `include_resolved: Bool` (default `true`)
- `summarize: Bool` (default `false`) — see truncation policy requirement

The tool SHALL group comments using the `Comment.parentId` field returned by `Document.getCommentsFull()` (parent comments and their direct replies form one thread). The tool SHALL normalize author names by looking each raw author name up in `author_aliases` and using the mapped value when present.

#### Scenario: Threaded format with parent and replies

- **WHEN** the tool is invoked against a document with 3 parent comments, where one parent has 2 replies, all defaults
- **THEN** the returned markdown contains a table with one row per parent comment, including a column showing the reply count for that thread

#### Scenario: Author alias normalization

- **WHEN** the tool is invoked with `author_aliases: { "kllay's PC": "Lay", "Lay": "Lay" }` against a document where one author appears as both `kllay's PC` and `Lay`
- **THEN** the returned markdown shows `Lay` as the author for all rows from either raw name, with no separate row or count for `kllay's PC`

#### Scenario: Old pattern detection produces annotated replies

- **WHEN** the tool is invoked with `detect_old_pattern: true` against a document containing a reply whose text begins with `Old: previous wording\nnew wording`
- **THEN** the row for that reply includes an annotation indicating informal-quote pattern with both the quoted prior text and the new wording extracted

#### Scenario: Detect_old_pattern false leaves text unmodified

- **WHEN** the tool is invoked with `detect_old_pattern: false` against the same `Old:`-prefixed reply
- **THEN** the row contains the reply text verbatim with no extra annotation

#### Scenario: Threaded format

- **WHEN** the tool is invoked with `format: "threaded"`
- **THEN** the returned markdown is a nested bullet list (one bullet per parent comment, indented bullets per reply) instead of a table

#### Scenario: Narrative format

- **WHEN** the tool is invoked with `format: "narrative"`
- **THEN** the returned markdown contains one prose paragraph per thread instead of a table or bullet list

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
-->

---

### Requirement: ooxml-swift exposes Comment.parentId via getCommentsFull

The `ooxml-swift` package SHALL provide a method `Document.getCommentsFull() -> [Comment]` that returns the complete `Comment` struct (including `id`, `author`, `text`, `paragraphIndex`, `date`, `parentId`, and `initials`) for every comment in the document.

The existing `Document.getComments()` method (returning a tuple) SHALL remain unchanged.

#### Scenario: Reply comment exposes parentId

- **WHEN** a caller calls `getCommentsFull()` on a document where comment B is a reply to comment A
- **THEN** the returned array contains both comments with comment B's `parentId` equal to comment A's `id`, and comment A's `parentId` equal to `nil`

#### Scenario: Top-level comment has nil parentId

- **WHEN** a caller calls `getCommentsFull()` on a document with one non-reply comment
- **THEN** the returned single-element array contains a `Comment` with `parentId == nil`

<!-- @trace
source: manuscript-review-markdown-export
updated: 2026-04-15
code:
  - packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
-->

---

### Requirement: AuthorAliasMap helper

The `che-word-mcp` server SHALL provide an internal `AuthorAliasMap` value type that wraps a `[String: String]` mapping from raw author name to canonical name and exposes a `canonicalize(_ rawAuthor: String) -> String` method. Lookups SHALL be exact-match (case-sensitive, no whitespace normalization). When the raw author is not in the map, the method SHALL return the raw author unchanged.

#### Scenario: Mapped author returns canonical name

- **WHEN** an `AuthorAliasMap` initialized with `["kllay's PC": "Lay"]` is queried with `canonicalize("kllay's PC")`
- **THEN** the method returns `"Lay"`

#### Scenario: Unmapped author passes through unchanged

- **WHEN** the same map is queried with `canonicalize("Tatsuma")`
- **THEN** the method returns `"Tatsuma"` unchanged
