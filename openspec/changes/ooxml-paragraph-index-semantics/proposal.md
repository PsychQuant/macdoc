## Why

`ooxml-swift` currently exposes paragraph mutator APIs whose `at: Int` parameters mean different things depending on the method: some use raw `body.children` positions while others translate through top-level paragraph-only indexes. This creates silent caller confusion and already forced downstream `che-word-mcp` to carry call-site workarounds.

## What Changes

- Standardize document body insertion and mutation APIs around explicitly named index bases, with body-position APIs using top-level `body.children` indexes.
- Add explicitly named paragraph-only APIs for callers that need nth top-level paragraph semantics.
- Add shared internal helpers for body-child and top-level-paragraph index validation instead of repeating ad-hoc `paragraphIndices` translation.
- Deprecate legacy paragraph-only overloads whose names do not state their index basis, with a one-minor-release warning period before any major removal.
- Document that recursive read APIs such as `getParagraphs()` are not index-compatible with top-level body mutation APIs.

## Non-Goals

- Do not introduce compile-time index newtypes in this change. They remain a future option if callers continue mixing index spaces after the naming cleanup.
- Do not change recursive `getParagraphs()` ordering or scope.
- Do not migrate downstream `che-word-mcp` behavior in this proposal; that belongs in a coordinated follow-up implementation PR.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `ooxml-document-part-mutations`: define consistent paragraph/body index semantics for `WordDocument` mutator APIs.

## Impact

- Affected specs: `ooxml-document-part-mutations`
- Affected code:
  - Modified: packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift
  - Modified: packages/ooxml-swift/Tests/OOXMLSwiftTests
  - Modified: mcp/che-word-mcp/Sources
- Related issue: PsychQuant/ooxml-swift#10
