// Executor.swift — §4.2 + §4.3 of macdoc-docx-workflow-cli.
//
// Orchestrates: read baseline → (resolve anchor → compile Edit → apply) per
// step → emit output. Sequential anchor resolution per spec.md "Executor
// applies steps in manifest order" — the snapshot is rebuilt between steps
// so step N's anchor sees step N-1's effect.
//
// Runtime handle = OOXMLSwift.WordDocument (not LensDocument) per the
// amended spec.md "Library uses the foundation's WordDocument as the
// runtime handle" Scenario. Rationale: word-builder-swift v1.0.0's
// LensDocument hides its inner WordDocument behind a private field, so
// downstream consumers cannot extract paragraph ElementIDs from a
// LensDocument value. Phase 1 goes through WordDocument directly. The
// user-visible CLI contract is unchanged. A future word-builder-swift
// surface exposing paragraph IDs would let Phase 2 switch to LensDocument.

import Foundation

public struct Executor {

    public init() {}

    public func apply(
        manifest: Manifest,
        baselineURL: URL,
        outputURL: URL,
        warnHandler: (String) -> Void = { _ in }
    ) throws -> ExecutorResult {
        var doc = try DocxReader.read(from: baselineURL, wireTreeBackedViews: true)

        let resolver = AnchorResolver()
        let planner = EditPlanner()

        var appliedCount = 0
        var skippedCount = 0
        var skippedTypes: [String] = []

        for (idx, step) in manifest.steps.enumerated() {
            // Resolve anchor against current (post-prior-steps) state.
            var anchorRef: ParagraphRef? = nil
            if planner.requiresAnchor(step), let anchor = anchorForStep(step) {
                let snapshot = ParagraphSnapshot.entries(from: doc)
                anchorRef = try resolver.resolve(anchor, snapshot: snapshot, stepIndex: idx)
            }

            switch planner.compile(step, anchorRef: anchorRef) {
            case .functional(let edit):
                doc = try doc.apply(edit)
                appliedCount += 1

            case .pending(let stepType, let tracker):
                warnHandler("warn: step type '\(stepType)' has no Reducer support yet (tracker: \(tracker)); skipping")
                skippedCount += 1
                skippedTypes.append(stepType)
            }
        }

        // Emit via the foundation's DocxWriter. Plain write — atomic
        // overwrite via Data.write(to:options:.atomic) does an unlink-rename
        // dance on macOS that errors when the destination doesn't exist
        // (NSCocoaErrorDomain Code=4). Default write semantics handle both
        // create-new and overwrite-existing paths cleanly.
        let bytes = try DocxWriter.writeData(doc)
        try bytes.write(to: outputURL)

        return ExecutorResult(
            appliedStepCount: appliedCount,
            skippedPendingStepCount: skippedCount,
            skippedStepTypes: skippedTypes
        )
    }

    private func anchorForStep(_ step: Step) -> Anchor? {
        switch step {
        case .insertParagraph(let p): return p.anchor
        case .removeParagraph(let p): return p.anchor
        case .wrapLink(let p): return p.anchor
        case .setBold(let p): return p.anchor
        case .setItalic(let p): return p.anchor
        case .setUnderline(let p): return p.anchor
        case .setParagraphStyle(let p): return p.anchor
        case .insertImage(let p): return p.anchor
        case .insertTable(let p): return p.anchor
        case .setCellText(let p): return p.anchor
        case .insertEquation(let p): return p.anchor
        case .replaceText:
            return nil  // replace_text is anchorless (find+replace across doc)
        }
    }
}

// MARK: - ExecutorResult

public struct ExecutorResult: Equatable {
    public let appliedStepCount: Int
    public let skippedPendingStepCount: Int
    public let skippedStepTypes: [String]

    public init(appliedStepCount: Int, skippedPendingStepCount: Int, skippedStepTypes: [String]) {
        self.appliedStepCount = appliedStepCount
        self.skippedPendingStepCount = skippedPendingStepCount
        self.skippedStepTypes = skippedStepTypes
    }
}
