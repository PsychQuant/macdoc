## Why

Filling a table-dense official form with swiftify puts every value in the right place, but the output looks uneven because the template itself is uneven: field cells use different sizes (9, 11, 12 pt), some carry an annotation style, a first-line indent or distributed alignment, some cells are not vertically centred, extra empty paragraphs push values above the centre line, and a box glyph that shares a run with Latin text is drawn in the Latin font and comes out smaller. Downstream callers currently repair every filled form with separate post-processing scripts. A raw-channel slot only replaces text (it never touches the cell, the box font or the surrounding paragraphs), so this has to be a separate, explicit step (PsychQuant/macdoc#249).

## What Changes

- New root-level target `DocxForm`: a paragraph classifier and string-level operations on `word/document.xml` that never re-serialize through the typed model, so raw-channel forms keep every byte outside the edited elements.
- New command `macdoc word form classify <in.docx>`: lists every paragraph that carries a `w14:paraId` with its kind from a closed enumeration (`list-checkbox`, `checkbox-line`, `table-field`, `body`) and a short text preview.
- New command `macdoc word form apply <in.docx> --to-docx <out.docx>` with these operations: `--field` (table field normalization: one size, left alignment, vertical centre, no style/indent, no text-less sibling paragraphs), `--field-size`, `--checkbox-font` (box glyphs drawn in one font), `--tick-list` (tick a box that is a list bullet), `--insert-after` (new paragraphs that inherit the anchor's format), `--remove`, `--truncate-from` (cut the body and keep the right section settings).
- `apply` validates every paragraph id before changing anything, runs the operations in a fixed order, checks the result is well-formed XML, copies every other zip part unchanged, refuses an existing output unless `--force`, and writes atomically. Any failure leaves the output path as it was.
- `macdoc word reverse --slot` prints one stderr note for each slot whose kind needs a follow-up (`table-field`, `checkbox-line`, `list-checkbox`), naming the matching `word form apply` option.
- The swiftify skill gains a kind → operation table and a form-normalization step after render; the macdoc skill documents the new commands.

## Capabilities

### New Capabilities

- `docx-form-normalization`: classification of form paragraphs by structural kind and the string-level operations that make a filled form uniform (field normalization, box font, list tick, inheriting insert, removal, truncation) with all-or-nothing output.

### Modified Capabilities

- `swiftify-workflow`: the documented round trip gains an optional form-normalization step after render, routed by paragraph kind.

## Impact

- Affected specs: `docx-form-normalization` (new), `swiftify-workflow` (modified)
- Affected code:
  - New: Sources/DocxForm/XMLTagIndex.swift, Sources/DocxForm/FormClassifier.swift, Sources/DocxForm/FormEditing.swift, Sources/DocxForm/FormOperations.swift, Sources/DocxForm/FormPlan.swift, Sources/DocxForm/DocxPackage.swift, Sources/MacDocCLI/MacDoc+Word+Form.swift, Tests/DocxFormTests/TestXML.swift, Tests/DocxFormTests/XMLTagIndexTests.swift, Tests/DocxFormTests/FormClassifierTests.swift, Tests/DocxFormTests/FormOperationsTests.swift, Tests/DocxFormTests/FormPlanTests.swift, Tests/DocxFormTests/DocxPackageTests.swift, Tests/MacDocCLITests/WordFormCommandTests.swift
  - Modified: Package.swift, Sources/MacDocCLI/MacDoc+Word.swift, cli-spec.yaml, plugins/macdoc/skills/swiftify/SKILL.md, plugins/macdoc/skills/macdoc/SKILL.md, plugins/macdoc/CHANGELOG.md
  - Removed: (none)
- Dependencies: ZIPFoundation (already a direct dependency of the package).
- Field size default (confirmed by the maintainer on 2026-11-04, previously an unattended assumption): when `--field-size` is omitted, the size is the most common explicit run size across the designated fields, ties going to the larger size. Left alignment is `w:jc w:val="left"`, and the box glyphs are exactly □ ■ ☐ ☑ ☒.
- Deferred to PsychQuant/macdoc#250: a whole-table pass (label cells untouched; the fill-cell rule is undecided). Removal of a whole table in the middle of the body was added there as `--remove-table`.
