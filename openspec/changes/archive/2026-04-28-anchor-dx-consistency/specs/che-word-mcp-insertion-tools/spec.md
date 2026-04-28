# che-word-mcp-insertion-tools Specification — anchor-dx-consistency delta

## ADDED Requirements

### Requirement: Conflicting anchor parameters MUST be rejected with structured error

The 4 `#61`-target insert tools (`insert_paragraph`, `insert_equation` display mode, `insert_image_from_path`, `insert_caption`) SHALL detect when 2 or more anchor parameters are simultaneously present in the request and return a structured error message instead of silently picking one by hardcoded priority.

The error message MUST follow the format:

```
Error: <tool_name>: received conflicting anchors: <a> + <b>[ + <c>...]. Specify exactly one.
```

Where `<tool_name>` is the snake-case MCP tool name and `<a> + <b>...` is the alphabetically-sorted list of present anchor parameter names.

The set of "anchor parameters" per tool is:

| Tool | Anchor parameters |
|---|---|
| `insert_paragraph` | `into_table_cell`, `after_image_id`, `after_text`, `before_text`, `index` |
| `insert_equation` (display mode) | `into_table_cell`, `after_image_id`, `after_text`, `before_text`, `paragraph_index` |
| `insert_image_from_path` | `into_table_cell`, `after_image_id`, `after_text`, `before_text`, `index` |
| `insert_caption` | `paragraph_index`, `after_image_id`, `after_table_index`, `after_text`, `before_text` |

Modifier parameters (`text_instance`, `position`, `style`, etc.) are NOT anchors and do NOT count toward conflict detection. `insert_equation` inline mode (`display_mode=false`) rejects ALL anchors per pre-existing v3.15.1 behavior; conflict detection does not change inline-mode rejection.

When **zero** anchor parameters are present, tools SHALL fall through to their existing default behavior (append at end for `insert_paragraph` / `insert_equation` display / `insert_image_from_path`; tool-specific default for `insert_caption`).

#### Scenario: Two anchors → conflict error

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x", after_text: "foo", index: 3 })` is called
- **THEN** the response is `"Error: insert_paragraph: received conflicting anchors: after_text + index. Specify exactly one."`
- **AND** the document is unchanged (no insertion occurs)

#### Scenario: Three anchors → all listed in error

- **WHEN** `insert_image_from_path({ doc_id: "d", path: "/tmp/x.png", into_table_cell: { table_index: 0, row: 0, col: 0 }, after_text: "bar", before_text: "baz" })` is called
- **THEN** the response is `"Error: insert_image_from_path: received conflicting anchors: after_text + before_text + into_table_cell. Specify exactly one."`
- **AND** the document is unchanged

#### Scenario: One anchor → unchanged behavior

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x", after_text: "foo" })` is called
- **THEN** the existing `after_text` insertion path is exercised; response is the existing success message `"Inserted paragraph after text 'foo' (instance 1)"`

#### Scenario: Zero anchors → append fallback

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x" })` is called
- **THEN** existing append-at-end behavior is exercised; response is `"Inserted paragraph at index <body.children.count - 1>"`

#### Scenario: Modifier params do NOT count

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x", after_text: "foo", text_instance: 2, style: "Heading1" })` is called
- **THEN** no conflict error (only one anchor `after_text`); existing path with `text_instance=2` and `style="Heading1"` is exercised

---

### Requirement: text_instance MUST be ≥ 1 when explicitly specified

The 4 `#61`-target insert tools that accept `after_text` / `before_text` anchors (i.e., all 4) SHALL validate `text_instance` as ≥ 1 when explicitly specified. The tools MUST default `text_instance` to `1` when omitted (existing behavior preserved).

When `text_instance` is explicitly set to `0` or any negative integer, the tool MUST return:

```
Error: <tool_name>: text_instance must be ≥ 1, got <N>.
```

Where `<N>` is the explicit value passed.

#### Scenario: text_instance: 0 rejected

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x", after_text: "foo", text_instance: 0 })` is called
- **THEN** the response is `"Error: insert_paragraph: text_instance must be ≥ 1, got 0."`
- **AND** the document is unchanged

#### Scenario: text_instance: -3 rejected

- **WHEN** `insert_equation({ doc_id: "d", omml: "...", display_mode: true, after_text: "bar", text_instance: -3 })` is called
- **THEN** the response is `"Error: insert_equation: text_instance must be ≥ 1, got -3."`

#### Scenario: text_instance omitted → defaults to 1

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x", after_text: "foo" })` is called
- **THEN** the `after_text` lookup uses `instance: 1` (existing behavior); no validation error

#### Scenario: text_instance: 1 explicit → equivalent to omitted

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x", after_text: "foo", text_instance: 1 })` is called
- **THEN** behavior identical to omitted (no error)

---

### Requirement: Error messages from `return "Error: ..."` lines MUST be tool-prefixed

All error messages returned via `return "Error: ..."` from the 4 `#61`-target insert tools (and from any other MCP tool in `Server.swift` adopting the same pattern) SHALL prefix the error body with the snake-case MCP tool name followed by `: `.

The error message format is:

```
Error: <mcp_tool_name>: <message_body>
```

Where `<mcp_tool_name>` matches the `case` label in the `Server.swift` `dispatch()` switch statement (e.g., `insert_paragraph`, `insert_equation`, `insert_image_from_path`, `insert_caption`).

`throw WordError.*` paths are explicitly excluded from this requirement — those errors are caught and rendered with tool context by the `dispatch()` wrapper.

#### Scenario: textNotFound error includes tool name

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x", after_text: "nonexistent" })` is called and the lookup fails
- **THEN** the response is `"Error: insert_paragraph: text 'nonexistent' not found (instance 1)"` (NOT the v3.15.x form `"Error: text 'nonexistent' not found (instance 1)"`)

#### Scenario: imageIdNotFound error includes tool name

- **WHEN** `insert_image_from_path({ doc_id: "d", path: "/tmp/x.png", after_image_id: "rId99" })` is called and `rId99` doesn't exist
- **THEN** the response is `"Error: insert_image_from_path: image rId 'rId99' not found"`

#### Scenario: into_table_cell partial dict error includes tool name

- **WHEN** `insert_paragraph({ doc_id: "d", text: "x", into_table_cell: { table_index: 0 } })` (missing `row` and `col`)
- **THEN** the response is `"Error: insert_paragraph: into_table_cell requires all three fields (table_index, row, col); got partial dict"`

#### Scenario: throw WordError.* paths unchanged

- **WHEN** `insert_paragraph({ /* missing doc_id */ })` is called
- **THEN** behavior is unchanged from v3.15.x — `throw WordError.missingParameter("doc_id")` is caught by `dispatch()` and rendered with existing tool-context wrapper. NOT subject to the `return "Error: ..."` prefix requirement.
