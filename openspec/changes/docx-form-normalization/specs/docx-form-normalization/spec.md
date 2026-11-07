## Purpose

Form normalization makes a filled Word form uniform after its values are in place: it classifies paragraphs by structural kind and applies string-level edits to the main document part (table field normalization, box glyph font, list-bullet tick, inheriting insert, removal and truncation) without re-serializing any part through the typed model, so raw-channel forms keep every byte outside the edited elements.

## ADDED Requirements

### Requirement: Paragraph kinds are assigned by structure from a closed enumeration

The classifier SHALL assign every paragraph exactly one kind from the closed set `list-checkbox`, `checkbox-line`, `table-field`, `body`, taking the first kind whose condition holds in that order. `list-checkbox` SHALL hold when the paragraph's own `w:pPr` contains `w:numPr` and the `w:lvlText` of the referenced level in `word/numbering.xml` contains a box glyph. `checkbox-line` SHALL hold when the paragraph's visible text contains a box glyph. `table-field` SHALL hold when the paragraph's nearest container, looking through `w:sdt`, `w:sdtContent` and `w:customXml` wrappers, is a `w:tc`; a paragraph in a text box belongs to the text box, not to the cell the text box sits in. The box glyphs SHALL be exactly U+25A1, U+25A0, U+2610, U+2611 and U+2612; box symbols drawn from symbol-font private-use code points are not box glyphs. A paragraph's visible text is the content of its own `w:t` elements (not those of paragraphs nested in text boxes), with entities decoded and CDATA sections taken literally. A `w:numId` of `0` means no numbering. The classifier SHALL NOT infer any kind from the wording of a paragraph.

#### Scenario: Paragraph in a table cell with a box glyph

- **WHEN** a paragraph inside a `w:tc` has the visible text `□ 是　□ 否`
- **THEN** its kind is `checkbox-line`, not `table-field`

#### Scenario: Numbered paragraph whose bullet is a box

- **WHEN** a paragraph's own `w:numPr` refers to `w:numId` 3 at `w:ilvl` 0, and numbering 3 maps to an abstract numbering whose level 0 has `w:lvlText w:val="□"`
- **THEN** its kind is `list-checkbox`

#### Scenario: Numbering inside a property change is not the paragraph's own

- **WHEN** a paragraph has no `w:numPr` in its `w:pPr` but has one inside `w:pPrChange`
- **THEN** its kind is not `list-checkbox`

##### Example: kind table

| Paragraph | Kind |
| --- | --- |
| top-level paragraph `申請人資料如下` | `body` |
| paragraph inside a cell, text `王小明` | `table-field` |
| paragraph inside a cell, text `□ 是　□ 否` | `checkbox-line` |
| numbered paragraph whose level text is `□` | `list-checkbox` |
| top-level paragraph `說明：請勿填寫本欄` | `body` |

### Requirement: The classify command lists every addressable paragraph

`macdoc word form classify <in.docx>` SHALL write to stdout one line per paragraph that carries a `w14:paraId` of exactly eight ASCII hexadecimal digits, in document order, formatted as the paragraph id, a tab, the kind, a tab, and the first 30 characters of the visible text with every control character (Unicode general category Cc, including tab, line breaks and ESC), the line and paragraph separators (Zl, Zp) and the bidirectional formatting characters (U+061C, U+200E, U+200F, U+202A–U+202E, U+2066–U+2069) replaced by a space. Paragraphs without a `w14:paraId` SHALL NOT be listed; paragraphs whose `w14:paraId` is any other value SHALL NOT be listed either and SHALL be counted on stderr, so a crafted id cannot put terminal sequences or extra columns on stdout. When `word/numbering.xml` is not well-formed XML (it is first scanned like the main part, which refuses a DOCTYPE, and then judged by an XML parser, not only by tag pairing), the command SHALL still list every paragraph with list-checkbox detection disabled and SHALL name the numbering part on stderr.

#### Scenario: Two addressable paragraphs and one without an id

