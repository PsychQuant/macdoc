// AnchorResolver.swift — §3.1 of macdoc-docx-workflow-cli.
//
// Implements design.md Decision 4: Anchor model — text-based with
// multi-match = FAIL, zero-match = FAIL.
//
// The resolver decouples from the document handle by accepting a
// pre-built `[ParagraphSnapshotEntry]` (see ParagraphSnapshot). The
// Executor rebuilds the snapshot between steps so sequential anchor
// resolution sees post-step state (spec.md "Sequential anchor resolution
// sees prior step output").

import Foundation

public enum AnchorError: Error, Equatable {
    case notFound(anchor: String, stepIndex: Int, scannedCount: Int)
    case ambiguous(anchor: String, stepIndex: Int, matches: [Int])
    case indexOutOfRange(requested: Int, available: Int)
}

public struct AnchorResolver {

    public init() {}

    /// Resolves an `Anchor` against a paragraph snapshot. Outcomes are
    /// exactly one of three:
    /// - exact-one match → returns the matching `ParagraphRef`
    /// - zero matches → throws `.notFound`
    /// - multi-match → throws `.ambiguous`
    /// First-match-wins fallback SHALL NOT happen.
    public func resolve(
        _ anchor: Anchor,
        snapshot: [ParagraphSnapshotEntry],
        stepIndex: Int
    ) throws -> ParagraphRef {
        switch anchor {
        case .beforeText(let text), .afterText(let text):
            return try resolveText(text, snapshot: snapshot, stepIndex: stepIndex)
        case .paragraphIndex(let idx):
            return try resolveIndex(idx, snapshot: snapshot)
        }
    }

    private func resolveText(
        _ text: String,
        snapshot: [ParagraphSnapshotEntry],
        stepIndex: Int
    ) throws -> ParagraphRef {
        // Exact-substring search across paragraph text in body order.
        let matches: [Int] = snapshot.enumerated().compactMap { (idx, entry) in
            entry.text.contains(text) ? idx : nil
        }

        switch matches.count {
        case 0:
            throw AnchorError.notFound(
                anchor: text,
                stepIndex: stepIndex,
                scannedCount: snapshot.count
            )
        case 1:
            return snapshot[matches[0]].ref
        default:
            throw AnchorError.ambiguous(
                anchor: text,
                stepIndex: stepIndex,
                matches: matches
            )
        }
    }

    private func resolveIndex(
        _ idx: Int,
        snapshot: [ParagraphSnapshotEntry]
    ) throws -> ParagraphRef {
        guard idx >= 0, idx < snapshot.count else {
            throw AnchorError.indexOutOfRange(
                requested: idx,
                available: snapshot.count
            )
        }
        return snapshot[idx].ref
    }
}
