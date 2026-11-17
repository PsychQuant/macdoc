## Summary

Make the requirement "Unreadable tables are reported whatever their paragraph ids" state only what `macdoc word form classify --grid` does and what a test checks.

## Motivation

A review of the requirement found three wording problems and one stale proposal:

- The Scenario says neither stdout nor stderr carries "any control character", but stdout separates fields with tabs and both streams end lines with a newline. What is meant is that no control character taken from the paragraph's `w14:paraId` or text appears.
- The Scenario says stderr does not carry the paragraph's text, but neither the Example nor the test checks stderr for that text.
- The requirement calls its exceptions "a closed description" with two cases (a nested table, a text box). The positive condition is right, but other containers also keep a paragraph out of the cell, for example a block-level `mc:AlternateContent`. The classifier looks through `w:sdt`, `w:sdtContent` and `w:customXml` only, so the note is written when, and only when, the nearest container found that way is a `w:tc` of the table; the two cases are examples of that.
- The open change `docx-form-normalization` still lists `docx-form-normalization` as a new capability, although the main spec for that capability already exists.

## Proposed Solution

- MODIFIED requirement "Unreadable tables are reported whatever their paragraph ids": the note is written when, and only when, the condition holds; the wrappers looked through are named as the only ones; the nested table, text box and block-level `mc:AlternateContent` cases are given as examples. The Scenario's THEN speaks of control characters taken from the paragraph's `w14:paraId` or text. The Example's THEN also requires that stderr does not contain the paragraph's text.
- `testClassifyGridNotesAnUnreadableTableWhoseIdsAreAllSkipped` gains the stderr assertion.
- The proposal of the open change `docx-form-normalization` lists the capability under Modified Capabilities.

## Non-Goals

- No change to the CLI's output. The text of both note forms stays as it is.
- The choice between the two note forms on a malformed table that has paragraphs printed outside `tN:?` is a separate issue (#298).
- The delta of the open change `docx-form-normalization` is not changed; only its proposal text is.

## Impact

- Affected specs: `docx-form-normalization` (modified)
- Affected code:
  - Modified: openspec/specs/docx-form-normalization/spec.md, Tests/MacDocCLITests/WordFormCommandTests.swift, openspec/changes/docx-form-normalization/proposal.md
  - New: (none)
  - Removed: (none)
