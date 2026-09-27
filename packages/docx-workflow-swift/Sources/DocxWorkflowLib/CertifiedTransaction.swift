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
// 1. Read the baseline and record its SHA-256.
// 2. Apply the manifest in memory (`Executor`) and write the candidate.
// 3. Run the Layer 1 gate, then the manifest's `verify` assertions, both
//    against the candidate.
// 4. Re-check the baseline hash.
// 5. Only if everything passed, atomically rename the candidate onto the
//    output.
// On any failure, the output path is untouched; the candidate is renamed
// to a rejected-candidate path instead, except for `intentUnavailable`,
// which fails before any candidate exists.

import Foundation

public struct CertifiedTransaction {

    public init() {}

    /// Public contract per design.md's Implementation Contract "Interface".
    public func apply(
        manifest: Manifest,
        baselineURL: URL,
        outputURL: URL,
        certificateURL: URL? = nil,
        warnHandler: (String) -> Void = { _ in }
    ) throws -> CertificationCertificate {
        try apply(
            manifest: manifest, baselineURL: baselineURL, outputURL: outputURL,
            certificateURL: certificateURL, warnHandler: warnHandler,
            testHookAfterCandidateWritten: nil, testHookBeforeBaselineRecheck: nil
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
        testHookAfterCandidateWritten: ((URL) throws -> Void)?,
        testHookBeforeBaselineRecheck: (() throws -> Void)?,
        deriveIntent: (Manifest) throws -> MutationIntent = { try MutationIntent.derive(from: $0) }
    ) throws -> CertificationCertificate {

        // 1. Read the baseline and record its SHA-256.
        let baselineDataAtRead = try Data(contentsOf: baselineURL)
        let baselineHashAtRead = SidecarStore.sha256Hex(of: baselineDataAtRead)

        // Intent derivation happens before Executor ever runs: on failure,
        // no candidate exists yet (design.md's "Failure modes").
        let intent = try deriveIntent(manifest)

        // 2. Apply the manifest in memory and write the candidate.
        let candidateURL = Self.makeCandidateURL(for: outputURL)
        defer {
            // Best-effort: once committed (either to `outputURL` or to the
            // rejected path) `candidateURL` no longer exists, so this is a
            // no-op on every normal path. It only matters if something
            // throws between the write above and the rename below.
            try? FileManager.default.removeItem(at: candidateURL)
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
            try Self.commit(from: candidateURL, to: outputURL)
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
            try Self.writeCertificateIfRequested(certificate, to: certificateURL)
            return certificate
        }

        let rejectedURL = Self.rejectedURL(for: outputURL)
        try Self.commit(from: candidateURL, to: rejectedURL)
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
        try Self.writeCertificateIfRequested(certificate, to: certificateURL)

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

    /// Atomic same-volume rename (POSIX `rename(2)`, falling back to
    /// copy+delete cross-volume) via the same `FileManager` API
    /// `OOXMLSwift.DocxWriter.write` uses. Replaces `destinationURL` if it
    /// already exists — "replacing any previous rejected file" for the
    /// rejected path, and the normal overwrite semantics for the output.
    private static func commit(from candidateURL: URL, to destinationURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(
            destinationURL, withItemAt: candidateURL, backupItemName: nil, options: []
        )
    }

    private static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func writeCertificateIfRequested(_ certificate: CertificationCertificate, to certificateURL: URL?) throws {
        guard let certificateURL else { return }
        try certificate.encoded().write(to: certificateURL)
    }
}