- **WHEN** the main part holds a body paragraph `1A2B3C4D` with text `申請人`, a cell paragraph `5E6F7A8B` with text `王小明`, and a paragraph without `w14:paraId`
- **THEN** stdout is exactly `1A2B3C4D\tbody\t申請人` followed by `5E6F7A8B\ttable-field\t王小明`, one per line

### Requirement: Table field normalization makes designated fields uniform

For each `--field <paraId>`, `macdoc word form apply` SHALL remove the paragraph's own `w:pStyle` and `w:ind`, set its own `w:jc` to `left`, set `w:sz` and `w:szCs` to the field size on the paragraph mark, on every run of the paragraph, and on the existing `w:sdtPr/w:rPr` of every content control inside the paragraph (a content control whose `w:sdtPr` has no `w:rPr` is left without one), set `w:vAlign` to `center` on the nearest enclosing `w:tc`, and remove every other direct-child paragraph of that cell that is empty, carries no `w:sectPr`, and is not named by any operation of the same command. A paragraph is empty only when its own `w:pPr` carries no `w:numPr` (a `w:numPr` whose `w:numId` is `0` removes numbering and does not count), no `w:pPrChange`, and no `w:ins`, `w:del`, `w:moveFrom`, `w:moveTo` or `w:rPrChange` in its paragraph-mark `w:rPr`, and, apart from that `w:pPr`, its children are `w:proofErr` markers and runs whose children are `w:rPr`, `w:lastRenderedPageBreak` or a `w:t` with no text; this is a closed list, and any other child (bookmarks, comment ranges, tracked changes, hyperlinks, fields, drawings, symbols, tabs, breaks) makes the paragraph non-empty. Sibling paragraphs SHALL NOT be removed when the cell contains a nested `w:tbl`, `w:sdt` or `w:customXml`; when that leaves at least one empty, unnamed sibling paragraph in place, the command SHALL write a note to standard error naming the field's paragraph id and which of those three structures the cell holds, in that order. A designated paragraph whose nearest container (looking through `w:sdt`, `w:sdtContent` and `w:customXml`) is not a `w:tc` SHALL be refused, including a paragraph in a text box that sits in a cell. Inserted elements SHALL follow ECMA-376 child order.

#### Scenario: Field with style, indent and distributed alignment

- **WHEN** a cell paragraph has `w:pStyle w:val="a3"`, `w:ind w:firstLine="480"`, `w:jc w:val="distribute"` and a run with `w:sz w:val="18"`, and it is designated with `--field-size 12`
- **THEN** the paragraph has no `w:pStyle` and no `w:ind`, has `w:jc w:val="left"`, its mark and run carry `w:sz w:val="24"` and `w:szCs w:val="24"`, and its cell's `w:tcPr` contains `w:vAlign w:val="center"`

#### Scenario: Empty sibling paragraph is removed but an image paragraph is kept

- **WHEN** a designated field's cell also holds an empty paragraph, a paragraph containing only a `w:drawing`, and a paragraph holding only a bookmark
- **THEN** the empty paragraph is removed and the drawing and bookmark paragraphs are kept

#### Scenario: Numbered or revised empty siblings are kept

- **WHEN** a designated field's cell also holds an empty paragraph whose `w:pPr` carries `w:numPr` with `w:numId` 3, an empty paragraph whose paragraph mark is a tracked insertion, and an empty paragraph whose `w:numPr` has `w:numId` 0
- **THEN** the first two paragraphs are kept and the third is removed

#### Scenario: Skipped cleanup is reported

- **WHEN** a designated field's cell also holds a paragraph wrapped in `w:sdt` and an empty paragraph
- **THEN** the empty paragraph is kept and standard error names the field's paragraph id and the content control

#### Scenario: Content control in the field takes the field size

- **WHEN** a designated field holds a drop-down content control whose `w:sdtPr/w:rPr` has `w:sz w:val="18"`, and the field size is 12 pt
- **THEN** that `w:rPr` carries `w:sz w:val="24"` and `w:szCs w:val="24"`

#### Scenario: Named sibling is kept

