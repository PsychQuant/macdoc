// CertifiedTransaction.swift — macdoc#137 Layer 1 (docx-mutation-certification-layer1).
//
// The certified transaction wrapping `Executor`: applies a manifest in
// memory, writes a candidate beside the output, evaluates the Layer 1
// gate and the manifest's `verify` assertions against the candidate, and
// only then atomically renames the candidate onto the output path. See
// design.md's Implementation Contract "Behavior" and spec.md "Certified
// transaction commits only after every gate passes".
//
// Sequence (design.md's numbered contract):
// 0. Pre-flight: reject an output path that is an existing directory, a
//    `--certificate` destination that is not writable, and a
//    `--certificate` destination that refers to the same file as the
//    output, the baseline, or the rejected-candidate path — before
//    anything is touched (R2 review Findings 1 CRITICAL and 2 MEDIUM; R3
//    review Finding A CRITICAL).
// 1. Read the baseline and record its SHA-256.
// 2. Apply the manifest in memory (`Executor`) and write the candidate.
// 3. Run the Layer 1 gate, then the manifest's `verify` assertions, both
//    against the candidate.
// 4. Re-check the baseline hash.
// 5. Only if everything passed, atomically rename the candidate onto the
//    output via POSIX `rename(2)` (R3 review Finding B — `rename(2)`
//    itself refuses a directory destination with `EISDIR` instead of
//    `FileManager.replaceItemAt`'s silent delete-and-replace, closing the
//    TOCTOU window between the pre-flight check above and this rename).
// On any failure, the output path is untouched; the candidate is renamed
// to a rejected-candidate path instead, except for `intentUnavailable`,
// `outputPathIsDirectory`, `certificateDestinationInvalid` and
// `certificateDestinationConflictsWithOtherPath`, which fail before any
// candidate exists.
//
// Certificate persistence is deliberately NOT part of the pass/fail signal
// above (R2 review Finding 1): once the destination has passed pre-flight
// validation, a write failure there (a race — the directory disappeared,
// permissions changed, disk full, ...) is reported only through
// `certificateWarnHandler`, never by changing what `apply` returns or
// throws for the transaction itself.

import Darwin
import Foundation

public struct CertifiedTransaction {

    public init() {}

    /// Public contract per design.md's Implementation Contract "Interface".
    ///
    /// `certificateWarnHandler` is called at most once, only when
    /// `certificateURL` is non-nil and the certificate could not actually
    /// be written even though its destination passed pre-flight validation
    /// (a race). It never changes whether this call returns or throws —
    /// callers that need to know a requested certificate was not persisted
    /// must inspect this handler, not the return value.
    public func apply(
        manifest: Manifest,
        baselineURL: URL,
        outputURL: URL,
        certificateURL: URL? = nil,
        warnHandler: (String) -> Void = { _ in },
        certificateWarnHandler: (String) -> Void = { _ in }
    ) throws -> CertificationCertificate {
        try apply(
            manifest: manifest, baselineURL: baselineURL, outputURL: outputURL,
            certificateURL: certificateURL, warnHandler: warnHandler,
            certificateWarnHandler: certificateWarnHandler,
            testHookAfterCandidateWritten: nil, testHookBeforeBaselineRecheck: nil,
            testHookAfterCommitBeforeCertificateWrite: nil
        )
    }

