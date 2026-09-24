import Foundation
import OOXMLSwift

/// Restores Tier 3 metadata-sidecar fields back onto the paragraphs of a
/// freshly-converted `WordDocument`, keyed by `ParagraphMeta.index` — the
/// same index the forward converter (`MetadataCollector.collectElement`,
/// word-to-md-swift's `WordConverter`) assigns while walking
/// `document.body.children` during a `.marker` fidelity pass. See
/// PsychQuant/macdoc#206 / #155 / #220.
///
/// ## Scope: which fields are restored
///
/// Paragraph-level formatting fields whose target `ParagraphProperties`
/// slot is self-contained — no referential integrity to other document
/// state: `alignment`, `spacing` (including `lineRule`, PsychQuant/macdoc#220
/// item 1), `indentation`, `keepNext`, `keepLines`, `pageBreakBefore`,
/// `border`, `shading`. Plus, since #220 item 4, per-run formatting
/// (`RunMeta` — font/size/color/highlight/underline/characterSpacing),
/// gated on a paragraph text-fingerprint match (see below).
///
/// ## Composite fields (`spacing`/`indentation`/`border`/`shading`) are
/// ## whole-value snapshots, not sparse per-field patches
///
/// When `ParagraphMeta.spacing` (etc.) is non-nil, the *entire* target
/// property is replaced with a freshly-built value from the sidecar's
/// sub-fields — it is not merged sub-field-by-sub-field onto whatever the
/// markdown-only conversion already produced. This matches how the forward
/// collector fills these fields: `MetadataCollector.collectParagraph`
/// (word-to-md-swift) snapshots `SpacingMeta`/`IndentationMeta` directly
/// from the *original* docx paragraph's `Spacing`/`Indentation` struct in
/// one shot — a sidecar entry represents "this is what the original
/// paragraph's spacing was" (which sub-fields the original had is a real
/// fact, not a patch instruction), not "here is a partial edit to overlay
/// on top of whatever the reverse converter happens to produce". Replacing
/// the whole target value is therefore the more faithful restoration: if
/// the original paragraph had no explicit `line` spacing, forcing the
/// markdown-only conversion's own invented default (`line: 276,
/// lineRule: .auto`, from `MarkdownWordBuilder`) to survive would reproduce
/// something the source document never had, not restore it.
///
/// ## Paragraph text-fingerprint gate (PsychQuant/macdoc#220 item 5)
///
/// Every `ParagraphMeta` entry MAY carry a `textFingerprint` — a
/// content-addressed hash of the *original* paragraph's run text (see
/// `ParagraphFingerprint`). When present, this restorer recomputes the same
/// fingerprint over the *current* body child at `meta.index`'s run text and
/// compares:
///
/// - **Match** → the entry is trusted; both paragraph-level fields and
///   per-run formatting (if any) are applied.
/// - **Mismatch** → positive evidence that `meta.index` no longer points at
///   the paragraph it was captured against (e.g. the markdown was
///   hand-edited and an earlier paragraph was inserted, shifting every
///   later index by one). The *entire* entry is skipped — paragraph-level
///   fields included, not just `runs` — and the skip is recorded in the
///   `Tier3RestorationReport` returned by `restore(_:onto:)` as
///   `.fingerprintMismatch`. This is the fix for the failure mode #220 was
///   opened to close: previously an index collision like this would apply
///   formatting to the wrong paragraph with no warning at all.
/// - **Absent** (`textFingerprint == nil`) → the sidecar predates
///   word-to-md-swift ≥ 1.1.0 (or was hand-constructed, as most of this
///   package's own unit tests do). Paragraph-level fields fall back to the
///   pre-#220 behavior: apply unconditionally by position, matching #206's
///   original (and still-supported) contract. **Per-run formatting is the
///   one exception**: since restoring `runs` is new in #220 and never had
///   an established "trust the index blindly" behavior to preserve, it is
///   applied ONLY when a fingerprint is present AND matches — never as a
///   backward-compat fallback. A sidecar with `runs` populated but no
///   `textFingerprint` behaves exactly as it did before #220: `runs` are
///   left untouched.
///
/// ## Per-run formatting (PsychQuant/macdoc#220 item 4)
///
/// `RunMeta.range` is a `[start, end)` character-offset pair into the
/// concatenation of the *original* paragraph's `runs` — the same text the
/// fingerprint above is computed over. Once the fingerprint confirms the
/// current paragraph's run text is identical, those same offsets are valid
/// against the current paragraph's own runs (regardless of how the
/// markdown-only conversion happened to segment them): `applyRunFormatting`
/// splits the current `runs` at every metadata range's boundaries and
/// applies each entry's formatting to the segments that fall fully inside
/// its range. See that function's doc comment for the splitting algorithm.
///
/// ## Deliberately NOT restored (evaluated for #220, declined — documented,
/// not silently dropped)
///
/// - **`commentIds`**: reconstructing a comment requires re-creating the
///   `Comment` (author/text) from `DocumentMetadata.document.comments` *and*
///   re-establishing the `<w:commentRangeStart/End>` wrapper at the correct
///   position. OOXMLSwift's `CommentRangeMarker.position` is an index into
///   the *interleaved* emission order of ALL paragraph children (runs,
///   hyperlinks, SDTs, footnote/endnote references, other range markers) —
///   not a character offset — so translating it into the character-offset
///   universe this restorer already uses for `runs` would require walking
///   that full interleaved order (including nested hyperlink/SDT text,
///   which `RunMeta`'s existing offsets deliberately exclude) to compute
///   cumulative visible-text length. No such utility exists in
///   word-to-md-swift or OOXMLSwift today; building one is materially more
///   work than the `runs` case (which only ever deals with plain top-level
///   `Run`s) and belongs upstream as a reusable primitive, not duplicated
///   ad hoc here. Comment reconstruction also needs to *insert* new marker
///   nodes into a run sequence built by unrelated markdown-parsing code —
///   an insertion, not the property-overlay-on-existing-runs this restorer
///   already does for `runs`. `ParagraphMeta` also does not carry the range
///   information needed to place the markers correctly even if the position
///   model were solved. Left as a follow-up.
/// - **`bookmarkNames`**: names survive in the sidecar, but not the original
///   numeric ids, and Word requires document-unique bookmark ids. Minting
///   fresh ids is low-risk *today* (`MarkdownToWordConverter` does not
///   currently mint any bookmark ids of its own — no collision source
///   exists yet), but restoring bookmarks hits the exact same
///   position-model blocker as comments above (`BookmarkRangeMarker`'s
///   `position` is the same interleaved-order index), so id-minting safety
///   is not actually the limiting factor. Left as a follow-up alongside
///   comments, since solving the position-model problem once would unblock
///   both.
///
/// ## Index-mismatch policy (unchanged from #206, extended with the
/// ## fingerprint gate above)
///
/// A `ParagraphMeta.index` that is out of range for `document.body.children`,
/// or that lands on a non-`.paragraph` body child (e.g. `.table`), is
/// **skipped** — no error is thrown, and no other metadata entry is
/// affected. This is recorded in the returned `Tier3RestorationReport` as
/// `.indexOutOfRange` / `.indexNotAParagraph` respectively (#220 item 5 —
/// these were silent before, now they are reported; the underlying
/// skip-and-continue behavior is unchanged from #206).
enum Tier3MetadataRestorer {
    @discardableResult
    static func restore(_ metadata: DocumentMetadata, onto document: inout WordDocument) -> Tier3RestorationReport {
        var report = Tier3RestorationReport()

        for meta in metadata.paragraphs {
            guard meta.index >= 0, meta.index < document.body.children.count else {
                report.skipped.append(Tier3RestorationReport.SkippedEntry(index: meta.index, reason: .indexOutOfRange))
                continue
            }
            guard case .paragraph(var paragraph) = document.body.children[meta.index] else {
                report.skipped.append(Tier3RestorationReport.SkippedEntry(index: meta.index, reason: .indexNotAParagraph))
                continue
            }

            var fingerprintConfirmedMatch = false
            if let expectedFingerprint = meta.textFingerprint {
                let actualText = paragraph.runs.map(\.text).joined()
                let actualFingerprint = ParagraphFingerprint.compute(actualText)
                guard actualFingerprint == expectedFingerprint else {
                    report.skipped.append(Tier3RestorationReport.SkippedEntry(index: meta.index, reason: .fingerprintMismatch))
                    continue
                }
                fingerprintConfirmedMatch = true
            }

            apply(meta, to: &paragraph.properties)
            if fingerprintConfirmedMatch, !meta.runs.isEmpty {
                applyRunFormatting(meta.runs, to: &paragraph.runs)
            }

            document.body.children[meta.index] = .paragraph(paragraph)
            report.appliedCount += 1
        }

        return report
    }

