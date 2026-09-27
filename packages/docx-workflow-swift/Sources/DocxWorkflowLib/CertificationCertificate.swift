// CertificationCertificate.swift — macdoc#137 Layer 1 (docx-mutation-certification-layer1).
//
// The certificate `CertifiedTransaction.apply` produces: a JSON document
// that states exactly which evidence layers were evaluated and never
// claims a layer that was not measured. See design.md "Certificate claims
// only the layers that were evaluated" and spec.md "Certificate claims
// only evaluated layers".
//
// `status` is a closed two-case vocabulary (`layer1Verified` / `rejected`)
// — the value `certified` cannot be represented, let alone encoded, by
// this schema version. `layer2`/`layer3` are always `notEvaluated` with a
// non-empty `reason` naming the future slice.

import Foundation

public enum CertificationStatus: String, Codable, Equatable, CaseIterable {
    case layer1Verified
    case rejected
}

public enum VerifyOutcome: String, Codable, Equatable, CaseIterable {
    case passed
    case failed
    case notRequested
}

/// A layer this schema version does not evaluate. `status` is always the
/// literal string `"notEvaluated"` — it is a field, not a case of
/// `CertificationStatus`, because a not-evaluated layer is not itself a
/// transaction outcome.
public struct NotEvaluatedLayer: Codable, Equatable {
    public let status: String
    public let reason: String

    public init(reason: String) {
        self.status = "notEvaluated"
        self.reason = reason
    }
}

public struct Layer1CertificateSection: Codable, Equatable {
    public let passed: Bool
    public let violations: [Layer1Violation]

    public init(passed: Bool, violations: [Layer1Violation]) {
        self.passed = passed
        self.violations = violations
    }
}

public struct CertificationCertificate: Codable, Equatable {

    public static let currentSchemaVersion = 1

    public static let layer2NotEvaluatedReason =
        "Layer 2 (typed round-trip / trial-rebuild gate) is a later slice of macdoc#137; not evaluated by docx-mutation-certification-layer1."
    public static let layer3NotEvaluatedReason =
        "Layer 3 (real-Word render oracle) is a later slice of macdoc#137; not evaluated by docx-mutation-certification-layer1."

    public let schemaVersion: Int
    public let status: CertificationStatus
    public let baselineSHA256: String
    public let candidateSHA256: String
    public let allowedParts: [String]
    public let changedParts: [String]
    public let layer1: Layer1CertificateSection
    public let layer2: NotEvaluatedLayer
    public let layer3: NotEvaluatedLayer
    public let verify: VerifyOutcome
    public let outputURL: String?
    public let rejectedCandidateURL: String?
    public let createdAt: Date

    public init(
        status: CertificationStatus,
        baselineSHA256: String,
        candidateSHA256: String,
        allowedParts: [String],
        changedParts: [String],
        layer1: Layer1CertificateSection,
        layer2: NotEvaluatedLayer = NotEvaluatedLayer(reason: CertificationCertificate.layer2NotEvaluatedReason),
        layer3: NotEvaluatedLayer = NotEvaluatedLayer(reason: CertificationCertificate.layer3NotEvaluatedReason),
        verify: VerifyOutcome,
        outputURL: String?,
        rejectedCandidateURL: String?,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.status = status
        self.baselineSHA256 = baselineSHA256
        self.candidateSHA256 = candidateSHA256
        self.allowedParts = allowedParts
        self.changedParts = changedParts
        self.layer1 = layer1
        self.layer2 = layer2
        self.layer3 = layer3
        self.verify = verify
        self.outputURL = outputURL
        self.rejectedCandidateURL = rejectedCandidateURL
        self.createdAt = createdAt
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // `.secondsSince1970` (not `.iso8601`): Foundation's ISO 8601
        // formatter rounds to whole or millisecond-fractional seconds, so a
        // `Date()` with sub-millisecond precision does not round-trip
        // exactly through it — `testJSONRoundTripPreservesEveryField`
        // caught this. The JSON number itself round-trips the `Double`
        // exactly; converting it back to a `Date` can still differ from
        // the original by ~1 ULP, because `Date`'s native storage is an
        // offset from 2001 and the JSON number is an offset from 1970 —
        // see `CertificateTests.assertRoundTripsIgnoringTimestampULP`.
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    public func encoded() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    // MARK: - Codable
    //
    // Hand-written, not auto-synthesized: the compiler-synthesized
    // `Encodable` for a struct uses `encodeIfPresent` for `Optional`
    // properties, which OMITS the JSON key entirely when the value is
    // `nil`. design.md's Implementation Contract lists `outputURL` and
    // `rejectedCandidateURL` as fields that are always present (null when
    // absent) — `testTopLevelKeyNamesMatchImplementationContract` checks
    // exactly this. Decoding stays lenient (`decodeIfPresent`) so a
    // certificate that omits the key (an older producer, or one written by
    // a future schema version's superset) still decodes.

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, status, baselineSHA256, candidateSHA256
        case allowedParts, changedParts, layer1, layer2, layer3, verify
        case outputURL, rejectedCandidateURL, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        status = try container.decode(CertificationStatus.self, forKey: .status)
        baselineSHA256 = try container.decode(String.self, forKey: .baselineSHA256)
        candidateSHA256 = try container.decode(String.self, forKey: .candidateSHA256)
        allowedParts = try container.decode([String].self, forKey: .allowedParts)
        changedParts = try container.decode([String].self, forKey: .changedParts)
        layer1 = try container.decode(Layer1CertificateSection.self, forKey: .layer1)
        layer2 = try container.decode(NotEvaluatedLayer.self, forKey: .layer2)
        layer3 = try container.decode(NotEvaluatedLayer.self, forKey: .layer3)
        verify = try container.decode(VerifyOutcome.self, forKey: .verify)
        outputURL = try container.decodeIfPresent(String.self, forKey: .outputURL)
        rejectedCandidateURL = try container.decodeIfPresent(String.self, forKey: .rejectedCandidateURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
        try container.encode(baselineSHA256, forKey: .baselineSHA256)
        try container.encode(candidateSHA256, forKey: .candidateSHA256)
        try container.encode(allowedParts, forKey: .allowedParts)
        try container.encode(changedParts, forKey: .changedParts)
        try container.encode(layer1, forKey: .layer1)
        try container.encode(layer2, forKey: .layer2)
        try container.encode(layer3, forKey: .layer3)
        try container.encode(verify, forKey: .verify)
        try container.encode(outputURL, forKey: .outputURL)
        try container.encode(rejectedCandidateURL, forKey: .rejectedCandidateURL)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
