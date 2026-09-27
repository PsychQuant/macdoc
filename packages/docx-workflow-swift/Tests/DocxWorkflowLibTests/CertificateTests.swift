// CertificateTests — macdoc#137 Layer 1 (docx-mutation-certification-layer1).
//
// Covers spec.md Requirement "Certificate claims only evaluated layers":
// a JSON round-trip (including an encoded `Layer1Violation`), a check that
// the status vocabulary cannot encode `certified`, and a check of the
// top-level key names against design.md's Implementation Contract
// "Interface" list.

import XCTest
import DocxWorkflowLib

final class CertificateTests: XCTestCase {

    private func sampleCertificate(status: CertificationStatus = .layer1Verified) -> CertificationCertificate {
        CertificationCertificate(
            status: status,
            baselineSHA256: "aaaa",
            candidateSHA256: "bbbb",
            allowedParts: ["word/document.xml"],
            changedParts: ["word/document.xml"],
            layer1: Layer1CertificateSection(
                passed: status == .layer1Verified,
                violations: status == .layer1Verified ? [] : [.partRemoved("word/theme/theme1.xml"),
                                                               .unexpectedChange(part: "word/styles.xml", baselineSize: 10, candidateSize: 20, firstDifferingOffset: 3)]
            ),
            verify: .notRequested,
            outputURL: "/tmp/out.docx",
            rejectedCandidateURL: status == .layer1Verified ? nil : "/tmp/out.rejected.docx"
        )
    }

    // MARK: - JSON round-trip

    /// `Date`'s `==` compares `timeIntervalSinceReferenceDate` (offset from
    /// 2001); the certificate's `.secondsSince1970` encoding round-trips
    /// through `timeIntervalSince1970` (offset from 1970). Adding and then
    /// subtracting that ~978,307,200-second constant can lose a
    /// sub-microsecond low bit that `Date()`'s native representation
    /// carries — the JSON number itself round-trips exactly (verified
    /// separately against a bare `Date` below this file's scope), but the
    /// reconstructed `Date` can differ from the original by roughly 1 ULP.
    /// A certificate consumer reads a timestamp; it does not need
    /// bit-exact `Date` equality, so field-by-field comparison tolerates
    /// this instead of the test switching to a lossier or non-standard
    /// date encoding.
    private func assertRoundTripsIgnoringTimestampULP(
        _ decoded: CertificationCertificate, _ original: CertificationCertificate,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(decoded.schemaVersion, original.schemaVersion, file: file, line: line)
        XCTAssertEqual(decoded.status, original.status, file: file, line: line)
        XCTAssertEqual(decoded.baselineSHA256, original.baselineSHA256, file: file, line: line)
        XCTAssertEqual(decoded.candidateSHA256, original.candidateSHA256, file: file, line: line)
        XCTAssertEqual(decoded.allowedParts, original.allowedParts, file: file, line: line)
        XCTAssertEqual(decoded.changedParts, original.changedParts, file: file, line: line)
        XCTAssertEqual(decoded.layer1, original.layer1, file: file, line: line)
        XCTAssertEqual(decoded.layer2, original.layer2, file: file, line: line)
        XCTAssertEqual(decoded.layer3, original.layer3, file: file, line: line)
        XCTAssertEqual(decoded.verify, original.verify, file: file, line: line)
        XCTAssertEqual(decoded.outputURL, original.outputURL, file: file, line: line)
        XCTAssertEqual(decoded.rejectedCandidateURL, original.rejectedCandidateURL, file: file, line: line)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970,
                        accuracy: 0.001, file: file, line: line)
    }

    func testJSONRoundTripPreservesEveryField() throws {
        let original = sampleCertificate(status: .rejected)
        let data = try original.encoded()
        let decoded = try CertificationCertificate.makeDecoder().decode(CertificationCertificate.self, from: data)
        assertRoundTripsIgnoringTimestampULP(decoded, original)
    }

    func testJSONRoundTripOfSuccessfulCertificate() throws {
        let original = sampleCertificate(status: .layer1Verified)
        let data = try original.encoded()
        let decoded = try CertificationCertificate.makeDecoder().decode(CertificationCertificate.self, from: data)
        assertRoundTripsIgnoringTimestampULP(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(decoded.rejectedCandidateURL)
    }

    // MARK: - Status vocabulary cannot encode `certified`

    func testStatusVocabularyIsExactlyTwoValuesNeverCertified() {
        let rawValues = Set(CertificationStatus.allCases.map(\.rawValue))
        XCTAssertEqual(rawValues, ["layer1Verified", "rejected"])
        XCTAssertFalse(rawValues.contains("certified"))
    }

    func testDecodingCertifiedStatusFails() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(CertificationStatus.self, from: Data(#""certified""#.utf8))
        )
    }

    // MARK: - layer2 / layer3 always notEvaluated with a non-empty reason

    func testLayer2AndLayer3AreNotEvaluatedWithNonEmptyReason() {
        let certificate = sampleCertificate()
        XCTAssertEqual(certificate.layer2.status, "notEvaluated")
        XCTAssertFalse(certificate.layer2.reason.isEmpty)
        XCTAssertEqual(certificate.layer3.status, "notEvaluated")
        XCTAssertFalse(certificate.layer3.reason.isEmpty)
    }

    // MARK: - Key names (design.md Implementation Contract "Interface")

    func testTopLevelKeyNamesMatchImplementationContract() throws {
        let data = try sampleCertificate().encoded()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = Set(try XCTUnwrap(object).keys)
        XCTAssertEqual(keys, [
            "schemaVersion", "status", "baselineSHA256", "candidateSHA256",
            "allowedParts", "changedParts", "layer1", "layer2", "layer3",
            "verify", "outputURL", "rejectedCandidateURL", "createdAt",
        ])
    }

    func testLayer1SectionKeyNames() throws {
        let data = try sampleCertificate(status: .rejected).encoded()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let layer1 = try XCTUnwrap(try XCTUnwrap(object)["layer1"] as? [String: Any])
        XCTAssertEqual(Set(layer1.keys), ["passed", "violations"])
    }

    func testLayer2SectionKeyNames() throws {
        let data = try sampleCertificate().encoded()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let layer2 = try XCTUnwrap(try XCTUnwrap(object)["layer2"] as? [String: Any])
        XCTAssertEqual(Set(layer2.keys), ["status", "reason"])
        XCTAssertEqual(layer2["status"] as? String, "notEvaluated")
    }

    func testSchemaVersionIsFixedAtOne() {
        XCTAssertEqual(sampleCertificate().schemaVersion, 1)
    }
}
