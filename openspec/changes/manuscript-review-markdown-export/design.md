## Context

This change spans three packages in the macdoc monorepo:

- `packages/markdown-swift/` (Layer 1) — gains a new `MarkdownBuilder` API
- `packages/ooxml-swift/` (Layer 1) — gains an additive `Document.getCommentsFull()` method
- `mcp/che-word-mcp/` (Layer 4) — gains 3 new MCP tools and a unified truncation policy migration

It bundles four GitHub issues that share infrastructure:

- [`PsychQuant/che-word-mcp#2`](https://github.com/PsychQuant/che-word-mcp/issues/2) — `export_revision_summary_markdown`
- [`PsychQuant/che-word-mcp#3`](https://github.com/PsychQuant/che-word-mcp/issues/3) — `compare_documents_markdown`
- [`PsychQuant/che-word-mcp#4`](https://github.com/PsychQuant/che-word-mcp/issues/4) — `export_comment_threads_markdown`
- [`PsychQuant/che-word-mcp#5`](https://github.com/PsychQuant/che-word-mcp/issues/5) — `get_revisions` truncation policy clarification

The originating use case is the tatsuma taxometric manuscript review (5 versions, 2 reviewers, 3 months — see [`PsychQuant/macdoc#75`](https://github.com/PsychQuant/macdoc/issues/75) tracking issue).

Current state of the repos:

- `mcp/che-word-mcp/Sources/CheWordMCP/Server.swift` (~9,100 lines) already exposes `get_revisions`, `list_comments`, `compare_documents` as plain-text-output tools. There is no shared markdown formatter; each tool ad-hoc concatenates strings.
- `packages/ooxml-swift/Sources/OOXMLSwift/Models/Comment.swift` already defines the full `Comment` struct with `parentId: Int?`, `isReply: Bool`, `getReplies(to:)`, but `Document.getComments()` returns a tuple that drops `parentId`.
- `packages/markdown-swift/` exists as Layer 1 and is consumed by `word-to-md-swift`. It has no programmatic builder API; current consumers write markdown via direct string interpolation.

## Goals / Non-Goals

**Goals:**

- Enable manuscript review reports to be generated in <5 seconds per version (vs ~30 minutes manually)
- Establish a shared `MarkdownBuilder` API reusable by future MCP servers and converters
- Establish a single, predictable truncation policy across all che-word-mcp tools that return potentially long text
- Close the ooxml-swift Comment API gap so threading-aware tools do not have to re-parse XML
- Resolve four GitHub issues as one coherent change

**Non-Goals:**

- Not extending `macdoc convert` CLI — markdown export is MCP-tool-only in this change. CLI integration is a separate future change.
- Not refactoring existing `list_comments` or `compare_documents` plain-text output — those tools keep their current text format. New markdown-output tools are additive.
- Not doing NLP-level cumulative analysis (e.g., "which sections were most contested") — `compare_documents_markdown` does mechanical aggregation only (counts, per-pair stats, optional narrative templates). Semantic analysis would require an LLM call inside the tool, which is out of scope.
- Not making ooxml-swift `Document.getComments()` return type a breaking change — additive new method only.
- Not implementing a `summarize: true` "smart truncation" beyond head+tail elision — heuristics like sentence-boundary cutting are out of scope; `summarize: true` is a simple fixed-policy fallback for extreme inputs.
- Not changing the markdown-swift consumers (`word-to-md-swift`) to use the new builder — they may migrate later but this change does not include that refactor.

## Decisions

### Decision: Change Location is macdoc/openspec

This change lives in `macdoc/openspec/changes/manuscript-review-markdown-export/`, not in `che-word-mcp` or `ooxml-swift` per-repo openspecs.

**Rationale**: The change touches three packages across two-plus git repos (`packages/markdown-swift/`, `packages/ooxml-swift/`, `mcp/che-word-mcp/`). The macdoc monorepo's openspec is the only level where one change document can describe the cross-package story coherently. The existing `che-pptx-mcp` change archived at `openspec/changes/archive/2026-03-21-che-pptx-mcp/` set this precedent — it spans both `packages/pptx-swift/` and `mcp/che-pptx-mcp/`.

**Alternatives**:
- _Per-repo spectras_ (init spectra in `che-word-mcp` and `ooxml-swift` separately) — rejected because spectra is per-repo and cannot model cross-repo dependencies; the dependency between the ooxml-swift `getCommentsFull()` API and the `export_comment_threads_markdown` tool would have to be tracked manually outside spectra.
- _Two macdoc changes_ (one for ooxml-swift API, one for markdown export tools) — rejected because the API is single-consumer (the threading tool) and bundling avoids "blocked on change A" sequencing.

### Decision: Bundle Scope Includes Four Issues

`#2` + `#3` + `#4` + `#5` ship as one change.

**Rationale**: `#3` and `#4` share `MarkdownBuilder` and `AuthorAliasMap`. `#2`'s per-doc summary builder is reused by `#3`'s pairwise diff. `#5`'s `full_text` → `summarize` migration cannot ship in isolation without forcing two API breaks on che-word-mcp consumers (one for `summarize`, another later for the bundled tools); doing it once is cheaper.

**Alternatives**:
- _Ship `#2` first, then `#3` + `#4` later_ — rejected because the second change would inherit the same MarkdownBuilder + AuthorAliasMap and cannot add value beyond what bundling provides.
- _Defer `#5` to a separate change_ — rejected because `#5`'s `summarize` policy must be defined before any new markdown export tool can adopt it consistently. Splitting forces re-litigating the policy in the second change.

### Decision: Capability Naming uses kebab-case domain-action

Two new capabilities: `markdown-builder` and `word-mcp-markdown-export`.

**Rationale**: Matches the existing convention in `openspec/specs/` (`pptx-mcp-server`, `pptx-parsing`, `pptx-slide-read`, `pptx-slide-write`, `simplified-pdf-ocr`).

**Alternatives**:
- _One combined capability `manuscript-review-export`_ — rejected because the `MarkdownBuilder` is reusable infrastructure, not manuscript-specific; conflating it with the use case would prevent future reuse from being spec-tracked.
- _Three capabilities, one per tool_ — rejected as over-decomposed; the three tools share a single coherent design (markdown export + truncation policy + alias normalization) and split-spec would duplicate scenarios.

### Decision: MarkdownBuilder Lives in markdown-swift Package

`MarkdownBuilder` is added to `packages/markdown-swift/Sources/MarkdownSwift/MarkdownBuilder.swift`, not inside `mcp/che-word-mcp/`.

**Rationale**: `markdown-swift` is already the Layer 1 Markdown generation package per `CLAUDE.md` architecture. A programmatic builder belongs there alongside `MarkdownWriter` (existing `word-to-md-swift` consumer). Future MCP servers (`che-pdf-mcp`, hypothetical `che-pptx-mcp` markdown export) can depend on the same package.

**Implementation note (added during apply, 2026-04-15)**: The package already contains `MarkdownWriter<StreamingOutput>`, a streaming throwing API used by `word-to-md-swift`. `MarkdownBuilder` is implemented as a thin chainable wrapper around `MarkdownWriter<StringOutput>`, reusing its escaping logic (`MarkdownEscaping`) and state machine (`needsBlankLine`, `listDepth`). The two APIs coexist with distinct ergonomics: `MarkdownWriter` for streaming pipelines that propagate IO errors, `MarkdownBuilder` for in-memory programmatic composition where chaining is preferred and IO failure is not a concern.

**Alternatives**:
- _Builder lives in che-word-mcp_ — rejected; future MCP servers would copy-paste the API.
- _Builder lives in a new `markdown-builder-swift` package_ — rejected; markdown-swift is already the home for markdown generation and adding a fourth subpackage is unnecessary fragmentation.
- _Scrap `MarkdownBuilder`, have MCP tools use `MarkdownWriter` directly_ — rejected during apply once the existing `MarkdownWriter` was discovered: `MarkdownWriter`'s throwing streaming API leaks IO error semantics into MCP tool code that assembles strings; the wrapper preserves clean MCP tool ergonomics with no functional duplication.

### Decision: ooxml-swift API is Additive (new getCommentsFull method)

`Document.getCommentsFull() -> [Comment]` is added. The existing `Document.getComments() -> [(id:, author:, text:, paragraphIndex:, date:)]` tuple-returning method is unchanged.

**Rationale**: The current `listComments` MCP tool destructures the tuple at `Server.swift:5999`. A breaking change would require synchronized updates across all callers (currently only one, but the additive API is so cheap that there is no benefit to forcing the migration). The new method's name pairs with a `Full` suffix that signals "complete struct, not summary tuple".

**Alternatives**:
- _Replace tuple with `[Comment]`_ — rejected for backward compatibility; downstream consumers in `che-word-mcp` and any future external consumer would have to update simultaneously with the ooxml-swift release.
- _Extend tuple to add `parentId`_ — rejected because the tuple shape will keep growing with future fields (resolved status, mentions, etc.); switching to a struct return type once is cleaner than incremental tuple sprawl.
- _Expose `Comment.parentId` via a separate `getCommentParents() -> [Int: Int]` lookup_ — rejected as awkward; callers would need both a list and a parent map and stitch them together.

### Decision: Truncation Policy is Default-Complete

All MCP tools that return potentially long text accept a `summarize: Bool = false` parameter. Default behavior returns complete text with no implicit upper bound. `summarize: true` activates head+tail elision per entry.

**Rationale**: Silent data loss via default truncation is harder to debug than context-window overflow. LLM callers that exceed context can re-invoke with `summarize: true`; a tool that secretly truncates leaves no recovery path. This inverts the previous `full_text: false` default for `get_revisions` (which forced opt-in for completeness — the wrong default).

**Alternatives**:
- _No `summarize` parameter at all (always complete)_ — rejected because legitimate summary use cases exist (e.g., 100 revisions × 10 KB each = 1 MB context) and opt-in elision is a useful escape hatch.
- _`max_chars: Int?` opt-in numeric limit_ — rejected as more API surface (caller must guess a number) without proportional benefit; a single boolean covers the use case.
- _Soft cap with auto-elision and warning_ — rejected as implicit behavior; default-complete with explicit opt-in is more predictable.

### Decision: Elision Threshold is 5000 chars per entry

When `summarize: true`, individual entries (a single revision's text, a single comment's text, a single diff entry) below 5000 chars are returned complete. Entries above 5000 chars are formatted as `head[30 chars] [...] tail[30 chars]`.

**Rationale**: Empirical sizing — typical manuscript comments range 50–500 chars; reviewer long-form comments rarely exceed 2000 chars; only extreme cases (entire paragraph rewrites pasted into a single comment) exceed 5000 chars. The threshold is intentionally large so opt-in elision rarely fires in practice but provides a cap when it does. The `[30 chars]` head and tail follow the existing `truncateText` helper convention in `Server.swift:7849`.

**Alternatives**:
- _500 chars (current `truncateText` default)_ — too aggressive; fires on routine reviewer comments.
- _10,000 chars_ — large enough to feel like no-cap; chosen 5000 as conservative for the first iteration with room to raise later.
- _Dynamic threshold based on total payload size_ — rejected as implicit; per-entry threshold is predictable.

### Decision: Author Alias Normalization is Shared Helper

A `AuthorAliasMap` value type lives in `mcp/che-word-mcp/Sources/CheWordMCP/` (consumed by `#3` and `#4` tools). The map is `[String: String]` from raw author name to canonical name. Tool input accepts an optional `author_aliases` argument that constructs the map per call.

**Rationale**: `#3` and `#4` both need this; one helper avoids drift. Per-call input (not config file) keeps the MCP tool stateless and allows different review sessions to use different alias maps.

**Alternatives**:
- _Each tool maintains its own alias logic_ — rejected; risk of drift in matching rules (case-insensitive? trim?).
- _Persistent config file in che-word-mcp_ — rejected; adds state and config complexity for marginal benefit.

## Risks / Trade-offs

- **Risk**: ooxml-swift release coordination — adding `getCommentsFull()` requires a `packages/ooxml-swift/` commit + tag + push, then `mcp/che-word-mcp/Package.swift` `swift package update`. If done in wrong order, builds fail.
  - **Mitigation**: Tasks document the sequence explicitly; CI build on che-word-mcp validates the dependency resolution.

- **Risk**: `summarize` migration breaks downstream callers using `full_text: true` — any LLM agent or hard-coded caller passing `full_text` will silently get the old default behavior (truncation) until they update.
  - **Mitigation**: CHANGELOG and che-word-mcp README document the migration. Tool description includes the new parameter name. The default change (`full_text: false` → `summarize: false`) is in the *less surprising* direction (more data, not less), so accidental over-completeness is the failure mode rather than data loss.

- **Risk**: 5000-char threshold is wrong for some real corpora — academic preprint reviewers occasionally paste large blocks.
  - **Mitigation**: Threshold is a constant in code, easy to bump. First-iteration choice is intentionally conservative; can ship a follow-up to raise to 10,000 if telemetry shows frequent elision firing.

- **Risk**: `Old:` pattern detection in `#4` produces false positives (any comment that happens to contain "Old:" as literal text gets misclassified as informal reply).
  - **Mitigation**: Make pattern detection opt-in via `detect_old_pattern: Bool = false` on the tool call. Document the pattern's regex and known limitations in the tool description. Validation tasks include testing against the tatsuma manuscript corpus.

- **Trade-off**: Bundling `#5` into a feature-typed change rather than handling as standalone bug — the unified migration is cleaner but the "fix" is now coupled to feature delivery timeline.
  - **Mitigation**: Apply phase order tasks so the `summarize` migration lands first (one-line default change + tool schema rename), making the bug-fix portion deployable even if other tools slip.

- **Trade-off**: `MarkdownBuilder` is brand new in `markdown-swift` but only one immediate consumer (the three new tools) — risk of API design that fits one use case but locks future consumers.
  - **Mitigation**: Design the builder API minimally (only methods needed by the three tools); explicitly defer "rich" features (footnotes, math, custom blocks) to later changes when concrete consumers exist. Document this in the spec's scope statement.

## Migration Plan

1. **Implementation order** (within this change's tasks):
   1. `markdown-swift` MarkdownBuilder (no breaking change, additive)
   2. `ooxml-swift` `getCommentsFull()` additive method (push tag → consume in che-word-mcp)
   3. `che-word-mcp` `summarize` parameter migration (replaces `full_text` in `get_revisions` and `compare_documents`)
   4. `che-word-mcp` three new markdown export tools

2. **For che-word-mcp downstream consumers** (LLM agents, scripts):
   - **No-op for callers that did not pass `full_text`**: behavior changes from "truncate at 500 chars" to "return complete text". This is the intended improvement.
   - **Callers passing `full_text: true`**: remove the argument; default is now complete.
   - **Callers passing `full_text: false`**: replace with `summarize: true`.
   - Document migration in `mcp/che-word-mcp/CHANGELOG.md` under the version bump.

3. **Rollback**: revert the entire change as one commit. Because all four packages live in the macdoc monorepo (with ooxml-swift updated via package tag), rollback requires reverting the macdoc commit + reverting the ooxml-swift tag + re-pinning che-word-mcp's `Package.resolved`. Document this rollback procedure in the change's tasks for the apply phase.

## Open Questions

- _(none open as of proposal — all key decisions resolved during `/spectra-discuss` phase)_
