## Context

swiftify fills official forms by replacing the text of designated paragraphs. When the form's main part rides the raw channel, the raw-channel slot locates a paragraph by `w14:paraId`, keeps its `w:pPr`, and collapses the rest into one run. It never touches the enclosing cell, the font of a box glyph or neighbouring paragraphs, so the template's own unevenness survives into the filled output (PsychQuant/macdoc#249).

Downstream callers repair filled forms with six post-processing scripts. All six edit `word/document.xml` as a string and copy every other zip part unchanged, because a table-dense form usually rides the raw channel and re-serializing it through the typed model can rewrite body text (PsychQuant/ooxml-swift#133). The scripts use plain regular expressions: they pick the wrong `w:tc` when tables nest, treat any `w:numPr` match inside `w:pPrChange` as the paragraph's own, and copy paragraphs with images as if they were empty.

Constraints found while scouting:

- The raw-slot directive parser in ooxml-swift throws on a `// @slot-raw` line with a token count other than two, but silently ignores an unknown `// @` keyword. Putting the kind into the script therefore means changing the existing directive's shape across ooxml-swift, che-word-mcp and macdoc.
- docx-workflow-swift's executor applies every manifest step to an `OOXMLSwift.WordDocument` and writes through `DocxWriter.write`, which re-serializes dirtied parts from the typed model.
- A root-level target already exists in this package (`NotabilityContainerDetection`), with ZIPFoundation as its only dependency.

## Goals / Non-Goals

**Goals:**

- One command that classifies the paragraphs of a form by structural kind, so a caller knows which follow-up each filled paragraph needs.
- One command that applies the follow-ups a filled form needs: uniform table fields (one size, left aligned, vertically centred), box glyphs in one font, a ticked list-bullet box, inserted paragraphs that inherit the anchor's format, removal of instruction paragraphs, and truncation of unrelated trailing forms.
- Every byte outside the edited elements stays as it was; any failure leaves the output path untouched.
- `word reverse --slot` tells the caller which slots will need a follow-up.

**Non-Goals:**

- MCP parity. che-word-mcp's `execute_script` does not gain these operations; tracked in PsychQuant/che-word-mcp#300.
- Making docx-workflow's `insert_paragraph` inherit the anchor's format. It goes through the typed model; that change belongs to ooxml-swift's `OOXMLEdit.insertParagraph` and is tracked in PsychQuant/macdoc#251.
- Detecting instruction ("hint") paragraphs automatically. Removal is always explicit by paragraph id.
- Changing raw-channel slot substitution semantics or the `// @slot-raw` directive grammar.
- Headers, footers, footnotes and other parts. Only `word/document.xml` is edited.
- Resolving list numbering inherited from paragraph styles; only a paragraph's own `w:numPr` counts.
- Telling fill cells from label cells by their content. A whole table is tidied with `--table-defaults`, but only the cells the caller names by grid column and row are fill cells (PsychQuant/macdoc#250; see "Whole-table field normalization is named on the grid"). Removing a whole table in the middle of the body was added in the same issue (`--remove-table`).

## Decisions

### Normalization runs after render as an explicit command

The operations live in `macdoc word form apply`, run on a rendered `.docx`, instead of inside the raw-slot pipeline (option A) or as docx-workflow manifest steps (option B1).

Alternatives: option A keeps CLI and MCP aligned by construction, but needs a directive grammar change in three repositories and an ooxml-swift release first, and removal, truncation and insertion are not text substitutions. Option B1 gives one manifest, but the typed executor would re-serialize the main part of a raw-channel form. The chosen option touches one repository, leaves the script grammar alone, and keeps the byte-equal guarantee of an all-default replay intact, because the script is not changed.

### String-level edits on the main part, never the typed model

Every operation reads `word/document.xml` (and `word/numbering.xml` for classification) as UTF-8 text and splices strings. No operation loads the document through ooxml-swift. Other zip entries are copied with their uncompressed content unchanged and in their original order.

### Tag index scanner instead of regular expressions

`XMLTagIndex` scans the part once into a list of tags (name, kind open/close/self-closing, byte range, attribute region, parent index, matching close index). The scanner is quote-aware (a `>` inside an attribute value does not end a tag) and skips comments, CDATA sections, processing instructions and the XML declaration. Every element query (the paragraph carrying a paraId, the nearest enclosing `w:tc`, a run's own `w:rPr`, a paragraph's own `w:pPr`) is a walk over parent and child links, so nested tables, `w:pPrChange` and `w:rPrChange` resolve to the right element. The index is rebuilt after each splice; parts in real forms are a few hundred kilobytes, so a linear rebuild per operation is acceptable.

### Paragraph kinds are a closed enumeration decided by structure

`FormClassifier` assigns exactly one kind, taking the first that matches in this order:

1. `list-checkbox`: the paragraph's own `w:pPr` has `w:numPr`, and the matching `w:lvl` in `word/numbering.xml` (via `w:num` → `w:abstractNumId` → `w:lvl w:ilvl`) has a `w:lvlText` value containing a box glyph.
2. `checkbox-line`: the paragraph's visible text (all `w:t` content, entity-decoded) contains a box glyph.
3. `table-field`: the paragraph's nearest container, looking through `w:sdt`, `w:sdtContent` and `w:customXml`, is a `w:tc`. A paragraph in a text box anchored in a cell belongs to the text box, so it is not a field of that cell (styling the outer cell would change the wrong cell).
4. `body`: anything else.

The box glyphs are exactly U+25A1 □, U+25A0 ■, U+2610 ☐, U+2611 ☑ and U+2612 ☒. Instruction paragraphs are not a kind: they look like body text, and guessing them from wording would delete content an applicant has to fill.

### Field size defaults to the most common designated size

When `--field` is given without `--field-size`, the size is the most common explicit `w:sz` value among the designated paragraphs: each text-bearing run's own `w:rPr` contributes its value; a designated paragraph with no text-bearing run contributes its paragraph-mark size. Ties go to the larger value. The chosen size is printed to stderr. When no explicit size is found, `apply` refuses and asks for `--field-size`. `--field-size` takes points in steps of 0.5 between 1 and 1638 and is written as half-points.

### Whole-table field normalization is named on the grid

`--table-defaults <paraId>=col:…/row:…` tidies every fill cell of one table as `--field` tidies one paragraph (PsychQuant/macdoc#250). The maintainer decided that label cells stay untouched (2026-11-04) and that the caller names the fill cells by column or row number (2026-11-08); comparing against a blank template and dropping the whole-table pass were the other candidates. Five choices follow from that:

- Columns are grid columns (`w:gridBefore`, `w:gridSpan`), not the n-th `w:tc` of a row, because the number of cells per row changes with merged cells. `classify --grid` prints each cell's position, since Word does not show grid column numbers and an irregular form has more grid columns than visible columns.
- A cell is a fill cell only when it lies wholly inside the selection. A cell only partly inside (a title row across the table, an address across a label column) is left alone and listed on stderr; refusing instead would make column selection unusable on most forms, which have a full-width row somewhere.
- Several selections on one table take the union, so a form with a regular part and an irregular part can be named in two pieces. Each selection must still find a fill cell of its own, which catches a mistyped number.
- A grid that cannot be read (bad numbers, the legacy `w:hMerge`, a continuation cell with nothing above it) is refused rather than guessed; `--field` stays available for such tables.
- A fill cell's field paragraphs are its non-empty paragraphs, or its first paragraph when all are empty, so the existing cleanup still removes its empty paragraphs; a paragraph with content must carry a `w14:paraId`, because every later step finds paragraphs by id. An empty cell that cannot be named, or a cell with no paragraph, holds nothing to tidy and is left alone and listed (verify round 1), as long as the selection tidies at least one cell.

### The library lives in ooxml-swift; the command and its flags stay in macdoc

The `DocxForm` library moved from this repo's root-level target into ooxml-swift as a library product (PsychQuant/ooxml-swift#238, released in 3.21.0), so che-word-mcp can use the same normalization; macdoc depends on that product (PsychQuant/macdoc#274). This change still specifies the `macdoc word form` command, so the spec stays here. The mapping from paragraph kinds to `word form apply` flags (`ApplyOption`, `ParagraphKind.applyOption`) stays in the CLI: flags are how macdoc is reached, not part of the format (`.claude/rules/format-library-vs-access-surface.md`). References below to `Sources/DocxForm` and `DocxFormTests` describe where the code was when each task was done; the files and the 241 library tests are now in ooxml-swift.

### All paragraph ids are validated before any edit, operations run in a fixed order

`apply` builds a `FormPlan` from the options, then checks every paragraph id against the original part (exactly one `w:p` carries it; operation-specific preconditions hold) before editing. Operations then run in this order: field, tick-list, insert, checkbox-font, remove, truncate. Fields come first so the default size is computed from the template; boxes are re-fonted after the tick and insert steps add text; removal and truncation run last so no earlier step loses its target. A precondition that only becomes false after an earlier step (for example removing the only paragraph left in a cell after field normalization dropped its siblings) is checked again when the step runs, and any failure aborts the whole command.

### Output handling mirrors word render

`apply` refuses an existing output unless `--force`, writes the new archive to `out.docx` inside a staging directory created with mode 0700 next to the output (`.macdoc-form-<UUID>`), and renames it into place, and parses the edited main part with Foundation's `XMLParser` before writing. Without `--force` the rename is exclusive (`renamex_np` with `RENAME_EXCL`), so a file that appears at the output path during the run is never replaced. Filesystems without exclusive rename (exFAT, FAT, some network volumes) return `ENOTSUP` or `EINVAL`; there the command falls back to an existence check immediately followed by a plain rename, which narrows but cannot close the race. Every existence check uses `lstat`, so a symbolic link whose target is missing still counts as an existing output. The temporary file takes the input file's permission bits before the rename; because it lives in the 0700 directory, its content is never readable by other users while it is written, and the short fixed name keeps a long output name within the file-name limit. The staging directory is removed on every exit path that runs Swift code; a process killed outright (SIGKILL, power loss) leaves the hidden 0700 directory with the rewritten package, which the user can delete. With `--force`, a symbolic link at the output is replaced by the new file and its target is left as it was (rename semantics). Any error leaves the output path as it was and exits non-zero with a Traditional Chinese message naming the paragraph id and the reason.

Alternatives: always using a plain rename after an existence check (round-1 defect: a concurrent writer is overwritten); refusing to write on filesystems without exclusive rename (round-2 regression: writing to a USB drive failed without `--force`); a temporary file named after the output next to it (run-2 round-1 defect: readable by others until its permissions were set, and too long for output names near the limit).

### Reverse reports kinds only when a follow-up exists

`word reverse --slot`, in full-fidelity mode, classifies each designated paragraph id found in the source's main part. For `table-field`, `checkbox-line` and `list-checkbox` it prints one stderr line naming the slot, the kind and the matching `word form apply` option. `body` slots, paragraphs-only mode and ids not found in the main part print nothing, following the silence-on-success convention. The one exception: when `word/numbering.xml` is not well-formed and at least one slot is designated, one line names the numbering part, because a list-checkbox slot would otherwise lose its note without a trace.

## Implementation Contract

**Commands.**

- `macdoc word form classify <in.docx>` writes one line per paragraph whose `w14:paraId` is exactly eight ASCII hexadecimal digits, in document order, to stdout: `<paraId>\t<kind>\t<preview>`, where preview is the first 30 characters of the visible text with every control character (Unicode category Cc: tab, line breaks, ESC, the rest of C0 and C1), the line and paragraph separators and the bidirectional formatting characters replaced by a space, so document text cannot drive or reorder the terminal. Paragraphs with any other `w14:paraId` value (a damaged or crafted file; character references are decoded, so an id could carry ESC or a tab) are counted on stderr instead of printed. Visible text is the content of the paragraph's own `w:t` elements, entity-decoded, with CDATA taken literally. When `word/numbering.xml` is not well-formed (it is first scanned by the tag index, which refuses a DOCTYPE, and then checked with `XMLParser` before the level index is built, so duplicate attributes and bad references count, not only unbalanced tags), classification still runs with list-checkbox detection off, and stderr names the numbering part. Exit 0. A missing input fails with `找不到輸入檔案: <path>`.
- `macdoc word form apply <in.docx> --to-docx <out.docx> [--force]` with:
  - `--field <paraId>` (repeatable): remove the paragraph's own `w:pStyle` and `w:ind`, set `w:jc w:val="left"`, set `w:sz` and `w:szCs` on the paragraph mark and on every run of the paragraph, set `w:vAlign w:val="center"` on the enclosing cell, and remove the cell's other direct-child paragraphs that are empty, carry no `w:sectPr`, and are not named by any operation. Empty is a closed list: apart from its own `w:pPr`, the paragraph holds only `w:proofErr` and runs whose children are `w:rPr`, `w:lastRenderedPageBreak` or a `w:t` with no text. The cleanup is skipped when the cell contains a nested table or a block wrapper (`w:sdt`, `w:customXml`). Refused when the paragraph's nearest container is not a `w:tc` (a paragraph in a text box in a cell is refused). Inserted `w:sz`/`w:szCs` and `w:rFonts` go before extension elements (`w14:` and other non-`w:` children), which ECMA-376 places after every schema element.
  - `--field-size <pt>`: whole-string match of digits with at most one fractional part, 1 to 1638 in steps of 0.5; requires `--field`. See the field size decision for the default.
  - `--checkbox-font <font>`: in every run whose children are an optional `w:rPr` and exactly one `w:t`, each maximal sequence of box glyphs becomes its own run with `w:rFonts` set to the font for `w:ascii`, `w:hAnsi`, `w:eastAsia` and `w:cs`; the surrounding text keeps a run with the original properties. A run that would have to be split and carries `w:rPrChange` is left alone and counted, so a tracked formatting change is neither duplicated nor discarded; a run with a box glyph and any other content child is treated the same way, and so is a run inside a native checkbox content control (`w:sdt` whose `w:sdtPr` holds `w14:checkbox`), because Word redraws that glyph from the fonts of `w14:checkedState`/`w14:uncheckedState` when it is toggled. An empty font name, or one with characters forbidden by XML 1.0, is refused.
  - `--tick-list <paraId>` (repeatable): remove the paragraph's own `w:numPr` and insert a run holding ■ as the first child after the paragraph's own `w:pPr`, with the `w:rPr` of the first run that has text without `w:rPrChange` (or of the paragraph mark, without `w:ins`, `w:del`, `w:moveFrom`, `w:moveTo` and `w:rPrChange`, when no run has text). Refused when the paragraph has no own `w:numPr` or its `w:numId` is `0`. The numbering level's indentation and suffix are not carried over.
  - `--insert-after <paraId>=<text>` (repeatable): insert a paragraph after the anchor holding one run with the text. The new paragraph's `w:pPr` is the anchor's own `w:pPr` without `w:numPr`, `w:sectPr`, `w:pPrChange` and `w:pageBreakBefore`, with revision marks removed from its paragraph-mark `w:rPr`; the run's `w:rPr` is the anchor's first text-bearing run's `w:rPr` without `w:rPrChange`. Repeated options with the same anchor are inserted in the order given. When the anchor carries its own `w:sectPr` (it ends a section), that `w:sectPr` moves to the last inserted paragraph, so the inserted text stays in the anchor's section; otherwise the new text would open the next section, and with `--truncate-from` after it the kept-break rule would not fire. Text containing characters forbidden in XML 1.0 is refused; line breaks and tabs are written as text.
  - `--remove <paraId>` (repeatable): remove the paragraph. Refused when it carries a `w:sectPr`, or when, counting the blocks of its enclosing `w:tc` or `w:txbxContent` through `w:sdt`/`w:customXml` wrappers, the cell or text box would be left with no paragraph or ending with a block other than a paragraph.
  - `--truncate-from <paraId>`: the paragraph must be a direct child of `w:body` with at least one content block before it (range markers alone do not count). Everything from it to the end of the body is removed, and the first live section properties in the removed range become the body's final `w:sectPr`: the `w:sectPr` of a body-level paragraph's own `w:pPr` (including paragraphs inside body-level `w:sdt`), or the body's own `w:sectPr`. A `w:sectPr` inside `w:pPrChange` is revision history and is never used. When the last kept block (looking through body-level `w:sdt` and `w:customXml`; every element counts as a block except the closed list of range markers and wrapper property elements, so `w:altChunk`, math or an element not foreseen here stops the move) is a paragraph carrying its own `w:sectPr`, the cut removed whole sections: that `w:sectPr` moves from the paragraph to the end of the body and the removed range's one is dropped. Keeping both would end the body with an empty section, which renders as an extra blank page (run-2 round-1 finding, reproduced in LibreOffice: two pages instead of one).
- `apply` with no operation option fails with a usage error.

**Plan validation.** Every named id must be carried by exactly one `w:p`. A plan is refused when a paragraph named by `--remove` is also named by another operation, when a named paragraph lies inside the element of a paragraph that `--remove` deletes (for example a paragraph in a text box), or when a named paragraph lies in the range `--truncate-from` cuts away (including the cut paragraph itself when another operation names it).

**Failure modes.** Missing input; output exists without `--force` (also when it appears during the run); a paragraph id carried by zero or several `w:p` elements; a per-operation precondition failure, including one that only becomes false after an earlier step; conflicting operations; text or font forbidden by XML 1.0; a main part with a DOCTYPE declaration; a package entry that is neither a file nor a directory; an edited part that does not parse. Each fails with a non-zero exit, a Traditional Chinese message naming the id or part and the reason, and no change at the output path.

**Acceptance criteria.**

- Unit tests in `DocxFormTests` cover the tag index (quote-aware tags, comments, CDATA, DOCTYPE refusal, nested tables), each kind of the classifier, each operation's positive case and refusals, the default field size including the 18/24/24 example, the fixed order, the conflict checks (same id and nested element range), the cell guards through `w:sdt`, the dropped `w:rPrChange`, the rename fallback (`ENOTSUP` and `EINVAL`, including a dangling symbolic link at the output), the private staging directory, the kept-break truncation, text-box paragraphs in cells, native checkbox controls and extension-element order.
- A package test round-trips a generated `.docx`, edits it, and asserts every entry other than `word/document.xml` has identical uncompressed bytes and order, that the output keeps the input's permission bits, and that a file created during the run is not replaced without `--force`.
- CLI tests in `MacDocCLITests` run `word form classify` and `word form apply` on generated fixtures, assert the refusal of an existing output and that a failed run leaves the output path absent, and assert the `word reverse --slot` note.
- `cli-spec.yaml` is regenerated and the CLI spec contract tests pass.

**Scope.** In scope: the `DocxForm` target, the two commands, the reverse note, tests, the generated CLI specification, and the swiftify and macdoc skill documentation. Out of scope: everything listed under Non-Goals.

## Risks / Trade-offs

- [String splicing can produce invalid OOXML child order] → insertions use explicit follower lists from ECMA-376 (`w:pPr`, `w:rPr`, `w:tcPr`), and tests assert the position of each inserted element.
- [Removing a paragraph that looks empty can remove content] → emptiness is a closed whitelist (empty runs and `w:proofErr` only); bookmarks, comment ranges, tracked changes, fields, drawings and symbols count as content.
- [Structural rules beyond well-formedness] → the final `XMLParser` check proves well-formedness only. The cell-ending guard, the conflict checks and the live-sectPr rule cover the structural cases found in review; body-level structure after deletion is checked since PsychQuant/macdoc#250: two tables a non-table block separated must not become adjacent, the body keeps content and gets an empty final paragraph instead of ending with a table, and without a cut the last section keeps content. Empty-paragraph cleanup skipped silently for inline content controls, numbered or revised empty paragraphs, and range markers cut by truncation are tracked in PsychQuant/macdoc#253; id lookup cost and the entry-count limit in PsychQuant/macdoc#252.
- [The default field size can surprise a caller] → the chosen size is printed, and `--field-size` overrides it (default confirmed by the maintainer on 2026-11-04).
- [Exclusive rename is unavailable on some filesystems] → falls back to an existence check plus a plain rename; the race window remains there.
- [Two steps (render, then apply) instead of one] → the swiftify skill documents the order and the kind → option table.
- [MCP callers do not get the operations] → recorded as a non-goal; PsychQuant/che-word-mcp#300.
- [Grid column numbers are not what a person counts in Word] → `classify --grid` prints them, and a cell only partly inside a selection is left alone and listed rather than tidied (PsychQuant/macdoc#250).
- [An empty fill cell that cannot be named is left untidied while the command succeeds] → its first paragraph has no `w14:paraId`, so it cannot be addressed; it is listed on stderr, and a selection that tidies nothing is refused. Word gives every paragraph an id when it saves, so this only reaches paragraphs written by other tools, or added by them after the last Word save; a caller that must have every cell tidied reads stderr, or saves the form in Word first (verify round 2).
- [One field size for every field of a run] → `--table-defaults` fields share the size with `--field` fields, as the existing rule takes one size for all designated paragraphs; two tables with different conventions are tidied in two runs or with `--field-size`.
