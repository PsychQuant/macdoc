## Problem

The requirement "Unreadable tables are reported whatever their paragraph ids", added by `idd-277-classify-grid-unreadable-table`, says the unreadable-table note is written "for every table with at least one paragraph that carries a `w14:paraId`". That is wider than what `macdoc word form classify --grid` does: an outer table that holds paragraphs only through a nested table, or only inside a text box in one of its cells, is not reported, because classify places a paragraph only in the table whose `w:tc` is the paragraph's nearest container. The #277 verify (round 1) produced both counter-examples.

## Root Cause

The requirement used a general criterion with a single exception instead of naming the paragraphs that place a table, so its literal scope covered two cases the code never handled.

## Proposed Solution

Rewrite the requirement as a closed description: a table is reported through the paragraphs whose nearest container, looking through `w:sdt`, `w:sdtContent` and `w:customXml`, is a `w:tc` of that table, and the requirement names the two cases it does not cover. The Example's expected result also states that stderr carries no U+001B, matching the test. No code changes.

## Non-Goals

- Reporting outer tables reached only through nested tables or text boxes; that would be a behaviour change outside #277.
- Changing the wording of the note (tracked in PsychQuant/macdoc#283).

## Success Criteria

- The requirement states only what classify does, with the two excluded cases named.
- `spectra validate`, the spec link check and `WordFormCommandTests` pass.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `docx-form-normalization`: narrows the requirement "Unreadable tables are reported whatever their paragraph ids" to a closed description.

## Impact

- Affected specs: `docx-form-normalization`
- Affected code: (none)