- **WHEN** a designated field's cell also holds an empty paragraph that is the anchor of an `--insert-after`
- **THEN** the empty paragraph is kept and receives the inserted paragraph

#### Scenario: Paragraph outside a table is refused

- **WHEN** `--field` names a top-level body paragraph
- **THEN** the command fails naming that paragraph id and writes no output

### Requirement: The default field size is the most common designated size

When `--field` is given without `--field-size`, the field size SHALL be the most common explicit `w:sz` value collected from the designated paragraphs, where each run with text contributes the value in its own `w:rPr` and a designated paragraph with no run with text contributes its paragraph-mark value. Ties SHALL go to the larger value. The chosen size SHALL be printed to stderr. When no explicit value is collected the command SHALL fail and ask for `--field-size`. `--field-size` SHALL be refused unless `--field` is also given, and SHALL accept, as a whole-string match, digits with at most one fractional part (no sign, exponent or second decimal point), from 1 to 1638 points in steps of 0.5, and be written as half-points.

#### Scenario: Most common size wins

- **WHEN** three designated fields have text runs with `w:sz` 18, 24 and 24 and no `--field-size` is given
- **THEN** all three fields are set to `w:sz w:val="24"` and stderr names 12 pt as the chosen size

##### Example: size resolution

| Collected values | `--field-size` | Result |
| --- | --- | --- |
| 18, 24, 24 | (none) | 24 |
| 18, 24 | (none) | 24 (tie, larger) |
| 22, 22, 18 | 10.5 | 21 |
| (none) | (none) | refused |
| 18 | 10.3 | refused (not a step of 0.5) |
| 18 | 12.5.3 | refused (not a number) |

### Requirement: Box glyphs are drawn in one font

When `--checkbox-font <font>` is given, `macdoc word form apply` SHALL rewrite every run in the main part whose children are an optional `w:rPr` and exactly one `w:t` containing a box glyph, so that each maximal sequence of box glyphs becomes a run whose `w:rFonts` sets `w:ascii`, `w:hAnsi`, `w:eastAsia` and `w:cs` to the font, and the remaining text stays in runs with the original properties, in the original order. A run that would have to be split and carries `w:rPrChange` SHALL be left unchanged and counted on stderr, so a tracked formatting change is neither duplicated nor discarded. Runs containing a box glyph together with any other content child, and runs inside a `w:sdt` whose `w:sdtPr` holds `w14:checkbox` (a native checkbox control redraws its glyph from the fonts of its checked and unchecked states), SHALL be left unchanged and counted on stderr. An empty font name, or one containing characters forbidden by XML 1.0, SHALL be refused.

#### Scenario: Split run with a tracked formatting change

- **WHEN** a run holding `A□B` carries `w:rPrChange w:id="8"` and `--checkbox-font` is given
- **THEN** the run is unchanged, still carries exactly one `w:rPrChange`, and is counted on stderr

#### Scenario: Box after Latin text in one run

- **WHEN** a run with `w:rFonts w:ascii="Times New Roman"` and `w:sz w:val="24"` holds the text `)  □`, and `--checkbox-font 標楷體` is given
- **THEN** the paragraph holds a run with the original properties and text `)  ` followed by a run with text `□` whose `w:rFonts` sets all four attributes to `標楷體` and whose `w:sz` is still `24`

### Requirement: A box that is a list bullet can be ticked

For each `--tick-list <paraId>`, `macdoc word form apply` SHALL remove the paragraph's own `w:numPr` and insert, as the first child after the paragraph's own `w:pPr`, a run holding `■` whose `w:rPr` is copied from the first run with text without `w:rPrChange`, or from the paragraph mark without `w:ins`, `w:del`, `w:moveFrom`, `w:moveTo` and `w:rPrChange` when no run has text. A paragraph without its own `w:numPr`, or whose `w:numId` is `0` (numbering removed), SHALL be refused. The indentation and suffix that the numbering level supplied are not carried over.

#### Scenario: Tick a bulleted option

- **WHEN** a numbered paragraph with text `第一個選項` is named by `--tick-list`
- **THEN** it has no `w:numPr` and its visible text is `■第一個選項`

