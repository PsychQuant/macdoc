// MutationIntent.swift — macdoc#137 Layer 1 (docx-mutation-certification-layer1).
//
// Derives the set of OOXML package parts a manifest's steps are allowed to
// change, through a closed per-step-type table. See design.md "Derive
// allowed parts from step types through a closed table" and spec.md
// "Mutation intent is derived from a closed step-type table".
//
// The table is deliberately NOT extended by inference: a runtime-functional
// step type without a row fails the whole transaction (`intentUnavailable`)
// rather than being silently permitted. Pending (Phase 2c) step types
// contribute no parts — they never reach the writer.

import Foundation

/// Errors shared by the certification transaction (`CertifiedTransaction`)
/// and mutation-intent derivation. A single closed enum per design.md's
/// Implementation Contract.
public enum CertificationError: Error {
    /// A runtime-functional step type has no row in
    /// `MutationIntent.allowedPartsTable`. Thrown before any candidate file
    /// is written.
    case intentUnavailable(stepType: String)
    /// The Layer 1 gate found at least one violation.
    case gateFailed(CertificationCertificate)
    /// A manifest `verify` assertion failed against the candidate.
    case verifyFailed(VerifyError, CertificationCertificate)
    /// The baseline's bytes changed between the initial read and the
    /// commit-time recheck (TOCTOU guard).
    case baselineChanged(CertificationCertificate)
    /// The output path already exists and is a directory. Thrown before
    /// any candidate is written (R2 review Finding 2) — `FileManager
    /// .replaceItemAt`, which `CertifiedTransaction.commit` uses, silently
    /// deletes a directory (and everything in it) to replace it with a
    /// file, so this is checked up front instead of discovered by data
    /// loss.
    case outputPathIsDirectory(path: String)
    /// The `--certificate` destination is unwritable: its parent directory
    /// does not exist, is not writable, or the destination path itself is
    /// an existing directory. Thrown before any candidate is written (R2
    /// review Finding 1, CRITICAL) — a certificate write that fails AFTER
    /// this pre-flight check has passed is a separate, narrower case (a
    /// race) and does NOT throw this; see `CertifiedTransaction`'s
    /// `certificateWarnHandler`.
    case certificateDestinationInvalid(path: String, reason: String)
}

/// The set of package parts a manifest is allowed to change, derived from
/// its steps' types alone (never from anchor resolution or document
/// content — `MutationIntent.derive(from:)` runs before the baseline is
/// touched).
public struct MutationIntent: Equatable {
    public let allowedParts: Set<String>
    /// The runtime-functional step type IDs that contributed to
    /// `allowedParts`, in manifest order. Informational — not part of the
    /// certificate schema.
    public let stepSummary: [String]

    public init(allowedParts: Set<String>, stepSummary: [String]) {
        self.allowedParts = allowedParts
        self.stepSummary = stepSummary
    }

    /// The closed step-type → allowed-parts table (design.md "Derive
    /// allowed parts from step types through a closed table"). Extending
    /// this table is a reviewed source change, never a runtime inference.
    static let allowedPartsTable: [String: Set<String>] = [
        "insert_paragraph": ["word/document.xml"],
        "remove_paragraph": ["word/document.xml"],
        "set_bold": ["word/document.xml"],
        "wrap_link": ["word/document.xml", "word/_rels/document.xml.rels"],
    ]

    /// Classifies a `Step` as runtime-functional (has a candidate row in
    /// the table, per EditPlanner's Phase 1 functional set) or pending
    /// (Phase 2c — EditPlanner always skips it, contributing no parts).
    /// This mirrors EditPlanner's own case split but does not call
    /// `EditPlanner.compile`, which requires a resolved anchor; the
    /// classification here is by step TYPE only, matching what the table
    /// keys on.
    private static func isRuntimeFunctional(_ step: Step) -> Bool {
        switch step {
        case .insertParagraph, .removeParagraph, .setBold, .wrapLink:
            return true
        case .replaceText, .setParagraphStyle, .setItalic, .setUnderline,
             .insertImage, .insertTable, .setCellText, .insertEquation:
            return false
        }
    }

    /// Derives the intent from a manifest's steps. Pure function of the
    /// manifest — no document I/O, no anchor resolution.
    public static func derive(from manifest: Manifest) throws -> MutationIntent {
        let functionalTypeIDs = manifest.steps
            .filter(isRuntimeFunctional)
            .map { $0.typeID }
        return try derive(functionalStepTypeIDs: functionalTypeIDs)
    }

    /// Test-only seam (macdoc#137 Layer 1): lets `MutationIntentTests`
    /// exercise the "runtime-functional step type with no table row"
    /// failure without waiting for a real `Step` case to reach that state
    /// — `Step` is a closed 12-case enum and every case
    /// `isRuntimeFunctional` accepts already has a row. The public
    /// contract is `derive(from: Manifest)`; this overload is `internal`.
    internal static func derive(functionalStepTypeIDs: [String]) throws -> MutationIntent {
        var parts = Set<String>()
        for typeID in functionalStepTypeIDs {
            guard let rows = allowedPartsTable[typeID] else {
                throw CertificationError.intentUnavailable(stepType: typeID)
            }
            parts.formUnion(rows)
        }
        return MutationIntent(allowedParts: parts, stepSummary: functionalStepTypeIDs)
    }
}