    private static func apply(_ meta: ParagraphMeta, to properties: inout ParagraphProperties) {
        if let alignment = meta.alignment.flatMap(Alignment.init(rawValue:)) {
            properties.alignment = alignment
        }

        if let spacing = meta.spacing {
            properties.spacing = Spacing(
                before: spacing.before,
                after: spacing.after,
                line: spacing.line,
                lineRule: spacing.lineRule.flatMap(LineRule.init(rawValue:))
            )
        }

        if let indentation = meta.indentation {
            properties.indentation = Indentation(
                left: indentation.left,
                right: indentation.right,
                firstLine: indentation.firstLine,
                hanging: indentation.hanging
            )
        }

        if let keepNext = meta.keepNext {
            properties.keepNext = keepNext
        }

        if let keepLines = meta.keepLines {
            properties.keepLines = keepLines
        }

        if let pageBreakBefore = meta.pageBreakBefore {
            properties.pageBreakBefore = pageBreakBefore
        }

        if let border = meta.border {
            properties.border = ParagraphBorder(
                top: borderStyle(border.top),
                bottom: borderStyle(border.bottom),
                left: borderStyle(border.left),
                right: borderStyle(border.right)
            )
        }

        if let shading = meta.shading {
            properties.shading = ParagraphShading(
                fill: shading.fill,
                pattern: shading.pattern.flatMap(ShadingPattern.init(rawValue:))
            )
        }
    }

