# docx-form-normalization Specification

## Purpose

Form normalization makes a filled Word form uniform after its values are in place: it classifies paragraphs by structural kind and applies string-level edits to the main document part (table field normalization, whole-table field normalization by named grid columns and rows, box glyph font, list-bullet tick, inheriting insert, removal and truncation) without re-serializing any part through the typed model, so raw-channel forms keep every byte outside the edited elements.

## Requirements

### Requirement: Unreadable tables are reported whatever their paragraph ids

When `macdoc word form classify --grid` finds a table whose grid cannot be read, the stderr note naming that table SHALL be written when, and only when, at least one paragraph that carries a `w14:paraId` has as its nearest container a `w:tc` of that table, whether or not that `w14:paraId` is well-formed. The nearest container SHALL be found by looking through `w:sdt`, `w:sdtContent` and `w:customXml` and no other element. A paragraph whose nearest container is any other element does not cause a note for the table; for example, a paragraph in a table nested in one of the table's cells belongs to the nested table, and a paragraph in a text box (`w:txbxContent`) or in a block-level `mc:AlternateContent` in one of its cells lies outside any cell. The command SHALL record the table as unreadable before it decides whether to skip a paragraph for a malformed id, because a table's grid does not depend on its paragraph ids and the table number is an integer computed from the document structure. Paragraphs without a `w14:paraId` are not classified and do not cause a note. Paragraphs with a malformed `w14:paraId` SHALL still be left off stdout and counted on stderr. Without `--grid` the command SHALL write no unreadable-table note.

The note SHALL begin with `note: 第 N 張表格的欄列位置無法判讀`, where N is the table number. When at least one paragraph of that table is printed on stdout with the position `tN:?`, the note SHALL continue with `，座標印 tN:?；apply --table-defaults 會說明原因`. When no paragraph of that table is printed with the position `tN:?` (every such paragraph was skipped for a malformed id), no stdout line carries `tN:?` and no paragraph id of that table can be given to `apply --table-defaults`, so the note SHALL instead continue with `；這張表格帶 w14:paraId 的段落全部被略過，沒有 paraId 可以交給 apply --table-defaults`.

#### Scenario: Unreadable table whose only paragraph has a malformed id

- **WHEN** `macdoc word form classify --grid` reads a document whose second table uses a legacy `w:hMerge` and whose only paragraph carries a `w14:paraId` that is not eight hexadecimal digits
- **THEN** stderr names the second table as unreadable, says that the table's paragraphs carrying a `w14:paraId` were all skipped instead of pointing to `t2:?`, and counts one skipped id, and neither stdout nor stderr carries that paragraph's text or any control character taken from that paragraph's `w14:paraId` or text

##### Example: hMerge table with an escape-sequence paraId

- **GIVEN** a document with one readable table (table 1) and, after it, a table (table 2) whose single cell carries `<w:hMerge w:val="restart"/>` and holds one paragraph with `w14:paraId` set to an ESC character followed by `[31mXX` and the text `偽造`
- **WHEN** `macdoc word form classify --grid` runs on it
- **THEN** the exit code is 0, stderr contains `note: 第 2 張表格的欄列位置無法判讀；這張表格帶 w14:paraId 的段落全部被略過` and `略過 1 個 w14:paraId` and does not contain `座標印 t2:?`, and neither stdout nor stderr contains `偽造` or U+001B

#### Scenario: Unreadable table with a printed paragraph

- **WHEN** `macdoc word form classify --grid` reads a document whose second table uses a legacy `w:hMerge` and whose only paragraph carries a well-formed `w14:paraId`
- **THEN** stdout lists that paragraph with the position `t2:?`, and stderr names the second table as unreadable and points to `t2:?` and `apply --table-defaults`

##### Example: hMerge table with a well-formed paraId

- **GIVEN** a document with one readable table (table 1) and, after it, a table (table 2) whose single cell carries `<w:hMerge w:val="restart"/>` and holds one paragraph with `w14:paraId` `0000E101` and the text `舊式合併`
- **WHEN** `macdoc word form classify --grid` runs on it
- **THEN** the exit code is 0, stdout contains the line made of `0000E101`, `table-field`, `t2:?` and `舊式合併` separated by tabs, and stderr contains `note: 第 2 張表格的欄列位置無法判讀，座標印 t2:?；apply --table-defaults 會說明原因`
