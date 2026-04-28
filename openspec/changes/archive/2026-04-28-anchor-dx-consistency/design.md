## Design

Three coordinated MCP-layer changes touching `Sources/CheWordMCP/Server.swift`. Each spelled out below with the **mechanism**, **tool-by-tool surface**, and **trade-off considered**.

---

### 1. Conflict detection algorithm (#71)

#### Mechanism

A small helper at the top of each anchor-handling tool function. Per-anchor type-aware presence check — required because `Value` is JSON-shaped: a key may be present but typed as `null` (e.g., LLM emits `{"index": null}`), and `into_table_cell` is dict-typed while other anchors are `String` or `Int`. Uniform `args[k] != nil` would false-positive on null-typed values.

```swift
// Helper (defined once near top of Server.swift)
private static let anchorPresence: [String: (Value) -> Bool] = [
    "into_table_cell":   { $0.objectValue != nil },
    "after_image_id":    { $0.stringValue != nil },
    "after_text":        { $0.stringValue != nil },
    "before_text":       { $0.stringValue != nil },
    "index":             { $0.intValue    != nil },
    "paragraph_index":   { $0.intValue    != nil },
    "after_table_index": { $0.intValue    != nil },
]

private static func detectPresentAnchors(_ args: [String: Value], anchors: [String]) -> [String] {
    return anchors.compactMap { name in
        guard let value = args[name],
              let predicate = anchorPresence[name],
              predicate(value)
        else { return nil }
        return name
    }.sorted()
}
```

`null`-typed and wrong-type values do NOT count as present — they're treated as if the param were omitted. This matches existing dispatcher behavior (an `args["after_text"]?.stringValue` that returns nil falls through to the next branch).

Each tool calls it with the anchor set it accepts:

```swift
// In insertParagraph(args:)
let presentAnchors = detectAnchorConflicts(args, anchors: [
    "into_table_cell", "after_image_id", "after_text", "before_text", "index"
])
if presentAnchors.count > 1 {
    return "Error: insert_paragraph: received conflicting anchors: \(presentAnchors.joined(separator: " + ")). Specify exactly one."
}
// ... existing dispatcher unchanged below
```

Per-tool anchor sets:

| Tool | Anchor set |
|---|---|
| `insert_paragraph` | `into_table_cell`, `after_image_id`, `after_text`, `before_text`, `index` |
| `insert_equation` (display mode) | `into_table_cell`, `after_image_id`, `after_text`, `before_text`, `paragraph_index` |
| `insert_equation` (inline mode) | _no anchors accepted; existing rejection path unchanged_ |
| `insert_image_from_path` | `into_table_cell`, `after_image_id`, `after_text`, `before_text`, `index` |
| `insert_caption` | `paragraph_index`, `after_image_id`, `after_table_index`, `after_text`, `before_text` |

#### Why `return "Error: ..."` and not `throw WordError.invalidParameter`

Three of the four tools already use the `return "Error: ..."` style for runtime failures (textNotFound, tableIndexOutOfRange). Throwing here would create an inconsistent "throw for input validation, return for runtime" split that AI callers' error parsers would have to handle twice.

If we ever sweep ALL error returns to throws (separate larger refactor), this changes too. For now, match the dominant pattern.

#### Edge case: `into_table_cell` partial dict

Currently (v3.15.1+) returns `"Error: into_table_cell requires all three fields"`. Conflict detection runs BEFORE the partial-dict check — so a user passing `into_table_cell={table_index:0}` AND `after_text="foo"` sees the conflict error first. That's correct: conflict is the more fundamental issue; once they remove the redundant `after_text`, they then see the partial-dict error.

---

### 2. text_instance validation (#72)

#### Mechanism

After the existing `let textInstance = args["text_instance"]?.intValue ?? 1`, add:

```swift
if let explicit = args["text_instance"]?.intValue, explicit < 1 {
    return "Error: insert_paragraph: text_instance must be ≥ 1, got \(explicit)."
}
```

Note: only error when **explicit**. Omitting the param keeps current default-to-1 behavior — that's a sensible coalesce, not user input.

#### Why ≥ 1, not ≥ 0

The `instance` parameter is 1-indexed in lib API (`InsertLocation.afterText("foo", instance: 1)` = "first match"). `instance: 0` doesn't have lib-side semantics ("zeroth match" is undefined). Forbidding it pushes the user toward the documented contract.

#### Where applied

Wherever `text_instance` is read in 4 #61-target tools (~4 spots). Modifier-only places (e.g., `insert_caption`'s anchor params other than text-search) don't read `text_instance` and aren't touched.

---

### 3. Tool-prefix error messages (#70)

#### Mechanism

Mechanical rewrite: every `return "Error: <body>"` in 4 #61-target tools becomes `return "Error: <tool_name>: <body>"`.

#### Convention

```
Error: <mcp_tool_name>: <message>
```

`<mcp_tool_name>` matches the tool name in the dispatcher `case` (`insert_paragraph`, `insert_equation`, etc.). Snake-case, no quotes.

