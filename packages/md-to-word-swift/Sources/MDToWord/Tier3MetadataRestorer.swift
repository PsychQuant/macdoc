import Foundation
import OOXMLSwift

/// Restores Tier 3 metadata-sidecar fields back onto the paragraphs of a
/// freshly-converted `WordDocument`, keyed by `ParagraphMeta.index` — the
/// same index the forward converter (`MetadataCollector.collectElement`,
/// word-to-md-swift's `WordConverter`) assigns while walking
/// `document.body.children` during a `.marker` fidelity pass. See
/// PsychQuant/macdoc#206 / #155.
///
/// ## Scope: which fields are restored
///
/// Only paragraph-level formatting fields whose target `ParagraphProperties`
/// slot is self-contained — no referential integrity to other document
/// state — are restored: `alignment`, `spacing`, `indentation`, `keepNext`,
/// `keepLines`, `pageBreakBefore`, `border`, `shading`.
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
/// One known consequence of this: `SpacingMeta` does not carry `lineRule`
/// at all (a pre-existing gap in word-to-md-swift's sidecar schema, not
/// introduced here), so restoring `spacing` always drops whatever
/// `lineRule` the markdown-only conversion had set, with no sidecar value
/// available to put back in its place. Extending the sidecar schema to
/// capture `lineRule` is out of scope for this package — the fix belongs in
/// word-to-md-swift's `MetadataCollector`/`SpacingMeta`, a separate repo and
/// a separate release.
///
/// ## Deliberately NOT restored (documented, not silently dropped)
///
/// - **`commentIds`**: reconstructing a comment requires re-creating the
///   `Comment` (author/text) from `DocumentMetadata.document.comments` *and*
///   re-establishing the `<w:commentRangeStart/End>` wrapper at the correct
///   run offsets. That crosses into document-level state this restorer does
///   not otherwise touch, and `ParagraphMeta` does not carry the range
///   information needed to place the markers correctly — left as a
///   follow-up.
/// - **`bookmarkNames`**: names survive in the sidecar, but not the original
///   numeric ids, and Word requires document-unique bookmark ids. Minting
///   fresh ids without colliding with ids the reverse converter's own
///   numbering/hyperlink machinery may already be using is future work.
/// - **`runs`** (per-run Tier 3 formatting — font/size/color/highlight/
///   underline/characterSpacing): `RunMeta.range` is a character-offset pair
///   captured against the *original* paragraph's run segmentation. The
///   freshly reverse-converted paragraph is not guaranteed to segment its
///   runs at the same offsets (run coalescing, math placeholders, etc. can
///   shift them), so indexing back in by raw offset risks silently
///   corrupting unrelated text. Left for a follow-up once a robust
///   text-offset-to-run mapping exists.
///
/// ## Index-mismatch policy
///
/// A `ParagraphMeta.index` that is out of range for `document.body.children`,
/// or that lands on a non-`.paragraph` body child (e.g. `.table`), is
/// **silently skipped** — no error is thrown, and no other metadata entry is
/// affected.
///
/// This is a deliberate choice, not an oversight: `MetadataReader.parse`
/// already treats the sidecar as sparse and best-effort (malformed entries
/// are dropped via `compactMap`, never surfaced as an error), and
/// `MetadataCollector`'s own doc-comment states the sidecar's "Sparse
/// Metadata 原則" explicitly. Throwing on any index drift would make the
/// ordinary "hand-edit the markdown, keep the old sidecar" workflow
/// unusable outright; this restorer instead applies whatever still lines up
/// and leaves the rest of the document exactly as the markdown-only
/// conversion produced it.
///
/// **What this policy does *not* protect against**: index matching is
/// purely positional. If the edited markdown still has *a* paragraph at
/// `ParagraphMeta.index` but it is no longer the *same* paragraph the
/// sidecar was captured against (e.g. a new paragraph was inserted earlier
/// in the document, shifting every later paragraph's index by one), the
/// restorer has no way to detect that and will happily apply the sidecar
/// entry's formatting to the wrong paragraph — no skip, no error. Detecting
/// that would require some form of content-addressed matching (e.g. hashing
/// paragraph text) that the sidecar format does not currently carry. Callers
/// relying on positional restoration after edits should keep paragraph
/// order (insert/delete/reorder-free edits only) for the mapping to stay
/// correct; only out-of-range or type-mismatched indices are caught here.
/// Callers that need to know which entries were skipped (the cases this
/// restorer *does* catch) can compare `metadata.paragraphs.count` / indices
/// against the resulting document's `body.children` themselves — no side
/// channel is added here to keep the `convertMarkdown(_:metadata:...)`
/// entry point a plain, synchronous `throws -> WordDocument` call.
enum Tier3MetadataRestorer {
    static func restore(_ metadata: DocumentMetadata, onto document: inout WordDocument) {
        for meta in metadata.paragraphs {
            guard meta.index >= 0, meta.index < document.body.children.count else { continue }
            guard case .paragraph(var paragraph) = document.body.children[meta.index] else { continue }
            apply(meta, to: &paragraph.properties)
            document.body.children[meta.index] = .paragraph(paragraph)
        }
    }

    private static func apply(_ meta: ParagraphMeta, to properties: inout ParagraphProperties) {
        if let alignment = meta.alignment.flatMap(Alignment.init(rawValue:)) {
            properties.alignment = alignment
        }

        if let spacing = meta.spacing {
            properties.spacing = Spacing(
                before: spacing.before,
                after: spacing.after,
                line: spacing.line
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
}
