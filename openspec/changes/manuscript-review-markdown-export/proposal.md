## Why

Manuscript review on `.docx` (e.g., the 2026-04-14 tatsuma taxometric paper — 5 versions, 2 reviewers, 3 months) currently requires ~30 minutes per version to turn raw `get_revisions` / `list_comments` / `compare_documents` MCP output into a readable change-log note. Three recurring manual steps dominate the cost: (a) grouping comments into threads with parent-reply structure, (b) normalizing reviewer aliases (`kllay's PC` → `Lay` when the same reviewer uses two machines), and (c) stitching pairwise diffs across N versions into a cumulative timeline. This change closes that gap by adding MCP-level markdown export tools that compose over existing primitives.

## What Changes

- **New MCP tools** in `mcp/che-word-mcp/`:
  - `export_revision_summary_markdown`: per-doc revision + comment summary with stats and tables (tracks [PsychQuant/che-word-mcp#2](https://github.com/PsychQuant/che-word-mcp/issues/2))
  - `compare_documents_markdown`: multi-doc cumulative timeline with pairwise transitions (tracks [PsychQuant/che-word-mcp#3](https://github.com/PsychQuant/che-word-mcp/issues/3))
  - `export_comment_threads_markdown`: comment + reply threading with author alias normalization and `Old:` pattern detection (tracks [PsychQuant/che-word-mcp#4](https://github.com/PsychQuant/che-word-mcp/issues/4))
- **New shared library** in `packages/markdown-swift/`: `MarkdownBuilder` API for programmatic markdown generation (`heading`, `table`, `bulletList`, `codeBlock`, `paragraph`) usable by all MCP servers and converters
- **New ooxml-swift API**: `Document.getCommentsFull() -> [Comment]` that returns the complete `Comment` struct including `parentId`. Additive (does not modify existing tuple-returning `getComments()`). Enables comment threading without XML re-parsing.
- **BREAKING (MCP tool argument)**: che-word-mcp tool arguments migrate from `full_text: Bool = false` to `summarize: Bool = false`, inverting the default. All tools that previously truncated by default now return complete text by default. Affected tools: `get_revisions`, `compare_documents`. Also sets the convention for all new tools listed above.
  - Reason: silent data loss via default truncation is harder to debug than context-window overflow; LLM callers can re-invoke with `summarize: true` when needed.
  - Migration: `full_text: true` calls should be replaced with omitting the argument (or `summarize: false`); `full_text: false` calls should be replaced with `summarize: true`.
- **Shared `AuthorAliasMap` helper** in `mcp/che-word-mcp/`: map from raw author name (as stored in docx XML) to canonical name, usable across `#3` and `#4` tools.
- **Resolves [PsychQuant/che-word-mcp#5](https://github.com/PsychQuant/che-word-mcp/issues/5)**: the `full_text` → `summarize` migration supersedes the #5 stale-source report; once this change ships, the tool surface reflects the intent #5 was asking for.

## Non-Goals

<!-- Non-Goals live in design.md (Goals/Non-Goals section) since design.md will be created. -->

## Capabilities

### New Capabilities

- `markdown-builder`: Programmatic markdown generation API in the `markdown-swift` package — heading, table, bullet/numbered list, code block, paragraph builders. Used by MCP tools and converters to compose markdown output without ad-hoc string concatenation.
- `word-mcp-markdown-export`: MCP tools in `che-word-mcp` that export manuscript review artifacts as markdown — per-doc revision summary, cumulative cross-version timeline, comment thread view with alias normalization. Defines the `summarize: Bool = false` truncation policy shared across all che-word-mcp tools that return potentially long text.

### Modified Capabilities

(none)

## Impact

- **Affected specs**:
  - New: `openspec/specs/markdown-builder/spec.md`
  - New: `openspec/specs/word-mcp-markdown-export/spec.md`
- **Affected code**:
  - New: `packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift` (+ tests)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (new `getCommentsFull()` method)
  - Modified: `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift`:
    - Tool schema: replace `full_text` with `summarize` in `get_revisions` and `compare_documents`
    - New tools: `export_revision_summary_markdown`, `compare_documents_markdown`, `export_comment_threads_markdown`
    - New helpers: `AuthorAliasMap`, MarkdownBuilder-backed formatters
  - Modified: `mcp/che-word-mcp/mcpb/manifest.json` (version bump)
  - Modified: `mcp/che-word-mcp/CHANGELOG.md`
- **Dependencies**:
  - `mcp/che-word-mcp/Package.swift` depends on `markdown-swift` (added) and `ooxml-swift` (existing)
  - ooxml-swift package update workflow applies: commit + push + tag in `packages/ooxml-swift/`, then `swift package update` in `mcp/che-word-mcp/`
- **External cross-repo impact**:
  - Closes `PsychQuant/che-word-mcp#2` `#3` `#4` `#5` upon apply
  - Advances `PsychQuant/macdoc#75` (umbrella tracking issue) — Layer 1 (ooxml-swift Comment API) + Layer 2 (che-word-mcp markdown export) nodes
  - Downstream `PsychQuant/psychquant-claude-plugins#26` (archive-mail attachment routing) can start consuming the new tools once apply completes