    private static func borderStyle(_ meta: BorderStyleMeta?) -> ParagraphBorderStyle? {
        guard let meta else { return nil }
        guard let type = ParagraphBorderType(rawValue: meta.type) else { return nil }
        return ParagraphBorderStyle(type: type, color: meta.color, size: meta.size)
    }

    // MARK: - Per-run formatting (PsychQuant/macdoc#220 item 4)

    /// Splits `runs` at every `runMetas` entry's `[start, end)` character
    /// boundary and applies that entry's formatting to every resulting
    /// segment fully contained within its range.
    ///
    /// ## Algorithm
    ///
    /// 1. Collect every entry's `start`/`end` offset (clamped to the
    ///    paragraph's total run-text length) into a sorted, deduplicated
    ///    boundary set.
    /// 2. Walk `runs` in order, splitting each run's `.text` at any
    ///    boundary that falls strictly inside it, producing a flat list of
    ///    `(characterRange, Run)` segments — each segment initially a copy
    ///    of its parent run (same properties, sliced text). A run carrying
    ///    a `drawing` (image) is passed through as a single un-split
    ///    segment regardless of boundaries landing inside its (zero-length
    ///    text) span, since mutating an image run's `rPr` is not a
    ///    meaningful operation here.
    /// 3. For each `runMetas` entry, apply its formatting to every segment
    ///    whose character range is fully contained in `[start, end)`.
    ///
    /// Callers (`restore(_:onto:)`) only invoke this after confirming the
    /// paragraph's text-fingerprint matches, so the offsets are guaranteed
    /// valid against `runs`' own concatenated text — this function does not
    /// re-verify that itself, only clamps individual out-of-bounds ranges
    /// defensively.
    private static func applyRunFormatting(_ runMetas: [RunMeta], to runs: inout [Run]) {
        guard !runMetas.isEmpty, !runs.isEmpty else { return }

        let totalLength = runs.reduce(0) { $0 + $1.text.count }
        guard totalLength > 0 else { return }

        var boundaries = Set<Int>([0, totalLength])
        var normalizedRanges: [(start: Int, end: Int, meta: RunMeta)] = []
        for meta in runMetas {
            guard meta.range.count == 2 else { continue }
            let start = max(0, min(meta.range[0], totalLength))
            let end = max(start, min(meta.range[1], totalLength))
            guard start < end else { continue }
            boundaries.insert(start)
            boundaries.insert(end)
            normalizedRanges.append((start, end, meta))
        }
        guard !normalizedRanges.isEmpty else { return }

        // Split `runs` into segments at every boundary.
        var segments: [(range: Range<Int>, run: Run)] = []
        var cursor = 0
        for run in runs {
            let runStart = cursor
            let runEnd = cursor + run.text.count
            cursor = runEnd

            guard run.drawing == nil, runStart < runEnd else {
                // Zero-length run (e.g. a drawing/image run) — pass through
                // as a single segment; never a target for text-offset
                // formatting.
                segments.append((runStart..<runEnd, run))
                continue
            }

            let innerBoundaries = boundaries
                .filter { $0 > runStart && $0 < runEnd }
                .sorted()
            guard !innerBoundaries.isEmpty else {
                segments.append((runStart..<runEnd, run))
                continue
            }

            let characters = Array(run.text)
            var pieceStart = runStart
            for boundary in innerBoundaries {
                var piece = run
                piece.text = String(characters[(pieceStart - runStart)..<(boundary - runStart)])
                segments.append((pieceStart..<boundary, piece))
                pieceStart = boundary
            }
            var lastPiece = run
            lastPiece.text = String(characters[(pieceStart - runStart)..<(runEnd - runStart)])
            segments.append((pieceStart..<runEnd, lastPiece))
        }

        // Apply each entry's formatting to every fully-contained segment.
        for (start, end, meta) in normalizedRanges {
            for index in segments.indices {
                let segmentRange = segments[index].range
                guard segments[index].run.drawing == nil else { continue }
                guard segmentRange.lowerBound >= start, segmentRange.upperBound <= end else { continue }
                applyRunProperties(meta, to: &segments[index].run.properties)
            }
        }

        runs = segments.map(\.run)
    }

