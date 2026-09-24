import XCTest
@testable import MDToWord

/// Characterization tests for `ParagraphFingerprint` (PsychQuant/macdoc#220
/// item 5). These literal expected hex digests are the shared contract with
/// word-to-md-swift's independent mirror copy
/// (`Sources/WordToMD/ParagraphFingerprint.swift`, whose test suite pins the
/// identical vectors). If this test file's expectations ever need to
/// change, the word-to-md-swift-side copy of both the algorithm and its
/// test vectors must change identically in the same release cycle — see the
/// doc comment on `ParagraphFingerprint` for why.
final class ParagraphFingerprintTests: XCTestCase {

    // MARK: - Shared literal test vectors (cross-repo contract)

    func testFingerprintOfPlainASCIIText() {
        XCTAssertEqual(ParagraphFingerprint.compute("Hello, world!"), "38d1334144987bf4")
    }

    func testFingerprintCollapsesInteriorWhitespace() {
        XCTAssertEqual(ParagraphFingerprint.compute("café  naïve   text"), "f3e75da59db3cbf4")
    }

    func testFingerprintTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(ParagraphFingerprint.compute("  leading and trailing space  "), "4fd2d393b0def7d6")
    }

    func testFingerprintCollapsesNewlinesAndTabs() {
        XCTAssertEqual(ParagraphFingerprint.compute("line1\nline2\ttabbed"), "fa9bc3e805bb5524")
    }

    func testFingerprintOfEmptyString() {
        XCTAssertEqual(ParagraphFingerprint.compute(""), "cbf29ce484222325")
    }

    func testFingerprintOfSingleWord() {
        XCTAssertEqual(ParagraphFingerprint.compute("important"), "4f2844fb7985d8e5")
    }

    // MARK: - Typographic canonicalization (swift-markdown's default "smart
    // punctuation" — see ParagraphFingerprint's doc comment)

    func testFingerprintCanonicalizesApostrophe() {
        XCTAssertEqual(ParagraphFingerprint.compute("This paragraph's real text."), "dea38bc387d1a018")
    }

    func testFingerprintOfCurlyApostropheMatchesStraightApostrophe() {
        XCTAssertEqual(
            ParagraphFingerprint.compute("This paragraph\u{2019}s real text."),
            "dea38bc387d1a018"
        )
    }

    func testFingerprintCanonicalizesDashesAndEllipsisAndDoubleQuotes() {
        XCTAssertEqual(
            ParagraphFingerprint.compute("He said \"hello\" -- then left..."),
            "a00291c1039d1aab"
        )
    }

    func testFingerprintOfFullyTypographicVariantMatchesASCIIVariant() {
        XCTAssertEqual(
            ParagraphFingerprint.compute("He said \u{201C}hello\u{201D} \u{2013} then left\u{2026}"),
            "a00291c1039d1aab"
        )
    }

    // MARK: - Content-drift sensitivity

    func testDifferentTextProducesDifferentFingerprint() {
        XCTAssertNotEqual(
            ParagraphFingerprint.compute("First paragraph."),
            ParagraphFingerprint.compute("Second paragraph.")
        )
    }

    func testSameTextProducesSameFingerprintDeterministically() {
        let text = "Repeat this exact sentence."
        XCTAssertEqual(ParagraphFingerprint.compute(text), ParagraphFingerprint.compute(text))
    }

    // MARK: - Whitespace-only edits do NOT change the fingerprint

    func testWhitespaceOnlyDifferenceProducesSameFingerprint() {
        XCTAssertEqual(
            ParagraphFingerprint.compute("Same   content"),
            ParagraphFingerprint.compute("Same content")
        )
        XCTAssertEqual(
            ParagraphFingerprint.compute("Trailing space "),
            ParagraphFingerprint.compute("Trailing space")
        )
    }
}