    /// Test-only seams (macdoc#137 Layer 1), mirroring the precedent in
    /// `OOXMLSwift.DocxWriter.write`'s `immediatelyBeforeGenerationCheck`:
    ///
    /// - `testHookAfterCandidateWritten`: runs right after `Executor` writes
    ///   the candidate, before the Layer 1 gate evaluates it. Lets a test
    ///   simulate design.md's named risk ("the writer changes something
    ///   outside the allowed set in a case not yet seen") through the real
    ///   gate, without hand-assembling a `Layer1Result`.
    /// - `testHookBeforeBaselineRecheck`: runs immediately before the
    ///   baseline's SHA-256 is recomputed, letting a test rewrite the
    ///   baseline to exercise the TOCTOU guard.
    /// - `testHookAfterCommitBeforeCertificateWrite`: runs right after the
    ///   candidate has been committed (to the output or to the rejected
    ///   path), before the certificate write is attempted. Lets a test
    ///   simulate the pre-flight-passed-but-write-still-failed race (R2
    ///   review Finding 1) without a real, timing-dependent concurrent
    ///   process.
    /// - `deriveIntent`: how the intent is derived from the manifest.
    ///   Defaults to `MutationIntent.derive(from:)`. `Step` is a closed
    ///   12-case enum where every runtime-functional case already has a
    ///   table row, so `.intentUnavailable` cannot actually be thrown by
    ///   the real derivation today; this seam lets a test verify the
    ///   surrounding contract (no candidate, output untouched) for real
    ///   when it IS thrown, without waiting for that gap to exist.
    internal func apply(
        manifest: Manifest,
        baselineURL: URL,
        outputURL: URL,
        certificateURL: URL?,
        warnHandler: (String) -> Void,
        certificateWarnHandler: (String) -> Void = { _ in },
        testHookAfterCandidateWritten: ((URL) throws -> Void)?,
        testHookBeforeBaselineRecheck: (() throws -> Void)?,
        testHookAfterCommitBeforeCertificateWrite: (() throws -> Void)? = nil,
        deriveIntent: (Manifest) throws -> MutationIntent = { try MutationIntent.derive(from: $0) }
    ) throws -> CertificationCertificate {

        // 0. Pre-flight: reject an unwritable or conflicting destination
        // before anything is touched. None of these checks depend on the
        // manifest or the baseline's content, so all run before step 1's
        // read.
        try Self.validateOutputIsNotDirectory(outputURL)
        if let certificateURL {
            try Self.validateCertificateDestination(certificateURL, outputURL: outputURL, baselineURL: baselineURL)
        }

        // 1. Read the baseline and record its SHA-256.
        let baselineDataAtRead = try Data(contentsOf: baselineURL)
        let baselineHashAtRead = SidecarStore.sha256Hex(of: baselineDataAtRead)

        // Intent derivation happens before Executor ever runs: on failure,
        // no candidate exists yet (design.md's "Failure modes").
        let intent = try deriveIntent(manifest)

        // 2. Apply the manifest in memory and write the candidate.
        let candidateURL = Self.makeCandidateURL(for: outputURL)
        // R3 review Finding B: if the final commit rename fails, the
        // candidate is deliberately NOT deleted — it is either handed off
        // to the rejected-candidate path, or (if even that rename fails)
        // left at its own `candidateURL` for diagnosis. This flag is set
        // immediately before throwing in either of those cases so the
        // `defer` below does not delete the very evidence just preserved.
        var candidateCleanupSuppressed = false
        defer {
            // Best-effort: once committed (either to `outputURL` or to the
            // rejected path) `candidateURL` no longer exists, so this is a
            // no-op on every normal path. It only matters if something
            // throws between the write above and the rename below.
            if !candidateCleanupSuppressed {
                try? FileManager.default.removeItem(at: candidateURL)
            }
        }
        _ = try Executor().apply(manifest: manifest, baselineURL: baselineURL, outputURL: candidateURL, warnHandler: warnHandler)
        try testHookAfterCandidateWritten?(candidateURL)

        let candidateData = try Data(contentsOf: candidateURL)
        let candidateHash = SidecarStore.sha256Hex(of: candidateData)

        // 3. Layer 1 gate, then verify — both against the candidate.
        let layer1 = Layer1Gate.evaluate(baseline: baselineURL, candidate: candidateURL, intent: intent)

        var verifyOutcome: VerifyOutcome = .notRequested
        var verifyError: VerifyError?
        if let assertions = manifest.verify {
            let candidateUnreadable = layer1.violations.contains { violation in
                if case .unreadablePackage = violation { return true }
                return false
            }
            if candidateUnreadable {
                // Layer 1 already proved the candidate cannot be opened.
                // `Verifier.verify` would throw `DocxReader`'s own error —
                // not a `VerifyError` — which `CertificationError.verifyFailed`
                // cannot carry, and the transaction is rejected by the gate
                // failure regardless.
                verifyOutcome = .failed
            } else {
                do {
                    try Verifier().verify(assertions, baselineURL: baselineURL, outputURL: candidateURL)
                    verifyOutcome = .passed
                } catch let error as VerifyError {
                    verifyOutcome = .failed
                    verifyError = error
                }
            }
        }

        // 4. Re-check the baseline hash immediately before commit.
        try testHookBeforeBaselineRecheck?()
        let baselineDataNow = try Data(contentsOf: baselineURL)
        let baselineChanged = SidecarStore.sha256Hex(of: baselineDataNow) != baselineHashAtRead

        let sortedAllowedParts = intent.allowedParts.sorted()
        let layer1Section = Layer1CertificateSection(passed: layer1.passed, violations: layer1.violations)
        let overallPassed = layer1.passed && verifyOutcome != .failed && !baselineChanged

        // 5. Only if everything passed, atomically rename the candidate.
        if overallPassed {
            do {
                try Self.commit(from: candidateURL, to: outputURL)
            } catch let failure as RenameFailure {
                // The output slot changed underneath us between the last
                // pre-flight check and this rename (R3 review Finding B).
                // `rename(2)` itself refused it (typically `EISDIR`) —
                // unlike `FileManager.replaceItemAt`, it never silently
                // deleted anything. The candidate — which passed every
                // gate — is not lost: fall back to the rejected path.
                let rejectedURL = Self.rejectedURL(for: outputURL)
                var preservedAt: String?
                do {
                    try Self.commit(from: candidateURL, to: rejectedURL)
                    preservedAt = rejectedURL.path
                } catch {
                    candidateCleanupSuppressed = true
                    preservedAt = candidateURL.path
                }
                throw CertificationError.commitFailed(
                    path: outputURL.path,
                    reason: failure.isDestinationDirectory
                        ? "輸出路徑在最後改名瞬間變成了既有目錄"
                        : "改名失敗：\(failure.message)",
                    rejectedCandidatePath: preservedAt
                )
            }
            Self.removeIfExists(Self.rejectedURL(for: outputURL))
            let certificate = CertificationCertificate(
                status: .layer1Verified,
                baselineSHA256: baselineHashAtRead,
                candidateSHA256: candidateHash,
                allowedParts: sortedAllowedParts,
                changedParts: layer1.changedParts,
                layer1: layer1Section,
                verify: verifyOutcome,
                outputURL: outputURL.path,
                rejectedCandidateURL: nil
            )
            // The commit above already happened; a certificate write
            // failure past this point is a race (pre-flight already
            // validated the destination) and must not turn this success
            // into a throw — see `writeCertificateIfRequested`.
            try testHookAfterCommitBeforeCertificateWrite?()
            Self.writeCertificateIfRequested(certificate, to: certificateURL, certificateWarnHandler: certificateWarnHandler)
            return certificate
        }

        let rejectedURL = Self.rejectedURL(for: outputURL)
        do {
            try Self.commit(from: candidateURL, to: rejectedURL)
        } catch let failure as RenameFailure {
            // The rejected-candidate slot itself changed underneath us
            // (the same race as above, just on the failure path). There is
            // no further fallback location; leave the candidate at its own
            // temporary path rather than let the deferred cleanup delete
            // the only remaining evidence.
            candidateCleanupSuppressed = true
            throw CertificationError.commitFailed(
                path: rejectedURL.path,
                reason: failure.isDestinationDirectory
                    ? "rejected 候選檔路徑在最後改名瞬間變成了既有目錄"
                    : "改名失敗：\(failure.message)",
                rejectedCandidatePath: candidateURL.path
            )
        }
        let certificate = CertificationCertificate(
            status: .rejected,
            baselineSHA256: baselineHashAtRead,
            candidateSHA256: candidateHash,
            allowedParts: sortedAllowedParts,
            changedParts: layer1.changedParts,
            layer1: layer1Section,
            verify: verifyOutcome,
            outputURL: outputURL.path,
            rejectedCandidateURL: rejectedURL.path
        )
        try testHookAfterCommitBeforeCertificateWrite?()
        Self.writeCertificateIfRequested(certificate, to: certificateURL, certificateWarnHandler: certificateWarnHandler)

        if !layer1.passed {
            throw CertificationError.gateFailed(certificate)
        }
        if let verifyError {
            throw CertificationError.verifyFailed(verifyError, certificate)
        }
        if baselineChanged {
            throw CertificationError.baselineChanged(certificate)
        }
        // Unreachable: the only remaining way `overallPassed` is false is
        // `verifyOutcome == .failed` via the `candidateUnreadable`
        // short-circuit above, which requires an `unreadablePackage`
        // violation — and that already makes `layer1.passed` false, caught
        // by the first branch. Kept as an exhaustive, fail-closed fallback.
        throw CertificationError.gateFailed(certificate)
    }

