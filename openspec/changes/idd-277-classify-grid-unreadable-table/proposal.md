## Problem

`macdoc word form classify --grid` writes a stderr note for every table whose grid it cannot read ("第 N 張表格的欄列位置無法判讀"). A table whose paragraphs all carry a `w14:paraId` that is not eight hexadecimal digits never gets that note: stderr only says how many ids were skipped, so the reader believes every table's positions are usable and only finds out when `apply --table-defaults` refuses the table.

## Root Cause

The classify command handles each paragraph in two steps: it first skips a paragraph whose `w14:paraId` is malformed, and only afterwards records the paragraph's table as unreadable. A paragraph that is skipped never reaches the recording step, so a table made only of such paragraphs is never recorded. Whether a table's grid can be read does not depend on its paragraph ids, and the table number is an integer computed from the document structure, so printing it carries none of the injection risk that the id check guards against.

## Proposed Solution

Record the unreadable table before the paragraph id check, only when `--grid` is given, so the note lists every table whose grid cannot be read. The id check, the skipped-id count and the stdout lines stay as they are. This is the order che-word-mcp's `classify_form` already uses (PsychQuant/che-word-mcp#300).

## Non-Goals

- No change to which paragraphs are listed on stdout or to the skipped-id count.
- No change to the wording of either stderr note.
- No change to the DocxForm library in ooxml-swift: its classification output is correct; only the CLI's use of it is out of order.
- A table that holds no paragraph with any `w14:paraId` at all is not listed by classify today and stays unlisted; that is outside this issue.

## Success Criteria

- `macdoc word form classify --grid` on a document with an unreadable table whose only paragraph has a malformed `w14:paraId` writes both the unreadable-table note naming that table and the skipped-id note, and stdout contains neither the paragraph's text nor any control character.
- Every existing `WordFormCommandTests` case still passes.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `docx-form-normalization`: adds one requirement stating that the unreadable-table note covers every table whose grid cannot be read, whatever its paragraph ids. ASSUMPTION: the capability's classify requirement still lives only in the open change `docx-form-normalization` and is not in the main specs, so this change adds a separate requirement instead of modifying that one.

## Impact

- Affected specs: `docx-form-normalization`
- Affected code:
  - Modified: Sources/MacDocCLI/MacDoc+Word+Form.swift
  - Modified: Tests/MacDocCLITests/WordFormCommandTests.swift
