## Problem

PsychQuant/che-word-mcp#90 exposed a mismatch between user-facing math notation and the current OOXML text universe used for insertion anchors.

The concrete symptom is `H_0` written as Unicode subscript text by a user (`H₀`) not matching the flattened OMML visible text emitted by the library (`H0`). The anchor text is semantically the same for thesis/advisor review workflows, but the current `String.contains`-style lookup treats the two strings as unrelated.

This is not only a che-word-mcp schema issue. The root behavior belongs in the shared OOXML anchor lookup layer so MCP insertion tools, direct OOXMLSwift callers, and future search flows do not each invent their own Unicode workaround.

## Root Cause

`MathSubSuperScript.visibleText` intentionally emits a plain ASCII mirror such as `H0` for `H₀`. That output is useful for stable text extraction and should not be changed casually.

The anchor lookup path then compares caller-provided text directly against the flattened display text. Because neither side is normalized, these equivalent math-script variants fail bidirectionally:

- User anchor `H₀` vs flattened text `H0`
- User anchor `H0` vs document text that already contains Unicode subscript `H₀`

The bug is therefore a missing matching-mode contract, not a reason to change the default visible-text representation.

## Proposed Solution

Add an opt-in, bidirectional math-script-variant matching mode.

1. Add an OOXMLSwift anchor lookup option, tentatively named `mathScriptInsensitive`.
2. Keep default matching byte/string-exact so existing callers see no behavior change.
3. When the option is enabled, normalize both haystack and needle into a canonical ASCII math-script form before matching.
4. Preserve `MathSubSuperScript.visibleText` output and all read/export defaults.
5. Surface the option through che-word-mcp insertion anchor tools as a future-proof `match_options` object:

```json
{
  "after_text": "H₀",
  "match_options": {
    "math_script_insensitive": true
  }
}
```

The initial MCP scope is the insertion-anchor family that resolves `after_text` / `before_text`: `insert_paragraph`, `insert_equation` display mode, `insert_image_from_path`, and `insert_caption`.

## Non-Goals

- Do not change `MathSubSuperScript.visibleText` output.
- Do not change default anchor lookup behavior.
- Do not introduce broad Unicode normalization such as NFC/NFD folding in this change.
- Do not make approximate/fuzzy text matching.
- Do not change render/page-layout behavior.
- Do not redesign paragraph index semantics.
- Do not bundle unrelated `replace_text` behavior unless it already consumes the same shared anchor lookup API during implementation.

## Stakes

For thesis/advisor review workflows, equations are often referenced in natural prose as `H₀`, `αᵢ`, or similar notation. If agents cannot anchor insertions near those expressions, comment insertion and advisor-response workflows become brittle exactly where precision matters most.

The main risk is silent over-matching. Making the mode explicit, default-off, and limited to math script variants keeps the contract reviewable and avoids surprising callers that depend on exact anchors.

## Issue Link

Refs PsychQuant/che-word-mcp#90.