### Requirement: Inserted paragraphs inherit the anchor's format

For each `--insert-after <paraId>=<text>`, `macdoc word form apply` SHALL insert after the anchor a paragraph whose `w:pPr` is the anchor's own `w:pPr` without `w:numPr`, `w:sectPr`, `w:pPrChange` and `w:pageBreakBefore`, and with `w:ins`, `w:del`, `w:moveFrom`, `w:moveTo` and `w:rPrChange` removed from its paragraph-mark `w:rPr`, holding one run whose `w:rPr` is the anchor's first run with text's `w:rPr` without `w:rPrChange`, and whose text is the given text. Line breaks and tabs in the text are written as text, not as `w:br` or `w:tab`. Options naming the same anchor SHALL be inserted in the order given, each after the previous one. When the anchor's own `w:pPr` carries a `w:sectPr`, that `w:sectPr` SHALL move from the anchor to the last paragraph inserted after it, so the inserted paragraphs stay in the anchor's section instead of starting the next one. Text containing characters forbidden in XML 1.0 SHALL be refused.

#### Scenario: Two paragraphs after one anchor

- **WHEN** `--insert-after 1A2B3C4D=第一段` and `--insert-after 1A2B3C4D=第二段` are given
- **THEN** the anchor is followed by a paragraph with text `第一段` and then a paragraph with text `第二段`, both carrying the anchor's paragraph and run formatting

#### Scenario: Anchor that ends a section

- **WHEN** the anchor's `w:pPr` carries section break S1 and `--insert-after` names it with text `補充`
- **THEN** the anchor no longer carries S1, the inserted paragraph `補充` carries S1, and the document still holds exactly the same section breaks

### Requirement: Paragraphs are removed only when named

For each `--remove <paraId>`, `macdoc word form apply` SHALL remove the paragraph. It SHALL refuse a paragraph that carries a `w:sectPr`, and removals that would leave a `w:tc` or `w:txbxContent` with no paragraph or ending with a block other than a paragraph, where the container's blocks are counted through `w:sdt`/`w:sdtContent` and `w:customXml` wrappers and are judged after every paragraph that `--remove` names in that container is gone. A paragraph that breaks its container alone is named alone; when only the combination breaks it, the message SHALL name every named paragraph in the container for a container left without a paragraph, and the named paragraphs after the last block that stays for a container left ending with another block.