    // MARK: - Candidate / rejected paths (design.md "Write the candidate
    // next to the output and keep a rejected candidate for diagnosis")

    private static func makeCandidateURL(for outputURL: URL) -> URL {
        sibling(of: outputURL, suffix: "candidate-\(UUID().uuidString)")
    }

    private static func rejectedURL(for outputURL: URL) -> URL {
        sibling(of: outputURL, suffix: "rejected")
    }

    private static func sibling(of outputURL: URL, suffix: String) -> URL {
        let directory = outputURL.deletingLastPathComponent()
        let stem = outputURL.deletingPathExtension().lastPathComponent
        let ext = outputURL.pathExtension
        let name = ext.isEmpty ? "\(stem).\(suffix)" : "\(stem).\(suffix).\(ext)"
        return directory.appendingPathComponent(name)
    }

    /// A POSIX `rename(2)` failure, carrying `errno` for the caller to
    /// format or specialize (R3 review Finding B).
    private struct RenameFailure: Error {
        let errnoValue: Int32
        var isDestinationDirectory: Bool { errnoValue == EISDIR }
        var message: String { String(cString: strerror(errnoValue)) }
    }

    /// Atomic same-volume rename via the raw POSIX `rename(2)` syscall
    /// (`Darwin.rename`) — deliberately NOT `FileManager.replaceItemAt`
    /// (R2 review Finding 2 → R3 review Finding B). `candidateURL` is
    /// always a sibling of the output, so this is always same-volume: no
    /// cross-volume fallback is needed. `rename(2)`'s own semantics are
    /// exactly what this transaction needs and `replaceItemAt` did not
    /// give: replacing an existing regular file is atomic, and replacing
    /// an existing DIRECTORY is refused with `EISDIR` instead of the
    /// directory (and everything in it) being silently deleted.
    private static func commit(from candidateURL: URL, to destinationURL: URL) throws {
        let result = candidateURL.path.withCString { candidatePath in
            destinationURL.path.withCString { destinationPath in
                Darwin.rename(candidatePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw RenameFailure(errnoValue: errno)
        }
    }

    private static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Same-file identity (R3 review Finding A)

    private struct FileIdentity: Equatable {
        let device: Int
        let inode: Int
    }

    private static func fileIdentity(_ url: URL) -> FileIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        guard let device = attributes[.systemNumber] as? Int,
              let inode = attributes[.systemFileNumber] as? Int else { return nil }
        return FileIdentity(device: device, inode: inode)
    }

    /// True when `a` and `b` refer to the same file: either their
    /// symlink-resolved, standardized paths are textually equal, or — when
    /// both actually exist — they share the same device and inode. The
    /// second check is what catches a hard link, or a case-insensitive
    /// filesystem's collision between two differently cased paths that
    /// string normalization alone does not fold when the leaf component
    /// does not yet exist on disk (APFS is case-insensitive by default: on
    /// such a volume `Out.docx` and `out.docx` name the same file once
    /// either is created, even though `resolvingSymlinksInPath` cannot
    /// know that ahead of creation). Exposed (not `private`) so the CLI
    /// layer can apply the identical rule to a path `CertifiedTransaction`
    /// itself never sees — the manifest's own file path.
    public static func filesAreIdentical(_ a: URL, _ b: URL) -> Bool {
        let normalizedA = a.resolvingSymlinksInPath().standardizedFileURL
        let normalizedB = b.resolvingSymlinksInPath().standardizedFileURL
        if normalizedA.path == normalizedB.path { return true }
        guard let identityA = fileIdentity(normalizedA), let identityB = fileIdentity(normalizedB) else {
            return false
        }
        return identityA == identityB
    }

    // MARK: - Pre-flight destination checks (R2 review Findings 1 CRITICAL, 2 MEDIUM)

    /// `FileManager.replaceItemAt` (used by `commit`) silently deletes an
    /// existing directory — and everything in it — to replace it with a
    /// file. Rejecting that case here means the check happens before the
    /// review's manual reproduction (`mkdir output.docx; echo data >
    /// output.docx/f.txt; macdoc docx apply ... --output output.docx`)
    /// destroys anything, not after.
    private static func validateOutputIsNotDirectory(_ outputURL: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: outputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw CertificationError.outputPathIsDirectory(path: outputURL.path)
        }
    }

