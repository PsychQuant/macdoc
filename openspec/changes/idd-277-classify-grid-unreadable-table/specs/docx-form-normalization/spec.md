## Purpose

Form normalization makes a filled Word form uniform after its values are in place: it classifies paragraphs by structural kind and applies string-level edits to the main document part (table field normalization, whole-table field normalization by named grid columns and rows, box glyph font, list-bullet tick, inheriting insert, removal and truncation) without re-serializing any part through the typed model, so raw-channel forms keep every byte outside the edited elements.

## ADDED Requirements

### Requirement: Unreadable tables are reported whatever their paragraph ids

When `macdoc word form classify --grid` finds a table whose grid cannot be read, the stderr note naming that table SHALL be written whether or not any paragraph of the table carries a well-formed `w14:paraId`. The command SHALL record the table as unreadable before it decides whether to skip a paragraph for a malformed id, because a table's grid does not depend on its paragraph ids and the table number is an integer computed from the document structure. Paragraphs with a malformed `w14:paraId` SHALL still be left off stdout and counted on stderr. Without `--grid` the command SHALL write no unreadable-table note.

#### Scenario: Unreadable table whose only paragraph has a malformed id

- **WHEN** `macdoc word form classify --grid` reads a document whose second table uses a legacy `w:hMerge` and whose only paragraph carries a `w14:paraId` that is not eight hexadecimal digits
- **THEN** stderr names the second table as unreadable and counts one skipped id, and stdout lists neither that paragraph's text nor any control character

##### Example: hMerge table with an escape-sequence paraId

- **GIVEN** a document with one readable table (table 1) and, after it, a table (table 2) whose single cell carries `<w:hMerge w:val="restart"/>` and holds one paragraph with `w14:paraId` set to an ESC character followed by `[31mXX` and the text `偽造`
- **WHEN** `macdoc word form classify --grid` runs on it
- **THEN** the exit code is 0, stderr contains `note: 第 2 張表格的欄列位置無法判讀` and `略過 1 個 w14:paraId`, and stdout contains neither `偽造` nor U+001B
