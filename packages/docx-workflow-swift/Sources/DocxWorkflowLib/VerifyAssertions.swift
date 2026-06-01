// VerifyAssertions.swift — §2.3 of macdoc-docx-workflow-cli.
//
// Phase 1 post-condition catalog. Decoder uses snake_case JSON keys.
// All fields optional — a manifest's `verify` block may carry any subset.
// Evaluation lives in Verifier (§5.1).

import Foundation

public struct VerifyAssertions: Codable, Equatable {
    public let expectedImages: Int?
    public let expectedParagraphsMin: Int?
    public let expectedBookmarksMin: Int?
    public let libxml2Valid: Bool?
    public let bytePreservedParts: [String]?

    public init(
        expectedImages: Int? = nil,
        expectedParagraphsMin: Int? = nil,
        expectedBookmarksMin: Int? = nil,
        libxml2Valid: Bool? = nil,
        bytePreservedParts: [String]? = nil
    ) {
        self.expectedImages = expectedImages
        self.expectedParagraphsMin = expectedParagraphsMin
        self.expectedBookmarksMin = expectedBookmarksMin
        self.libxml2Valid = libxml2Valid
        self.bytePreservedParts = bytePreservedParts
    }

    private enum CodingKeys: String, CodingKey {
        case expectedImages = "expected_images"
        case expectedParagraphsMin = "expected_paragraphs_min"
        case expectedBookmarksMin = "expected_bookmarks_min"
        case libxml2Valid = "libxml2_valid"
        case bytePreservedParts = "byte_preserved_parts"
    }
}
