// EditPlanner.swift — §4.1 of macdoc-docx-workflow-cli.
//
// Compiles each Manifest Step into either a `.functional(any Edit)` or a
// `.pending(stepType:, tracker:)` outcome. The planner is the boundary
// between manifest schema (forward-compatible JSON shape) and the
// foundation's Edit-algebra runtime (case-by-case Reducer landings).
//
// Phase 1 runtime-functional set (per word-builder-swift v1.0.0 +
// ooxml-swift Phase 2c shipped cases):
//   - insert_paragraph    → OOXMLEdit.insertParagraph(after:, content:, styleId:)
//   - remove_paragraph    → OOXMLEdit.removeParagraph(target:)
//   - wrap_link           → OOXMLEdit.wrapWithHyperlink(target:, href:)
//   - set_bold            → OOXMLEdit.setBoldInRange(target:, substring:,
//                            value: true, instance: 1) (ooxml-swift 3.16.0,
//                            PsychQuant/macdoc#232). `target` is the anchor
//                            PARAGRAPH's ElementID, not a Run — the reducer
//                            locates `substring` within the paragraph's
//                            flattened text and splits run(s) as needed so
//                            only the matched range is bolded. Previously
//                            compiled to `OOXMLEdit.setBold(target:, value:)`
//                            against the paragraph ElementID, which the
//                            reducer always rejected (`setRunFormat target
//                            must be <w:r>`) because that case expects a
//                            Run, not a paragraph — `substring` was decoded
//                            but never consulted.
//
// Phase 1 spec-documented but Reducer-pending (warn + skip at runtime):
//   - replace_text, set_italic, set_underline, set_paragraph_style — pending
//     because shipping their OOXMLEdit / WordEdit cases is part of ooxml-swift
//     Phase 2c follow-up (tracker: ooxml-swift#71). Originally listed as
//     functional in design.md Decision 5 based on optimistic Phase-2c-landing
//     assumptions; spec.md "SHALL include [pending list]" wording permits
//     expansion.
//   - insert_image, insert_table, set_cell_text, insert_equation —
//     originally documented as pending in spec.md.

import Foundation

internal struct EditPlanner {

    enum CompileResult {
        case functional(any Edit)
        case pending(stepType: String, tracker: String)
    }

    func compile(_ step: Step, anchorRef: ParagraphRef?) -> CompileResult {
        switch step {

        // MARK: Runtime-functional

        case .insertParagraph(let payload):
            // After-text / paragraph-index anchors compile to insertParagraph;
            // before-text uses insertParagraphBefore. Style not exposed by the
            // Phase 1 manifest shape — pass nil.
            guard let ref = anchorRef else {
                return .pending(stepType: "insert_paragraph", tracker: "internal: anchor missing")
            }
            switch payload.anchor {
            case .beforeText:
                return .functional(OOXMLEdit.insertParagraphBefore(
                    before: ref.elementID,
                    content: payload.content,
                    styleId: nil
                ))
            case .afterText, .paragraphIndex:
                return .functional(OOXMLEdit.insertParagraph(
                    after: ref.elementID,
                    content: payload.content,
                    styleId: nil
                ))
            }

        case .removeParagraph(_):
            guard let ref = anchorRef else {
                return .pending(stepType: "remove_paragraph", tracker: "internal: anchor missing")
            }
            return .functional(OOXMLEdit.removeParagraph(target: ref.elementID))

        case .wrapLink(let payload):
            guard let ref = anchorRef else {
                return .pending(stepType: "wrap_link", tracker: "internal: anchor missing")
            }
            // URL parsing failure → Reducer-pending; treat as pending so the
            // manifest doesn't break.
            guard let url = URL(string: payload.url) else {
                return .pending(stepType: "wrap_link", tracker: "invalid URL: \(payload.url)")
            }
            return .functional(OOXMLEdit.wrapWithHyperlink(target: ref.elementID, href: url))

        case .setBold(let payload):
            guard let ref = anchorRef else {
                return .pending(stepType: "set_bold", tracker: "internal: anchor missing")
            }
            // PsychQuant/macdoc#232: an empty substring can never match a
            // text range inside the anchor paragraph — reject it here, at
            // compile time, rather than emitting an Edit that would only
            // fail once `doc.apply(edit)` materializes the operation log
            // (ooxml-swift's reducer also defends against this with its own
            // "substring must not be empty" `malformedOp`, but surfacing it
            // here means a malformed manifest never reaches the reducer at
            // all). Same treatment `wrap_link` already gives an unparsable
            // `url` a few cases above: pending + a tracker string, not a
            // thrown error — the manifest doesn't break, the step is
            // skipped and reported via `warnHandler`.
            guard !payload.substring.isEmpty else {
                return .pending(
                    stepType: "set_bold",
                    tracker: "empty substring: manifest declares substring: \"\" for anchor \(payload.anchor), which can never match a text range"
                )
            }
            return .functional(OOXMLEdit.setBoldInRange(
                target: ref.elementID,
                substring: payload.substring,
                value: true
            ))

        // MARK: Phase 2c Reducer-pending (no shipped Edit case in v1.0.0)

        case .replaceText:
            return .pending(stepType: "replace_text", tracker: "ooxml-swift#71")

        case .setItalic:
            return .pending(stepType: "set_italic", tracker: "ooxml-swift#71")

        case .setUnderline:
            return .pending(stepType: "set_underline", tracker: "ooxml-swift#71")

        case .setParagraphStyle:
            return .pending(stepType: "set_paragraph_style", tracker: "ooxml-swift#71")

        case .insertImage:
            return .pending(stepType: "insert_image", tracker: "ooxml-swift#71")

        case .insertTable:
            return .pending(stepType: "insert_table", tracker: "ooxml-swift#71")

        case .setCellText:
            return .pending(stepType: "set_cell_text", tracker: "ooxml-swift#71")

        case .insertEquation:
            return .pending(stepType: "insert_equation", tracker: "ooxml-swift#71")
        }
    }

    /// Step types that require anchor resolution (i.e., the planner needs a
    /// non-nil `anchorRef`). Used by the Executor to skip snapshot building
    /// for anchorless steps (Phase 1 has none, but the API stays general).
    func requiresAnchor(_ step: Step) -> Bool {
        switch step {
        case .replaceText:
            return false  // (pending; never reaches functional path, but conceptually anchorless)
        case .insertParagraph, .removeParagraph, .wrapLink, .setBold,
             .setItalic, .setUnderline, .setParagraphStyle,
             .insertImage, .insertTable, .setCellText, .insertEquation:
            return true
        }
    }
}
