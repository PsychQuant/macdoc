## Problem

After v3.15.0/v3.15.1 unified the anchor parameter set across the 4 `#61`-target tools (`insert_paragraph` / `insert_equation` display mode / `insert_image_from_path` / `insert_caption`), three follow-up issues from verify-69 ensemble surfaced a coherent gap: **the MCP layer accepts ambiguous, malformed, or boundary inputs without surfacing structured errors**. AI callers parsing tool output cannot distinguish between "the tool ran and reports success" and "the tool silently picked one of my conflicting params and proceeded."

Three concrete symptoms (PsychQuant/che-word-mcp #71 / #72 / #70):

1. **#71 — Silent priority winner on conflicting anchors**: `insert_paragraph(after_text="foo", index=3)` silently picks `after_text` (per the hardcoded priority chain at `Server.swift:6612-6660`) and ignores `index`. The AI caller gets `"Inserted paragraph after text 'foo' (instance 1)"` and assumes its `index=3` was honored. Same pattern in `insertEquation`, `insertImageFromPath`, `insertCaption`.
2. **#72 — `text_instance ≤ 0` propagates silently**: schema accepts any `Int`; defaults to `1` when omitted (`Server.swift:6614`); but explicit `text_instance: 0` or negative values pass through to lib `.afterText(_, instance: 0)` without validation. Either the lib silently coerces (caller can't tell) or throws an error that doesn't identify the originating MCP tool.
3. **#70 — Error messages lack tool-prefix**: half the error paths use `throw WordError.*` (structured, gets tool name from caller catch); the other half use `return "Error: text 'foo' not found (instance 1)"` (raw string, no tool identifier). When 5 tools all return `"Error: text 'foo' not found"` an AI parsing the response can't tell which call failed without correlating with the most recent tool invocation — fragile.

A 4th related issue (#67) — "should `insert_equation` inline mode accept anchors?" — is **deferred to wontfix-with-rationale** in a separate small fix, not bundled here. Inline equations are a structurally different shape (run-inside-paragraph) where paragraph-level anchor semantics are ill-defined; bolting the unified set on would muddy the contract. See decision rationale in #67 closing comment.

## Root Cause

The 4 #61-target tools share a common anchor-resolution dispatcher pattern that grew incrementally:

```swift
// Server.swift:6612-6660 (insertParagraph), repeated near-verbatim in 3 sibling tools
if let cellDict = args["into_table_cell"]?.objectValue { ... }
else if let afterImageId = args["after_image_id"]?.stringValue { ... }
else if let afterText = args["after_text"]?.stringValue { ... }
else if let beforeText = args["before_text"]?.stringValue { ... }
else if let index = args["index"]?.intValue { ... }
else { /* append */ }
```

This `if/else if` chain has three structural problems:

1. **Silently swallows extras**: 2nd+ branch never fires; no diagnostic emitted.
2. **No input validation before dispatch**: `text_instance` is fetched once at the top with `?? 1` (default), bypassing range checks even when user explicitly sets it.
3. **Error returns are stylistically split**: `throw WordError.*` for missing-required-param errors; `return "Error: ..."` for runtime errors (textNotFound, tableIndexOutOfRange, malformed dict). The latter forms the bulk of caller-visible errors but lacks tool identification.

Each issue (#70/#71/#72) addresses one of these in isolation, but the fixes touch the same dispatcher block in all 4 tools (≈ 4 × 60 lines of overlapping edits). Doing them as one consistency sweep avoids 3× repeated edits and lands as one coherent UX shift.

## Proposed Solution

One Spectra change (`anchor-dx-consistency`), one PR, three coordinated changes scoped to MCP layer (`Sources/CheWordMCP/Server.swift`) — no lib-layer changes:

### 1. Conflict detection (#71): reject 2+ anchor params with structured error

Before the existing dispatcher, count non-nil anchor params. If count > 1, return `"Error: <tool>: received conflicting anchors: <a> + <b>[ + <c>...]. Specify exactly one."` (or `throw WordError.invalidParameter(...)` — design decision in `design.md`).

Anchor knobs counted: `into_table_cell`, `after_image_id`, `after_text`, `before_text`, `paragraph_index` / `index`. Modifiers (`text_instance`, `position`, `style`) are NOT anchors and don't count.

### 2. text_instance validation (#72): reject explicit ≤ 0

Add `guard textInstance >= 1` after the `?? 1` default. Explicitly omitted = default 1 (silent, current behavior preserved). Explicitly passed `0` or negative = `"Error: <tool>: text_instance must be ≥ 1, got <N>."`

Applies wherever `text_instance` is read in the 4 tools.

### 3. Tool-prefix error messages (#70): rewrite `return "Error: ..."` lines in 4 #61-target tools

Convert `return "Error: text 'foo' not found (instance 1)"` → `return "Error: insert_paragraph: text 'foo' not found (instance 1)"`. **Scoped to the 4 #61-target tools (32 `return "Error: ..."` lines)**; the remaining 41 `return "Error: ..."` lines elsewhere in `Server.swift` (~50 unfamiliar handlers) are deferred to a separate `error-prefix-sweep` follow-up change to keep this bundle reviewable. See design §3 *Phasing*.

`throw WordError.*` paths are unchanged — those already get tool name from the caller's catch handler at `dispatch(...)` level.

## Non-Goals

- **Not changing schema (`tools/list` output)** — same params accepted; validation tightened. JSON schema would still describe these as Optional. Backward-compat shim: callers passing only one anchor at a time (the documented-and-modeled pattern) see no change.
- **Not changing lib (`PsychQuant/ooxml-swift`)** — all enforcement at MCP layer. Lib-layer convention questions (body.children vs paragraph-only index split) live at PsychQuant/ooxml-swift#10 separately.
- **Not addressing #67 (inline equation anchors)** — see decision in #67 closing comment; rejected with rationale, not bundled here.
- **Not introducing `--allow-priority-winner` opt-out** — opt-outs to reject become "the way to do it" for AI callers and erode the contract. If a real workflow needs priority fallback, design it as explicit "fallback chain" parameter (`anchor_strategy: "first_match"`) — separate change.

## Stakes

**For**: AI callers (Claude, Cursor, etc.) get unambiguous error/success boundaries. Prompts that accidentally include 2 anchors (e.g., LLM hedging "I'll specify both `after_text` AND `index` in case one fails") fail loud instead of misleading-success. Tool-prefix error messages let log-parsers and chained-tool flows attribute failures correctly.

**Against**: Behavior change — callers currently relying on the silent priority order (undocumented but existent for 9 months) break. Risk-mitigated by (a) priority order was never documented as contract, (b) the change error-messages clearly state which 2 anchors conflicted so callers can fix prompts, (c) ships in v3.16.0 minor bump (signals breaking change scope).

## Bundle Context

This is the third bundle in the verify-driven cleanup chain:
- Bundle A (v3.15.2) closed #69 + #73 + #74 + #75
- Bundle A2 (v3.15.3) closed #76 + #77 + #78 + #79
- **Bundle B (v3.16.0)** — this change closes #70 + #71 + #72; #67 closes separately as wontfix-with-rationale

Remaining open work after Bundle B: #62 / #68 / #16 (each standalone, separate spectra-discuss).