    private static func applyRunProperties(_ meta: RunMeta, to properties: inout RunProperties) {
        if let fontName = meta.fontName {
            properties.fontName = fontName
        }
        if let fontSize = meta.fontSize {
            properties.fontSize = fontSize
        }
        if let color = meta.color {
            properties.color = color
        }
        if let highlight = meta.highlightColor.flatMap(HighlightColor.init(rawValue:)) {
            properties.highlight = highlight
        }
        if let underline = meta.underlineType.flatMap(UnderlineType.init(rawValue:)) {
            properties.underline = underline
        }
        if let characterSpacing = meta.characterSpacing {
            properties.characterSpacing = CharacterSpacing(
                spacing: characterSpacing.spacing,
                position: characterSpacing.position,
                kern: characterSpacing.kern
            )
        }
    }
}

// MARK: - Tier3RestorationReport

/// Outcome of a `Tier3MetadataRestorer.restore(_:onto:)` call — how many
/// sidecar entries were applied, and which were skipped and why
/// (PsychQuant/macdoc#220 item 5: "不再默默套錯" — mismatches are reported,
/// not silently absorbed).
public struct Tier3RestorationReport: Equatable {
    /// Closed enumeration of every reason an entry can be skipped. Callers
    /// MUST NOT infer additional cases by analogy — if a new skip condition
    /// is ever added to `Tier3MetadataRestorer`, it gets its own case here.
    public enum SkipReason: Hashable {
        /// `ParagraphMeta.index` is negative or ≥ `document.body.children.count`.
        case indexOutOfRange
        /// `ParagraphMeta.index` is in range but the body child there is not
        /// a `.paragraph` (e.g. a `.table`).
        case indexNotAParagraph
        /// `ParagraphMeta.textFingerprint` was present but did not match the
        /// current paragraph's recomputed fingerprint — positive evidence
        /// the index no longer points at the paragraph this entry was
        /// captured against. The entire entry (paragraph-level fields and
        /// any `runs`) was skipped, not just the mismatched part.
        case fingerprintMismatch
    }

    public struct SkippedEntry: Hashable {
        public let index: Int
        public let reason: SkipReason

        public init(index: Int, reason: SkipReason) {
            self.index = index
            self.reason = reason
        }
    }

    /// Number of `ParagraphMeta` entries that were applied (paragraph-level
    /// fields at minimum; `runs` too when the fingerprint gate allowed it).
    public var appliedCount: Int = 0
    public var skipped: [SkippedEntry] = []

    public init(appliedCount: Int = 0, skipped: [SkippedEntry] = []) {
        self.appliedCount = appliedCount
        self.skipped = skipped
    }
}
