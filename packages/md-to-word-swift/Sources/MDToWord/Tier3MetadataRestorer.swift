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
/// ## Two fingerprint gates for two different guarantees (PsychQuant/macdoc#220
/// item 5, extended by a follow-up finding during item 4's implementation —
/// see `ParagraphFingerprint`'s doc comment for the full rationale)
///
/// A `ParagraphMeta` entry MAY carry `textFingerprint` (loose,
/// whitespace/typography-tolerant) and/or `exactTextFingerprint`
/// (byte-exact) — content-addressed hashes of the *original* paragraph's
/// run text. **They gate different things and must not be conflated**: a
/// loose-fingerprint match only proves "this is still roughly the same
/// paragraph" (fine for alignment/spacing/etc., which don't depend on
/// character positions); it does NOT prove `RunMeta.range` character
/// offsets are still valid, because the loose fingerprint's normalization
/// (whitespace collapsing, typographic canonicalization) is
/// length-changing.
///
/// **Paragraph-level fields** are gated on `textFingerprint`:
/// - **Match** → applied.
/// - **Mismatch** → positive evidence that `meta.index` no longer points at
///   the paragraph it was captured against (e.g. the markdown was
///   hand-edited and an earlier paragraph was inserted, shifting every
///   later index by one). The *entire* entry is skipped — paragraph-level
///   fields AND `runs` both — recorded in the returned
///   `Tier3RestorationReport` as `.fingerprintMismatch`. This is the fix
///   for the failure mode #220 was opened to close: previously an index
///   collision like this would apply formatting to the wrong paragraph
///   with no warning at all.
/// - **Absent** (`textFingerprint == nil`) → the sidecar predates
///   word-to-md-swift ≥ 1.1.0 (or was hand-constructed, as most of this
///   package's own unit tests do). Falls back to the pre-#220 behavior:
///   apply unconditionally by position, matching #206's original (and
///   still-supported) contract.
///
/// **`runs`** are gated on `exactTextFingerprint` independently, with no
/// backward-compat fallback in any case (restoring `runs` is new in #220
/// and never had an established "trust the index blindly" behavior to
/// preserve):
/// - **Present and matching** → `applyRunFormatting` runs; the current
///   paragraph's run text is proven byte-identical to what `RunMeta.range`
///   was captured against, so the offsets are safe.
/// - **Absent, or present but not matching** → `runs` are left untouched,
///   recorded in the report as `.exactFingerprintMismatchOrAbsent`. This
///   still leaves the entry's paragraph-level fields applied (if the loose
///   gate above passed) — only `runs` specifically are withheld.
///
/// ## Per-run formatting (PsychQuant/macdoc#220 item 4)
///
/// `RunMeta.range` is a `[start, end)` character-offset pair into the
/// concatenation of the *original* paragraph's `runs` — the same text
/// `exactTextFingerprint` above is computed over. Once that fingerprint
/// confirms the current paragraph's run text is byte-identical, those same
/// offsets are valid against the current paragraph's own runs (regardless
/// of how the markdown-only conversion happened to segment them):
/// `applyRunFormatting` splits the current `runs` at every metadata range's
/// boundaries and applies each entry's formatting to the segments that fall
/// fully inside its range. See that function's doc comment for the
/// splitting algorithm.
///
/// ## Deliberately NOT restored (evaluated for #220, declined — documented,
/// not silently dropped)
///
/// - **`commentIds`** and **`bookmarkNames`**: the decisive blocker for
///   both is the same, and it is more fundamental than any position-model
///   complexity below — **`ParagraphMeta` does not carry the original
///   range endpoints at all.** `collectParagraph` (word-to-md-swift) only
///   ever records *which* comment ids / bookmark names touched a paragraph
///   (`para.commentIds` / `para.bookmarks.map(\.name)`), never *where*
///   within the paragraph's text they started or ended. No amount of
///   restorer-side cleverness can reconstruct a range that was never
///   captured — this is a sidecar-schema gap, not (only) a restorer
///   limitation, and the concrete first step of a follow-up is extending
///   `MetadataCollector`/`ParagraphMeta` to capture that range in the first
///   place (analogous to how `RunMeta.range` already does for run
///   formatting).
///   - A secondary complication, layered on top of the missing-range
///     problem once range capture existed: OOXMLSwift's
///     `CommentRangeMarker.position` / `BookmarkRangeMarker.position` are
///     indices into the *interleaved* emission order of ALL paragraph
///     children (runs, hyperlinks, SDTs, footnote/endnote references,
///     other range markers) — not a character offset — so translating a
///     captured position into the character-offset universe this restorer
///     already uses for `runs` would require walking that full interleaved
///     order (including nested hyperlink/SDT text, which `RunMeta`'s
///     existing offsets deliberately exclude). No such utility exists in
///     word-to-md-swift or OOXMLSwift today.
///   - Comment reconstruction additionally needs to *insert* new marker
///     nodes into a run sequence built by unrelated markdown-parsing code —
///     an insertion, not the property-overlay-on-existing-runs this
///     restorer already does for `runs`.
///   - Minting fresh bookmark ids is comparatively low-risk *today*
///     (`MarkdownToWordConverter` does not currently mint any bookmark ids
///     of its own, so there is no existing collision source) — but that
///     was never the limiting factor; the missing-range-data blocker above
///     applies equally to bookmarks.
///   - This is left as a follow-up, not ruled out permanently: the concrete
///     unblocking path is (1) extend the sidecar schema to capture range
///     endpoints, (2) build the interleaved-position-to-character-offset
///     utility (belongs upstream in OOXMLSwift as a reusable primitive, not
///     duplicated ad hoc here), (3) extend `Tier3MetadataRestorer` to insert
///     the reconstructed markers/comments once (1) and (2) both exist.
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

            let rawRunsText = paragraph.runs.map(\.text).joined()

            if let expectedLooseFingerprint = meta.textFingerprint {
                guard ParagraphFingerprint.compute(rawRunsText) == expectedLooseFingerprint else {
                    report.skipped.append(Tier3RestorationReport.SkippedEntry(index: meta.index, reason: .fingerprintMismatch))
                    continue
                }
            }

            apply(meta, to: &paragraph.properties)

            if !meta.runs.isEmpty {
                // Per-run restoration is gated on the byte-exact fingerprint
                // ONLY — never on the loose one above, and never as an
                // "old sidecar, trust it anyway" fallback. See
                // `ParagraphFingerprint`'s doc comment on why the loose
                // fingerprint's normalization cannot guarantee
                // `RunMeta.range` offsets are still valid.
                if let expectedExactFingerprint = meta.exactTextFingerprint,
                   ParagraphFingerprint.computeExact(rawRunsText) == expectedExactFingerprint {
                    applyRunFormatting(meta.runs, to: &paragraph.runs)
                } else {
                    report.runsSkipped.append(Tier3RestorationReport.RunsSkippedEntry(
                        index: meta.index,
                        reason: .exactFingerprintMismatchOrAbsent
                    ))
                }
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

    /// Splits `runs` at every `runMetas` entry's `[start, end)` boundary —
    /// measured in **Unicode scalars**, matching `RunMeta.range`'s
    /// definition on the forward side (word-to-md-swift's
    /// `MetadataCollector`) — and applies that entry's formatting to every
    /// resulting segment fully contained within its range.
    ///
    /// ## Why Unicode scalars, not Swift `Character`s (Codex round 2 NEW-1)
    ///
    /// Swift `Character` (extended grapheme cluster) counts are NOT
    /// additive across a string boundary: a combining-character sequence
    /// (base + combining mark) split across two separately-formatted runs
    /// counts as 2 `Character`s when each run's text is measured in
    /// isolation, but merges into a single `Character` if those runs are
    /// later coalesced into one (e.g. by this restorer's own markdown-based
    /// reconstruction, which segments runs independently of the original
    /// document). Offsets computed by summing per-run `Character` counts on
    /// the forward side can therefore silently disagree with a `Character`
    /// count taken against the current, differently-segmented `runs` — even
    /// when the paragraph's exact-fingerprint-verified text is
    /// byte-identical. Unicode scalars have no such merging behavior:
    /// concatenating scalar sequences and counting scalars always equals
    /// the sum of the pieces' own scalar counts, independent of where run
    /// boundaries fall on either side. Using scalar-based offsets
    /// throughout (forward computation AND this splitting algorithm)
    /// eliminates the whole class of drift, rather than only detecting it.
    ///
    /// ## Algorithm
    ///
    /// 1. Collect every entry's `start`/`end` scalar offset (clamped to the
    ///    paragraph's total run-text scalar count) into a sorted,
    ///    deduplicated boundary set.
    /// 2. Walk `runs` in order, splitting each run's `.text` at any
    ///    boundary that falls strictly inside it (via
    ///    `String.unicodeScalars`, reassembled through
    ///    `String.UnicodeScalarView`), producing a flat list of
    ///    `(scalarRange, Run)` segments — each segment initially a copy of
    ///    its parent run (same properties, sliced text). A run carrying a
    ///    `drawing` (image) is passed through as a single un-split segment
    ///    regardless of boundaries landing inside its (zero-length text)
    ///    span, since mutating an image run's `rPr` is not a meaningful
    ///    operation here.
    /// 3. For each `runMetas` entry, apply its formatting to every segment
    ///    whose scalar range is fully contained in `[start, end)`.
    ///
    /// Callers (`restore(_:onto:)`) only invoke this after confirming the
    /// paragraph's *byte-exact* fingerprint matches, so the offsets are
    /// guaranteed valid against `runs`' own concatenated text — this
    /// function does not re-verify that itself, only clamps individual
    /// out-of-bounds ranges defensively.
    private static func applyRunFormatting(_ runMetas: [RunMeta], to runs: inout [Run]) {
        guard !runMetas.isEmpty, !runs.isEmpty else { return }

        let totalLength = runs.reduce(0) { $0 + $1.text.unicodeScalars.count }
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
            let runScalars = Array(run.text.unicodeScalars)
            let runEnd = cursor + runScalars.count
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

            var pieceStart = runStart
            for boundary in innerBoundaries {
                var piece = run
                piece.text = String(String.UnicodeScalarView(runScalars[(pieceStart - runStart)..<(boundary - runStart)]))
                segments.append((pieceStart..<boundary, piece))
                pieceStart = boundary
            }
            var lastPiece = run
            lastPiece.text = String(String.UnicodeScalarView(runScalars[(pieceStart - runStart)..<(runEnd - runStart)]))
            segments.append((pieceStart..<runEnd, lastPiece))
        }

        // Apply each entry's formatting to every fully-contained,
        // non-empty, non-drawing segment. The emptiness check matters at a
        // shared boundary: a zero-length segment sitting exactly at a
        // metadata range's edge would otherwise satisfy the containment
        // test (`lowerBound >= start && upperBound <= end` holds trivially
        // when lowerBound == upperBound) and pick up formatting from
        // whichever entry's range happens to end/start there, even though
        // it carries no text.
        for (start, end, meta) in normalizedRanges {
            for index in segments.indices {
                let segmentRange = segments[index].range
                guard !segmentRange.isEmpty else { continue }
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

    /// Closed enumeration of every reason a `ParagraphMeta`'s `runs` were
    /// NOT applied, distinct from `SkipReason` above: these entries still
    /// count toward `appliedCount` (their paragraph-level fields DID apply
    /// — `SkipReason` is reserved for when the WHOLE entry was skipped).
    public enum RunsSkipReason: Hashable {
        /// `ParagraphMeta.exactTextFingerprint` was nil (sidecar predates
        /// this field, or `runs` were hand-populated without it) or did not
        /// match the current paragraph's recomputed byte-exact fingerprint.
        /// Either way, `RunMeta.range` character offsets are not proven
        /// safe to apply — see `ParagraphFingerprint`'s doc comment for why
        /// a *loose* fingerprint match is not sufficient for this. This is
        /// never a fallback-and-apply situation, unlike paragraph-level
        /// fields on a fingerprint-less old sidecar: per-run restoration is
        /// new in #220 and has no established "trust it anyway" behavior to
        /// preserve.
        case exactFingerprintMismatchOrAbsent
    }

    public struct RunsSkippedEntry: Hashable {
        public let index: Int
        public let reason: RunsSkipReason

        public init(index: Int, reason: RunsSkipReason) {
            self.index = index
            self.reason = reason
        }
    }

    /// Number of `ParagraphMeta` entries that had at least their
    /// paragraph-level fields applied. An entry counted here MAY still have
    /// its `runs` skipped — check `runsSkipped` for that.
    public var appliedCount: Int = 0
    public var skipped: [SkippedEntry] = []
    public var runsSkipped: [RunsSkippedEntry] = []

    public init(appliedCount: Int = 0, skipped: [SkippedEntry] = [], runsSkipped: [RunsSkippedEntry] = []) {
        self.appliedCount = appliedCount
        self.skipped = skipped
        self.runsSkipped = runsSkipped
    }
}
