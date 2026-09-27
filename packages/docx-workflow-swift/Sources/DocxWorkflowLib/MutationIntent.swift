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
    /// The `--certificate` destination refers to the same file as another
    /// path this transaction uses — the output, the baseline, the
    /// rejected-candidate path, or (checked by the CLI layer, which is the
    /// only layer that knows this path) the manifest file itself. Writing
    /// the certificate there would silently destroy content the
    /// transaction just proved valid, or the caller's own source file.
    /// Thrown before any candidate is written (R3 review Finding A,
    /// CRITICAL). `conflictingRole` is a ready-to-print Traditional
    /// Chinese phrase naming which path it collided with (e.g. "輸出路徑
    /// （--output）"), matching the convention `certificateDestinationInvalid`
    /// already established of composing the Chinese text at the throw site.
    case certificateDestinationConflictsWithOtherPath(certificatePath: String, conflictingRole: String, conflictingPath: String)
    /// Every gate and every requested `verify` assertion passed, but the
    /// final rename — the candidate onto the output path — itself failed.
    /// This is what closes the TOCTOU window `FileManager.replaceItemAt`
    /// left open (R2 review Finding 2 → R3 review Finding B): the commit
    /// now goes through POSIX `rename(2)`, which refuses a directory
    /// destination (`EISDIR`) instead of silently deleting it, so this
    /// case is how that refusal — or any other rename failure — surfaces.
    /// The candidate is preserved at `rejectedCandidatePath` when that
    /// fallback rename succeeds; it is `nil` only if even that failed (the
    /// candidate then remains at its own temporary path, not deleted).
    case commitFailed(path: String, reason: String, rejectedCandidatePath: String?)
    /// The output path is itself a symbolic link (R4 review Finding E).
    /// POSIX `rename(2)` — unlike `FileManager.replaceItemAt`, which threw
    /// and touched nothing for this same case — replaces the SYMLINK
    /// itself when its destination names one, not the file the symlink
    /// points to: the alias relationship the caller set up would be
    /// silently severed, and whatever the link used to point to is left
    /// untouched and now out of sync with the new output. Rejected instead,
    /// before any candidate is written, if the symlink was already there
    /// at the pre-flight check; or with the candidate preserved at
    /// `rejectedCandidatePath` (non-`nil`), if the symlink appeared only in
    /// the narrow window between pre-flight and the commit rename (checked
    /// again immediately before that rename). `linkTarget` is the raw
    /// value the symlink points to, for the error message to suggest using
    /// the real path instead.
    case outputPathIsSymlink(path: String, linkTarget: String, rejectedCandidatePath: String?)
    /// The output path already exists, so its permissions, ACL and
    /// extended attributes must be carried over onto the candidate before
    /// the commit (R4 review Finding F) — `rename(2)`, unlike the
    /// `FileManager.replaceItemAt` this replaced, does not do this itself,
    /// so without this step a caller's tighter permissions on an existing
    /// output would be silently widened back to the process's default
    /// umask on every rerun. This case is thrown if that copy itself fails
    /// (`copyfile(3)`, e.g. the existing output became unreadable) — the
    /// commit is rejected outright rather than land with looser access
    /// than the file being replaced had. The candidate is preserved at
    /// `rejectedCandidatePath` when the fallback rename succeeds; `nil`
    /// only if even that failed.
    case metadataPreservationFailed(path: String, reason: String, rejectedCandidatePath: String?)
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
