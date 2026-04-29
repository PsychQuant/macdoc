## ADDED Requirements

### Requirement: wrap_caption_seq MCP tool

The `wrap_caption_seq` MCP tool SHALL bulk-convert plain-text caption number portions into `<w:fldSimple>`-bearing SEQ-field runs across paragraphs whose `flattenedDisplayText()` matches a user-supplied regex with one numeric capture group, returning a structured per-paragraph result for downstream verification.

The tool SHALL accept the following parameters:

- `doc_id: String` (required) — opened-document handle.
- `pattern: String` (required) — regex string with exactly ONE numeric capture group.
- `sequence_name: String` (required) — SEQ identifier (e.g., `"Figure"`, `"Table"`, custom).
- `format: String?` (default `"ARABIC"`) — one of `"ARABIC"` / `"ROMAN"` / `"ALPHABETIC"`.
- `scope: String?` (default `"body"`) — one of `"body"` / `"all"`.
- `insert_bookmark: Bool?` (default `false`).
- `bookmark_template: String?` (required when `insert_bookmark = true`) — template containing literal `${number}` placeholder substituted with the captured numeric.

The tool SHALL return a JSON object with snake_case keys:

```json
{
  "matched_paragraphs": <Int>,
  "fields_inserted": <Int>,
  "paragraphs_modified": [<Int>, ...],
  "skipped": [{"paragraph_index": <Int>, "reason": "<String>"}, ...]
}
```

The tool SHALL emit `"Error: wrap_caption_seq: <body>"` (per `#70` tool-prefix convention) for the following preconditions, BEFORE mutating the document:

- Pattern is empty, fails to compile as a valid `NSRegularExpression`, or contains zero or 2+ capture groups.
- `format` is not one of `"ARABIC"` / `"ROMAN"` / `"ALPHABETIC"`.
- `scope` is not one of `"body"` / `"all"`.
- `insert_bookmark = true` but `bookmark_template` is missing or does not contain the literal `${number}` placeholder.
- Document `doc_id` is not opened.

The tool SHALL be idempotent: paragraphs whose runs or `fieldSimples` already contain a `SEQ {sequence_name}` field SHALL appear in `skipped` with `reason = "already wraps SEQ {sequence_name}"` and SHALL NOT be double-wrapped.

#### Scenario: Body scope wraps three plain-text figure captions

##### Example:

GIVEN a document body containing 3 paragraphs with text `圖 4-1：架構圖`, `圖 4-2：流程圖`, `圖 4-3：時序圖` plus 5 unrelated paragraphs

WHEN `wrap_caption_seq(pattern: "圖 4-(\\d+)：", sequence_name: "Figure")` is called

THEN the response SHALL be:

```json
{
  "matched_paragraphs": 3,
  "fields_inserted": 3,
  "paragraphs_modified": [<idx1>, <idx2>, <idx3>],
  "skipped": []
}
```

AND each modified paragraph's `flattenedDisplayText()` SHALL still display `圖 4-1：架構圖` (etc.) immediately after the call (cachedResult preserved)

AND the underlying XML SHALL contain `<w:fldSimple w:instr=" SEQ Figure \* ARABIC ">` wrapping each captured digit

#### Scenario: Idempotent re-run skips already-wrapped paragraphs

##### Example:

GIVEN the same document AFTER the previous wrap_caption_seq call has succeeded

WHEN `wrap_caption_seq(pattern: "圖 4-(\\d+)：", sequence_name: "Figure")` is called a second time

THEN the response SHALL be:

```json
{
  "matched_paragraphs": 3,
  "fields_inserted": 0,
  "paragraphs_modified": [],
  "skipped": [
    {"paragraph_index": <idx1>, "reason": "already wraps SEQ Figure"},
    {"paragraph_index": <idx2>, "reason": "already wraps SEQ Figure"},
    {"paragraph_index": <idx3>, "reason": "already wraps SEQ Figure"}
  ]
}
```

#### Scenario: Pattern with zero capture groups rejected before mutation

##### Example:

GIVEN any opened document

WHEN `wrap_caption_seq(pattern: "圖 4-\\d+：", sequence_name: "Figure")` is called (no parentheses around `\d+` — zero capture groups)

THEN the tool SHALL return `"Error: wrap_caption_seq: pattern must contain exactly one capture group, got 0"`

AND the document SHALL be unmodified (no body.children diff)

#### Scenario: Bookmark wrapping with template substitution

##### Example:

GIVEN a body paragraph with text `Figure 7. Distribution of MoCA scores`

WHEN `wrap_caption_seq(pattern: "Figure (\\d+)\\.", sequence_name: "Figure", insert_bookmark: true, bookmark_template: "fig${number}")` is called

THEN the matched paragraph SHALL be wrapped with `<w:bookmarkStart w:name="fig7" w:id="<generated>">` immediately before the SEQ-field run AND `<w:bookmarkEnd w:id="<generated>">` immediately after

AND `list_bookmarks` SHALL return the new bookmark `fig7` after the call

#### Scenario: insert_bookmark = true without bookmark_template rejected before mutation

##### Example:

GIVEN any opened document

WHEN `wrap_caption_seq(pattern: "Figure (\\d+)", sequence_name: "Figure", insert_bookmark: true)` is called (no `bookmark_template`)

THEN the tool SHALL return `"Error: wrap_caption_seq: bookmark_template required when insert_bookmark is true"`

AND the document SHALL be unmodified