`<message>` keeps existing wording verbatim — only the prefix is added.

Examples:

| Before | After |
|---|---|
| `Error: text 'foo' not found (instance 1)` | `Error: insert_paragraph: text 'foo' not found (instance 1)` |
| `Error: image rId 'rId99' not found` | `Error: insert_image_from_path: image rId 'rId99' not found` |
| `Error: into_table_cell requires all three fields` | `Error: insert_equation: into_table_cell requires all three fields` |

#### Phasing — limited to 4 #61-target tools, global sweep deferred

This change applies the convention to **only** the 4 #61-target tools (32 `return "Error: ..."` lines, well-trodden code paths). A separate `error-prefix-sweep` change tackles the remaining 41 lines across ~50 unfamiliar handlers in `Server.swift`. Rationale for the split:

- 41 lines across 50+ handlers means substantial scope expansion — each handler's tool name must be looked up in the `dispatch()` switch (`Server.swift:5639+`) and matched precisely.
- Touching unfamiliar handlers risks subtle mistakes (e.g., handler named `formatText` but tool key is `format_text` — easy to invert).
- Bundling them together makes this change exceed the recommended 15-task scope guideline.
- The 41 follow-up lines are mechanically identical (same regex find-and-replace pattern), so a separate small change is low-risk and reviewable in one sitting.

The pre-test grep regression pin (Phase 5.5) lives in this change and **only** asserts zero un-prefixed lines in the 4 target tools. The `error-prefix-sweep` follow-up extends the pin globally.

#### `throw WordError.*` left alone

These are caught by the `dispatch()` wrapper and rendered with tool context already. Touching them here would risk double-prefixing.

---

### Cross-cutting: backward-compat note + SemVer rationale

This is a **behavior change for callers passing 2+ anchors** (estimate from grep of test fixtures: zero callers in our test suite; risk to external callers unknown).

**SemVer choice — minor bump v3.16.0, NOT major v4.0.0**, because:

1. **No schema break**: `tools/list` JSON schema is unchanged. Same params accepted (all Optional), same types. JSON Schema can't express "exactly one of these N fields", so the schema couldn't have communicated the constraint anyway.
2. **No tool removal/rename**: 4 tool names + their full param sets unchanged.
3. **Restricting previously-undefined behavior**: silent priority order was never documented as contract — it's an implementation detail that leaked. Tightening into a structured error is "implementation-defined behavior is now diagnosed", which SemVer minor permits per the same-rationale used when adding stricter input validation to a stable API.
4. **Major bump (v4.0.0) reserved** for actual breakage: tool removal, required-param additions, response-shape changes (e.g., success messages change format), or breaking changes to documented contracts.

If real-world breakage exceeds expectations post-release, fallback design is `anchor_strategy: "first_match" | "strict"` opt-in (default `strict` = v3.16.0 behavior; `first_match` = v3.15.x behavior). Defer until proven needed.

Mitigations:

1. Ships in v3.16.0 (minor bump signals scope).
2. Error message itemizes the conflicting anchors so callers can debug from the error text alone.
3. CHANGELOG entry explicitly calls out the behavior change in v3.16.0 with migration guidance ("if you previously relied on `after_text` winning over `index`, drop the `index` param").

### Cross-cutting: error message language

Error messages stay in English (existing convention in `Server.swift`). User-facing schema descriptions in Chinese; internal error strings in English so they parse consistently regardless of caller locale.

---

### Test strategy

`Tests/CheWordMCPTests/AnchorDXConsistencyTests.swift` (new file) covering:

- **Conflict detection**: 4 tools × 3 conflict combinations (e.g., `after_text + index`, `into_table_cell + after_text`, `after_image_id + before_text`) = 12 sub-tests asserting each returns `"Error: <tool>: received conflicting anchors..."` with the 2 anchor names.
- **text_instance validation**: 4 tools × 2 boundary values (`-1`, `0`) = 8 sub-tests asserting `"Error: <tool>: text_instance must be ≥ 1..."`.
- **Backward-compat**: 4 tools × happy path (single anchor) = 4 sub-tests asserting unchanged behavior.
- **Tool-prefix mechanical sweep regression pin**: 1 sub-test using grep on Server.swift source asserting zero occurrences of `return "Error: [^:]+ not found` (i.e., un-prefixed `return "Error:"` lines).

Estimate: 25 new sub-tests; suite 201 → 226 (+25, expect 0 fail).

### Out of scope (decisions made)

- **Schema-side validation** (rejecting at `tools/list` JSON-Schema layer instead of dispatch handler) — JSON Schema can't express "exactly one of these N fields", only `oneOf`. Worth exploring later if the conflict pattern needs cleaner schema documentation; not blocking.
- **`anchor_strategy` opt-in** — deferred until proven needed (see backward-compat note).
- **Inline equation anchor support (#67)** — separate decision; not bundled.
- **Lib-layer index-convention unification** — PsychQuant/ooxml-swift#10, separate process.
