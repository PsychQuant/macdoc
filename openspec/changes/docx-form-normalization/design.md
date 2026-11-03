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

- MCP parity. che-word-mcp's `execute_script` does not gain these operations; a follow-up can wrap the same library when needed.
- Making docx-workflow's `insert_paragraph` inherit the anchor's format. It goes through the typed model; that change belongs to ooxml-swift's `OOXMLEdit.insertParagraph` and is tracked as a follow-up issue.
- Detecting instruction ("hint") paragraphs automatically. Removal is always explicit by paragraph id.
- Changing raw-channel slot substitution semantics or the `// @slot-raw` directive grammar.
- Headers, footers, footnotes and other parts. Only `word/document.xml` is edited.
- Resolving list numbering inherited from paragraph styles; only a paragraph's own `w:numPr` counts.

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
3. `table-field`: the paragraph has an enclosing `w:tc`.
4. `body`: anything else.

The box glyphs are exactly U+25A1 □, U+25A0 ■, U+2610 ☐, U+2611 ☑ and U+2612 ☒. Instruction paragraphs are not a kind: they look like body text, and guessing them from wording would delete content an applicant has to fill.

### Field size defaults to the most common designated size

When `--field` is given without `--field-size`, the size is the most common explicit `w:sz` value among the designated paragraphs: each text-bearing run's own `w:rPr` contributes its value; a designated paragraph with no text-bearing run contributes its paragraph-mark size. Ties go to the larger value. The chosen size is printed to stderr. When no explicit size is found, `apply` refuses and asks for `--field-size`. `--field-size` takes points in steps of 0.5 between 1 and 1638 and is written as half-points.

### All paragraph ids are validated before any edit, operations run in a fixed order

`apply` builds a `FormPlan` from the options, then checks every paragraph id against the original part (exactly one `w:p` carries it; operation-specific preconditions hold) before editing. Operations then run in this order: field, tick-list, insert, checkbox-font, remove, truncate. Fields come first so the default size is computed from the template; boxes are re-fonted after the tick and insert steps add text; removal and truncation run last so no earlier step loses its target. A precondition that only becomes false after an earlier step (for example removing the only paragraph left in a cell after field normalization dropped its siblings) is checked again when the step runs, and any failure aborts the whole command.

### Output handling mirrors word render

`apply` refuses an existing output unless `--force`, writes the new archive to a temporary file in the output's directory and renames it into place, and parses the edited main part with Foundation's `XMLParser` before writing. Any error leaves the output path as it was and exits non-zero with a Traditional Chinese message naming the paragraph id and the reason.

### Reverse reports kinds only when a follow-up exists

`word reverse --slot`, in full-fidelity mode, classifies each designated paragraph id found in the source's main part. For `table-field`, `checkbox-line` and `list-checkbox` it prints one stderr line naming the slot, the kind and the matching `word form apply` option. `body` slots, paragraphs-only mode and ids not found in the main part print nothing, following the silence-on-success convention.

## Implementation Contract

**Commands.**

- `macdoc word form classify <in.docx>` writes one line per paragraph that carries `w14:paraId`, in document order, to stdout: `<paraId>\t<kind>\t<preview>`, where preview is the first 30 characters of the visible text with tabs and newlines replaced by spaces. Exit 0. A missing input fails with `找不到輸入檔案: <path>`.
- `macdoc word form apply <in.docx> --to-docx <out.docx> [--force]` with:
  - `--field <paraId>` (repeatable): remove the paragraph's own `w:pStyle` and `w:ind`, set `w:jc w:val="left"`, set `w:sz` and `w:szCs` on the paragraph mark and on every run in the paragraph, set `w:vAlign w:val="center"` on the enclosing cell, and remove the cell's other direct-child paragraphs that have no content and no `w:sectPr`, unless the cell contains a nested table. No content means no `w:t` with text and no `w:drawing`, `w:pict`, `w:object`, `w:sym`, `w:tab`, `w:br`, `w:fldChar`, `w:fldSimple`, `w:instrText`, footnote, endnote or comment reference, `m:oMath` or `m:oMathPara`. Refused when the paragraph is not inside a `w:tc`.
  - `--field-size <pt>`: see the field size decision.
  - `--checkbox-font <font>`: in every run whose children are an optional `w:rPr` and exactly one `w:t`, each maximal sequence of box glyphs becomes its own run with `w:rFonts` set to the font for `w:ascii`, `w:hAnsi`, `w:eastAsia` and `w:cs`; the surrounding text keeps a run with the original properties. A run with a box glyph and any other content child is left alone; the number of such runs is printed to stderr.
  - `--tick-list <paraId>` (repeatable): remove the paragraph's own `w:numPr` and insert a run holding ■ before the paragraph's first run, with the `w:rPr` of the first run that has text (or of the paragraph mark, without `w:ins`, `w:del`, `w:moveFrom`, `w:moveTo` and `w:rPrChange`, when no run has text). Refused when the paragraph has no own `w:numPr`.
  - `--insert-after <paraId>=<text>` (repeatable): insert a paragraph after the anchor holding one run with the text. The new paragraph's `w:pPr` is the anchor's own `w:pPr` without `w:numPr`, `w:sectPr` and `w:pPrChange`; the run's `w:rPr` is the anchor's first text-bearing run's `w:rPr`. Repeated options with the same anchor are inserted in the order given. Text containing characters forbidden in XML 1.0 is refused.
  - `--remove <paraId>` (repeatable): remove the paragraph. Refused when it is the only paragraph of its cell or carries a `w:sectPr`.
  - `--truncate-from <paraId>`: the paragraph must be a direct child of `w:body` and not its first child. Everything from it to the end of the body is removed, and the first `w:sectPr` found in the removed range (a paragraph-level break, otherwise the body's own) becomes the body's final `w:sectPr`.
- `apply` with no operation option fails with a usage error.

**Failure modes.** Missing input; output exists without `--force`; a paragraph id carried by zero or several `w:p` elements; a per-operation precondition failure; text forbidden by XML 1.0; an edited part that does not parse. Each fails with a non-zero exit, a Traditional Chinese message naming the id and the reason, and no change at the output path.

**Acceptance criteria.**

- Unit tests in `DocxFormTests` cover the tag index (quote-aware tags, comments, nested tables), each kind of the classifier, each operation's positive case and refusals, the default field size including the 18/24/24 example, and the fixed order.
- A package test round-trips a generated `.docx`, edits it, and asserts every entry other than `word/document.xml` has identical bytes and order.
- CLI tests in `MacDocCLITests` run `word form classify` and `word form apply` on generated fixtures, assert the refusal of an existing output and that a failed run leaves the output path absent, and assert the `word reverse --slot` note.
- `cli-spec.yaml` is regenerated and the CLI spec contract tests pass.

**Scope.** In scope: the `DocxForm` target, the two commands, the reverse note, tests, the generated CLI specification, and the swiftify and macdoc skill documentation. Out of scope: everything listed under Non-Goals.

## Risks / Trade-offs

- [String splicing can produce invalid OOXML child order] → insertions use explicit follower lists from ECMA-376 (`w:pPr`, `w:rPr`, `w:tcPr`), and tests assert the position of each inserted element.
- [Removing a paragraph without text can remove content that is not text] → the no-content definition lists drawings, objects, symbols, fields, notes and math explicitly, and tests cover an image paragraph in a field cell.
- [The default field size can surprise a caller] → the chosen size is printed, and `--field-size` overrides it.
- [Two steps (render, then apply) instead of one] → the swiftify skill documents the order and the kind → option table.
- [MCP callers do not get the operations] → recorded as a non-goal and a follow-up.