    /// Checked before anything is written (R2 review Finding 1, CRITICAL):
    /// the parent directory must exist and be writable, and the
    /// destination itself — if something is already there — must not be a
    /// directory. A write that still fails after this check passes is a
    /// race, handled separately by `writeCertificateIfRequested`'s
    /// `certificateWarnHandler`, not by this function.
    ///
    /// Also checked (R3 review Finding A, CRITICAL): the certificate
    /// destination must not be the same file as the output, the baseline,
    /// or the rejected-candidate path this same call would use. Without
    /// this, a certificate path that happens to equal one of those would
    /// let the certificate write — which runs AFTER the commit — silently
    /// overwrite the just-verified output or the caller's own source file,
    /// while `apply` still reports success.
    private static func validateCertificateDestination(_ certificateURL: URL, outputURL: URL, baselineURL: URL) throws {
        let fm = FileManager.default
        let parent = certificateURL.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            throw CertificationError.certificateDestinationInvalid(
                path: certificateURL.path, reason: "上層目錄不存在：\(parent.path)"
            )
        }
        guard fm.isWritableFile(atPath: parent.path) else {
            throw CertificationError.certificateDestinationInvalid(
                path: certificateURL.path, reason: "上層目錄不可寫：\(parent.path)"
            )
        }
        var targetIsDirectory: ObjCBool = false
        if fm.fileExists(atPath: certificateURL.path, isDirectory: &targetIsDirectory), targetIsDirectory.boolValue {
            throw CertificationError.certificateDestinationInvalid(
                path: certificateURL.path, reason: "目的路徑本身是既有目錄"
            )
        }

