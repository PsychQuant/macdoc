# docx-form-normalization Specification

## Purpose

Form normalization makes a filled Word form uniform after its values are in place: it classifies paragraphs by structural kind and applies string-level edits to the main document part (table field normalization, whole-table field normalization by named grid columns and rows, box glyph font, list-bullet tick, inheriting insert, removal and truncation) without re-serializing any part through the typed model, so raw-channel forms keep every byte outside the edited elements.

## Requirements

### Requirement: Unreadable tables are reported whatever their paragraph ids

When `macdoc word form classify --grid` finds a table whose grid cannot be read, the stderr note naming that table SHALL be written when at least one paragraph that carries a `w14:paraId` has as its nearest container, looking through `w:sdt`, `w:sdtContent` and `w:customXml`, a `w:tc` of that table, whether or not that `w14:paraId` is well-formed. The command SHALL record the table as unreadable before it decides whether to skip a paragraph for a malformed id, because a table's grid does not depend on its paragraph ids and the table number is an integer computed from the document structure. This is a closed description; the note is not written for these two cases: a table whose only such paragraphs lie in a table nested in one of its cells (those paragraphs belong to the nested table), and a table whose only such paragraphs lie in a text box (`w:txbxContent`) in one of its cells (those paragraphs are outside any cell). Paragraphs without a `w14:paraId` are not classified and do not cause a note. Paragraphs with a malformed `w14:paraId` SHALL still be left off stdout and counted on stderr. Without `--grid` the command SHALL write no unreadable-table note.

#### Scenario: Unreadable table whose only paragraph has a malformed id

- **WHEN** `macdoc word form classify --grid` reads a document whose second table uses a legacy `w:hMerge` and whose only paragraph carries a `w14:paraId` that is not eight hexadecimal digits
- **THEN** stderr names the second table as unreadable and counts one skipped id, and neither stdout nor stderr carries that paragraph's text or any control character

##### Example: hMerge table with an escape-sequence paraId

- **GIVEN** a document with one readable table (table 1) and, after it, a table (table 2) whose single cell carries `<w:hMerge w:val="restart"/>` and holds one paragraph with `w14:paraId` set to an ESC character followed by `[31mXX` and the text `偽造`
- **WHEN** `macdoc word form classify --grid` runs on it
- **THEN** the exit code is 0, stderr contains `note: 第 2 張表格的欄列位置無法判讀` and `略過 1 個 w14:paraId`, stdout contains neither `偽造` nor U+001B, and stderr contains no U+001B
