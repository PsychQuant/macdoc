import Foundation

/// Deterministic, cross-process-stable content fingerprint of a paragraph's
/// visible run text. Used by `Tier3MetadataRestorer` to verify that a
/// `ParagraphMeta.index` in the Tier 3 metadata sidecar still points at the
/// paragraph it was captured against, before applying that entry's
/// formatting (PsychQuant/macdoc#220 item 5).
///
/// ## Contract with word-to-md-swift's forward copy (CRITICAL — keep both in sync)
///
/// word-to-md-swift's `Sources/WordToMD/ParagraphFingerprint.swift` carries
/// an independent, hand-duplicated copy of this exact algorithm — the two
/// packages are separate Swift modules in separate repos with no shared
/// dependency to host a common implementation in. Both files' test suites
/// pin the SAME literal hex digests as expected values for the SAME input
/// strings (`ParagraphFingerprintTests.swift` in both repos). If you change
/// the normalization rule or the hash algorithm here, you MUST make the
/// identical change on the word-to-md-swift side and update both sets of
/// literal test vectors together, or a fingerprint written by that package
/// will never match one recomputed here — silently defeating the whole
/// feature (every restoration would look like a mismatch, and
/// `Tier3MetadataRestorer` would report `.fingerprintMismatch` for entries
/// that actually still line up).
///
/// ## What text this is computed over
///
/// The concatenation of `paragraph.runs.map(\.text)`, in run order — the
/// same restricted "top-level runs only" text that `RunMeta.range` offsets
/// are defined against on the forward side (word-to-md-swift's
/// `MetadataCollector`). `Tier3MetadataRestorer` computes this identically
/// over the freshly-converted paragraph's own `runs` before comparing
/// against `ParagraphMeta.textFingerprint`.
///
/// ## Normalization
///
/// 1. Unicode NFC normalize (`precomposedStringWithCanonicalMapping`).
/// 2. **Typographic canonicalization**: fold "smart punctuation" variants
///    down to their plain-ASCII equivalents — curly single/double quotes to
///    `'`/`"`, en dash (U+2013) to `--`, em dash (U+2014) to `---`,
///    horizontal ellipsis (U+2026) to `...`. This step exists because
///    swift-markdown's `Document(parsing:)` (used by
///    `MarkdownToWordConverter`, no `.disableSmartOpts` passed) enables
///    cmark's "smart" option set by default: parsing markdown containing a
///    literal straight apostrophe/quote, or an ASCII `--`/`---`/`...`
///    sequence, silently rewrites it to the corresponding Unicode
///    typographic character. Without folding both forms to the same
///    canonical ASCII representation, the fingerprint would mismatch on
///    nearly every ordinary paragraph containing a contraction or
///    possessive — verified empirically by round-tripping
///    `"This paragraph's real text."` through `convertMarkdown` and
///    observing the straight `'` come back as U+2019. See the
///    word-to-md-swift copy's doc comment for the full rationale,
///    including the documented residual gap (this canonicalization is
///    intentionally lossy: a literal Unicode em dash and a literal `---`
///    now fingerprint identically).
/// 3. Collapse every run of Unicode whitespace/newline characters to a
///    single ASCII space.
/// 4. Trim leading/trailing whitespace.
/// 5. Hash the normalized text with FNV-1a (64-bit), rendered as 16
///    lowercase hex digits.
enum ParagraphFingerprint {
    /// Unicode "smart punctuation" scalar → canonical ASCII replacement.
    /// Must exactly mirror word-to-md-swift's copy — see that file's doc
    /// comment for why each entry exists.
    private static let typographicCanonicalization: [Unicode.Scalar: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{201B}": "'", // single quote family
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{201F}": "\"", // double quote family
        "\u{2013}": "--",   // en dash
        "\u{2014}": "---",  // em dash
        "\u{2026}": "...",  // horizontal ellipsis
    ]

    static func compute(_ runsText: String) -> String {
        fnv1a64Hex(normalize(runsText))
    }

    static func normalize(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        var result = ""
        result.reserveCapacity(nfc.count)
        var lastWasWhitespace = false
        for scalar in nfc.unicodeScalars {
            if let replacement = typographicCanonicalization[scalar] {
                result += replacement
                lastWasWhitespace = false
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasWhitespace {
                    result.unicodeScalars.append(" ")
                }
                lastWasWhitespace = true
            } else {
                result.unicodeScalars.append(scalar)
                lastWasWhitespace = false
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fnv1a64Hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(format: "%016llx", hash)
    }
}