        let others: [(URL, String)] = [
            (outputURL, "輸出路徑（--output）"),
            (baselineURL, "baseline 路徑（--input）"),
            (rejectedURL(for: outputURL), "rejected 候選檔路徑"),
        ]
        for (other, role) in others where filesAreIdentical(certificateURL, other) {
            throw CertificationError.certificateDestinationConflictsWithOtherPath(
                certificatePath: certificateURL.path, conflictingRole: role, conflictingPath: other.path
            )
        }
    }

    /// Writes the certificate atomically (temp file + rename, via
    /// `Data.write(options: .atomic)`) and NEVER throws: a failure here —
    /// necessarily a race, since `validateCertificateDestination` already
    /// passed — is reported only through `certificateWarnHandler`. This is
    /// what keeps a certificate-write failure from overwriting the
    /// transaction's own already-decided result (R2 review Finding 1).
    private static func writeCertificateIfRequested(
        _ certificate: CertificationCertificate,
        to certificateURL: URL?,
        certificateWarnHandler: (String) -> Void
    ) {
        guard let certificateURL else { return }
        do {
            try certificate.encoded().write(to: certificateURL, options: .atomic)
        } catch {
            certificateWarnHandler("憑證寫入失敗（\(certificateURL.path)）：\(error)")
        }
    }
}