Removal SHALL NOT leave unpaired markup, judged against the deleted set: the union of every paragraph named by `--remove` and the range `--truncate-from` cuts. The deleted set SHALL be judged on the original part before any edit, and again by the deletion step on the part as the earlier steps left it; a refusal at either point aborts the command. The paired range markers are a closed list, each pairing a start and an end of the same kind with the same `w:id`: `w:bookmarkStart`/`w:bookmarkEnd`, `w:commentRangeStart`/`w:commentRangeEnd`, `w:moveFromRangeStart`/`w:moveFromRangeEnd`, `w:moveToRangeStart`/`w:moveToRangeEnd`, `w:permStart`/`w:permEnd`, and the four `w:customXml…RangeStart`/`…RangeEnd` pairs (insert, delete, move-from, move-to). A paired range marker inside a removed paragraph whose partner lies outside the deleted set, or that has no partner in the part, SHALL be kept where the paragraph was, in document order; when no block that stays follows the removed paragraph in its `w:tc` or `w:txbxContent`, the kept markers SHALL go at the end of the nearest paragraph before it that stays instead, so the container still ends with a paragraph whatever order the ids are given in. For every prefix that a kept marker's name and attribute names use, the marker SHALL carry a declaration of the namespace that prefix had at its original position whenever its new position would resolve the prefix to another namespace or to none; a declaration is an `xmlns` or `xmlns:` attribute, never text inside another attribute's value. The command SHALL refuse a deletion that would move a kept marker when a Markup Compatibility attribute is carried by the marker itself, by an ancestor of the marker below the lowest common ancestor of its old parent and its new parent, or by the new parent or one of its ancestors below that common ancestor; a Markup Compatibility attribute is an attribute whose prefix resolves, on its element, to the markup-compatibility namespace, the declared URI read with character references decoded; the message names the paragraph whose range holds the marker. A marker whose partner is also in the deleted set SHALL be removed with it. The command SHALL refuse a deleted set that holds some but not all of the `begin`, `separate` and `end` `w:fldChar` of one complex field (a paragraph wholly inside a field's result holds none of them and may go; naming every paragraph of a field removes it whole), and a deleted set holding a `w:commentReference` whose comment keeps a `w:commentRangeStart` or `w:commentRangeEnd` outside it; the message names the paragraph whose range holds the part that would go.

#### Scenario: Bookmark start kept when its end stays

- **WHEN** the removed paragraph holds `w:bookmarkStart w:id="3"` and the next paragraph holds `w:bookmarkEnd w:id="3"`
- **THEN** the paragraph's content is gone and the `w:bookmarkStart` stays in its place, before the next paragraph

#### Scenario: Removal would split a field

- **WHEN** the removed paragraph holds the `begin` and `separate` `w:fldChar` of a field whose `end` is in the next paragraph
- **THEN** the command fails naming that paragraph id and writes no output

#### Scenario: Removing only the separator paragraph is refused

- **WHEN** a field begins in P1, its `separate` is in P2 and its `end` in P3, and `--remove` names P2
- **THEN** the command fails naming P2 and writes no output

#### Scenario: Every paragraph of a field removed together

- **WHEN** a field begins in P1 and ends in P2, and `--remove` names both P1 and P2
- **THEN** both paragraphs are gone and no `w:fldChar` of that field remains

#### Scenario: Last paragraph of a cell keeps the cell ending with a paragraph

- **WHEN** the last paragraph of a cell holds a `w:bookmarkStart` whose end is after the table, and `--remove` names it
- **THEN** the `w:bookmarkStart` is at the end of the cell's previous paragraph and the cell's last child is a `w:p`

#### Scenario: Last two paragraphs of a cell removed in either order

- **WHEN** a cell holds paragraphs A, R1 and R2, R1 holds a `w:bookmarkStart` and R2 a `w:permStart` whose partners are after the table, and `--remove` names R1 and R2 in either order
- **THEN** both markers are at the end of A in document order and the cell's last child is a `w:p`

#### Scenario: Moved marker keeps the namespace of its prefix

- **WHEN** the root binds `foo` to `urn:a`, the cell's previous paragraph rebinds `foo` to `urn:b`, and the cell's last paragraph, named by `--remove`, holds a `w:bookmarkStart` with a `foo:tag` attribute whose end stays
- **THEN** the `w:bookmarkStart` is at the end of the previous paragraph carrying `xmlns:foo="urn:a"`

#### Scenario: Marker under compatibility rules is not moved

- **WHEN** the removed paragraph carries `mc:Ignorable="foo"` and holds a `w:bookmarkStart` with a `foo:tag` attribute whose end stays
- **THEN** the command fails naming that paragraph id and writes no output

#### Scenario: Compatibility attribute known by its namespace

- **WHEN** the root binds `compat` to the markup-compatibility namespace, and a kept marker in the removed paragraph carries `compat:ProcessContent`
- **THEN** the command fails naming that paragraph id and writes no output

#### Scenario: Field split between a removal and the cut

- **WHEN** a field's `begin` and `separate` are in the paragraph named by `--remove` and its `end` is in the paragraph named by `--truncate-from`
- **THEN** the command succeeds and no `w:fldChar` of that field remains

#### Scenario: Removal would orphan a comment

- **WHEN** the removed paragraph holds the `w:commentReference` of a comment whose range markers are in the previous paragraph
- **THEN** the command fails naming that paragraph id and writes no output

#### Scenario: Cell would end with a nested table

- **WHEN** a cell holds a paragraph, a nested table and a last paragraph, and `--remove` names the last paragraph
- **THEN** the command fails naming that paragraph id and writes no output

#### Scenario: Paragraphs that together empty a cell

- **WHEN** a cell holds paragraphs P1 and P2 and `--remove` names both
- **THEN** the command fails naming P1 and P2 and writes no output

#### Scenario: Paragraphs that together end a cell with a table

- **WHEN** a cell holds P0, P1, a nested table, P2 and P3, and `--remove` names P0, P2 and P3
- **THEN** the command fails naming P2 and P3, not P0, and writes no output

#### Scenario: Only paragraph of a cell inside a content control

- **WHEN** a cell's only paragraph is wrapped in `w:sdt`/`w:sdtContent` and `--remove` names it
- **THEN** the command fails naming that paragraph id and writes no output

#### Scenario: Only paragraph of a cell

- **WHEN** `--remove` names the only paragraph in a `w:tc`
- **THEN** the command fails naming that paragraph id and writes no output

### Requirement: Truncation keeps the section settings of the kept content

For `--truncate-from <paraId>`, the paragraph SHALL be a direct child of `w:body` with at least one content block before it (a block as defined below; range markers alone do not count, so cutting after nothing but a bookmark is refused like cutting at the first child). `macdoc word form apply` SHALL remove everything from that paragraph to the end of the body and SHALL make the first live section properties in the removed range the body's final `w:sectPr`: a `w:sectPr` that is a child of the own `w:pPr` of a paragraph directly under `w:body` or inside a body-level `w:sdt`, or the body's own `w:sectPr`. A `w:sectPr` inside `w:pPrChange` is revision history and SHALL NOT be used. When the last kept block (looking through body-level `w:sdt` and `w:customXml`; every element counts as a block except range markers such as bookmarks, comment ranges and permission ranges, so a `w:altChunk` or a table after the break is the last block) is a paragraph that carries its own `w:sectPr`, the cut removed whole sections: that `w:sectPr` SHALL be moved from the paragraph to the end of the body as its final `w:sectPr` and the removed range's section properties SHALL be dropped, so the result never ends with a section that has no content.

Truncation SHALL NOT leave unpaired markup, using the paired range markers and the deleted set defined under "Paragraphs are removed only when named": a paired marker in the removed range whose partner lies outside the deleted set, or that has no partner in the part, SHALL be kept at the end of the kept content, before the body's final `w:sectPr`, in document order, carrying namespace declarations by the same rule as for `--remove`; a marker whose partner is also in the deleted set SHALL be removed. The field, comment-reference and Markup Compatibility refusals of that requirement apply to the cut in the same way, the body being the kept markers' new parent. When every content block before the cut is a paragraph named by `--remove`, the command SHALL refuse before any edit, naming the `--truncate-from` paragraph.

#### Scenario: Kept bookmark end moves before the final section

- **WHEN** a bookmark starts in a kept paragraph and ends in the paragraph named by `--truncate-from`
- **THEN** the `w:bookmarkEnd` is the last element before the body's final `w:sectPr`

#### Scenario: Removals that leave nothing before the cut

- **WHEN** the body holds P1 and P2, `--remove` names P1 and `--truncate-from` names P2
- **THEN** the command fails naming P2 and writes no output

#### Scenario: Cut would split a field

- **WHEN** a field begins in a kept paragraph and its `end` `w:fldChar` is in the paragraph named by `--truncate-from`
- **THEN** the command fails naming that paragraph id and writes no output

#### Scenario: Cut before a later section break

- **WHEN** the body holds paragraphs P1, P2 (whose `w:pPr` carries section break S1), P3, P4 and the body's own `w:sectPr` S2, and `--truncate-from` names P2
- **THEN** the body holds P1 followed by S1 as the body's final `w:sectPr`

#### Scenario: Cut at the first paragraph of a section

- **WHEN** the body holds paragraphs P1, P2 (whose `w:pPr` carries section break S1), P3, P4 and the body's own `w:sectPr` S2, and `--truncate-from` names P3
- **THEN** the body holds P1, P2 without its `w:sectPr`, and S1 as the body's final `w:sectPr`; S2 is gone and no empty final section remains

#### Scenario: Section properties in revision history are ignored

- **WHEN** the paragraph named by `--truncate-from` keeps an old `w:sectPr` only inside `w:pPrChange`, and the body's own `w:sectPr` is S2
- **THEN** the body's final `w:sectPr` is S2

#### Scenario: Paragraph inside a table is refused

- **WHEN** `--truncate-from` names a paragraph inside a `w:tc`
- **THEN** the command fails naming that paragraph id and writes no output

### Requirement: Apply is all-or-nothing

`macdoc word form apply` SHALL check before editing that every named paragraph id is carried by exactly one `w:p`, SHALL refuse a plan in which a paragraph named by `--remove` is also named by another operation, in which any other named paragraph lies inside the element of a paragraph named by `--remove` (for example a paragraph in a text box), or in which any named paragraph lies in the range `--truncate-from` cuts away (including the cut paragraph itself when another operation names it), and SHALL then run the operations in the order field, tick-list, insert, checkbox-font, remove, truncate. Any failure, including an operation precondition that becomes false after an earlier step, SHALL abort the command with a non-zero exit and a message naming the paragraph id, and the output path SHALL be left as it was. The command SHALL refuse an existing output unless `--force` is given, including a file that appears at the output path while the command runs (the final rename SHALL be exclusive without `--force`; on filesystems that do not support an exclusive rename the command SHALL fall back to an existence check immediately before a plain rename; every existence check SHALL treat a symbolic link as existing even when its target is missing), SHALL parse the edited main part as XML before writing, and SHALL write through a temporary file inside a directory created with mode 0700 next to the output, under a short fixed name, that takes the input file's permission bits and is renamed into place; the directory SHALL be removed on every exit path. With no operation option the command SHALL fail with a usage error.

#### Scenario: One bad id among several

- **WHEN** `--field` names a valid cell paragraph and `--remove` names a paragraph id that does not exist
- **THEN** the command exits non-zero naming the missing id and no output file exists

#### Scenario: Named paragraph nested inside a removed paragraph

- **WHEN** `--insert-after` names a paragraph inside a text box of a paragraph that `--remove` names
- **THEN** the command fails naming the nested paragraph id and writes no output

#### Scenario: Operations that would undo each other

- **WHEN** `--insert-after` names a paragraph that `--remove` also names
- **THEN** the command fails naming that paragraph id and writes no output

#### Scenario: Existing output without force

- **WHEN** the output path already holds a file and `--force` is not given
- **THEN** the command fails and the file's bytes are unchanged

### Requirement: Parts other than the main part are unchanged

`macdoc word form apply` SHALL copy every zip entry other than `word/document.xml` with identical uncompressed content, and SHALL keep the entries in their original order. The archive itself is rewritten (compression and zip metadata are not preserved). A package holding an entry that is neither a file nor a directory SHALL be refused, and a main part containing a DOCTYPE declaration SHALL be refused.

#### Scenario: Styles and numbering survive byte for byte

- **WHEN** a form is processed with `--field` and `--checkbox-font`
- **THEN** `word/styles.xml`, `word/numbering.xml` and every other entry except `word/document.xml` have the same bytes as in the input, in the same order

### Requirement: Reverse names the follow-up for slots that need one

In full-fidelity mode, `macdoc word reverse --slot <name>=<paraId>` SHALL classify each designated paragraph found in the source's main part and, for kinds `table-field`, `checkbox-line` and `list-checkbox`, print one stderr line naming the slot, the kind and the `macdoc word form apply` option that handles it. It SHALL print nothing for `body` slots, in paragraphs-only mode, or for ids not found in the main part. When `word/numbering.xml` is not well-formed XML (judged the same way as `classify` judges it) and at least one slot is designated, it SHALL print one stderr line naming the numbering part, as `classify` does.

#### Scenario: Table field slot

- **WHEN** a slot `applicant` designates a paragraph inside a table cell
- **THEN** stderr carries one line naming `applicant`, `table-field` and `--field`, and the exported script is unchanged
