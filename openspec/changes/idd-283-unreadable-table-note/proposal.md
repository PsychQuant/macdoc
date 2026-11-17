## Problem

Since the unreadable-table note was extended to tables whose paragraph ids are all skipped, `macdoc word form classify --grid` writes the same note for every such table: "第 N 張表格的欄列位置無法判讀，座標印 tN:?；apply --table-defaults 會說明原因". When every paragraph in the table that carries a `w14:paraId` was skipped for a malformed id, stdout has no line with `tN:?` and there is no paragraph id to give to `apply --table-defaults`, so the second half of the note points the reader at coordinates and a next step that do not exist.

A related test cannot fail: `testClassifySkipsParaIdsThatAreNotEightHexDigits` uses the character reference `&#x1B;` as the malformed paragraph id, but the DocxForm text decoder keeps a reference to a control character as written, so the input contains no U+001B and the assertion that stdout carries no U+001B passes whether or not the id check exists. Its comment, which says the ESC comes from a character reference, is wrong for the same reason.

## Root Cause

The command records unreadable tables before the paragraph id check, which is correct, but it does not record which of those tables had at least one paragraph printed, so it cannot tell the two cases apart when it writes the note. The test was written before the decoder's handling of control-character references was known.

## Proposed Solution

While printing paragraphs, the command also records the number of every unreadable table that had a line printed with `tN:?`. The note keeps its first half, "note: 第 N 張表格的欄列位置無法判讀", in both cases. Its second half is the current text, "，座標印 tN:?；apply --table-defaults 會說明原因", when the table has a printed line, and "；這張表格帶 w14:paraId 的段落全部被略過，沒有 paraId 可以交給 apply --table-defaults" when it has none. The skipped-id count, the stdout lines and the conditions for writing a note stay as they are.

The test uses a raw U+001B in the paragraph id, as the newer unreadable-table test already does, and also asserts that stderr carries no U+001B.

## Non-Goals

- No change to when the note is written, to which paragraphs are listed on stdout, or to the skipped-id count.
- No change to che-word-mcp's `classify_form`: it reports unreadable tables as a structured list of table numbers and makes no claim about printed coordinates.
- The wording problems in the requirement's Scenario and its closed description (tracked separately in macdoc#284) are left as they are; this change copies them unchanged.

## Success Criteria

- On a document whose unreadable second table holds one paragraph with a malformed `w14:paraId`, stderr contains `note: 第 2 張表格的欄列位置無法判讀` and `略過 1 個 w14:paraId` and does not contain `座標印 t2:?`.
- On a document whose unreadable second table holds one paragraph with the id `0000E101`, stdout contains the line for `0000E101` with `t2:?` and stderr contains `座標印 t2:?`.
- `testClassifySkipsParaIdsThatAreNotEightHexDigits` fails when the paragraph id check is removed.
- Every existing `WordFormCommandTests` case still passes.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `docx-form-normalization`: the requirement "Unreadable tables are reported whatever their paragraph ids" states the two forms of the note's second half and gains an Example for a table with a printed line.

## Impact

- Affected specs: `docx-form-normalization`
- Affected code:
  - Modified: Sources/MacDocCLI/MacDoc+Word+Form.swift
  - Modified: Tests/MacDocCLITests/WordFormCommandTests.swift
