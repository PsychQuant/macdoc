// ParagraphSnapshot.swift — §3.2 of macdoc-docx-workflow-cli.
//
// The task description names this `LensDocument+Snapshot.swift` and frames
// it as a private extension on LensDocument. Implementation reality:
// LensDocument's `inner: OOXMLSwift.WordDocument` is private to
// word-builder-swift, so an extension from this module cannot reach it.
// Equivalent semantic implemented here as a free utility that re-reads the
// same baseline URL via DocxReader and walks the public body surface.
//
// Caveat (audit-discipline honest): paragraph identity is derived from
// `XmlNode.stableID` first (`w14:paraId` / `w:bookmarkId` / `w:id` etc.),
// `libraryUUID` last. For Word 2013+ documents almost every paragraph has
// `w14:paraId`, so a separate parse produces ElementIDs that match
// LensDocument's inner. For documents that fall through to `libraryUUID`,
// the two parses produce different random UUIDs — apply-time surfaces as
// `EditError.pathNotFound` / `.operationLogFailure` (per the foundation's
// PHASED state, see word-builder-swift v1.0.0 spec.md). The CLI documents
// this edge case in the README.

import Foundation
import WordBuilderSwift  // re-exports OOXMLSwift

/// One entry in a paragraph snapshot — a ParagraphRef paired with the
/// paragraph's concatenated text content.
public struct ParagraphSnapshotEntry: Equatable {
    public let ref: ParagraphRef
    public let text: String

    public init(ref: ParagraphRef, text: String) {
        self.ref = ref
        self.text = text
    }
}

/// Builds a `(ParagraphRef, text)` snapshot from a `.docx` baseline.
///
/// Reads the URL via `DocxReader` with `wireTreeBackedViews: true` so the
/// resulting `Paragraph.xmlNode` is non-nil and yields a stable `ElementID`
/// matching the one a `LensDocument(reading: url)` would use internally
/// (for documents with native `w14:paraId` etc.).
public enum ParagraphSnapshot {

    public static func read(from url: URL) throws -> [ParagraphSnapshotEntry] {
        let doc = try DocxReader.read(from: url, wireTreeBackedViews: true)
        return entries(from: doc)
    }

    /// Builds snapshot entries from an in-memory `WordDocument`. Used by
    /// the Executor between steps so sequential anchor resolution sees
    /// post-step state (per spec.md "Executor applies steps in manifest
    /// order").
    public static func entries(from doc: WordDocument) -> [ParagraphSnapshotEntry] {
        var result: [ParagraphSnapshotEntry] = []
        for child in doc.body.children {
            switch child {
            case .paragraph(let paragraph):
                guard let xmlNode = paragraph.xmlNode else {
                    // Paragraph without a tree-backed xmlNode is unaddressable.
                    // Skip — apply would throw `pathNotFound`.
                    continue
                }
                // ElementID(node:) returns nil only when xmlNode lacks both a
                // native stable ID (w14:paraId / w:id / etc.) and a
                // libraryUUID. Per the foundation contract, the consumer
                // assigns a libraryUUID before referencing such nodes (see
                // OOXMLSwift/OpLog/ElementID.swift comment block). Do that
                // here so manifests target paragraphs uniformly regardless
                // of whether the source .docx carries native IDs.
                if xmlNode.libraryUUID == nil, ElementID(node: xmlNode) == nil {
                    xmlNode.libraryUUID = UUID()
                }
                guard let elementID = ElementID(node: xmlNode) else {
                    continue
                }
                result.append(ParagraphSnapshotEntry(
                    ref: ParagraphRef(elementID),
                    text: paragraph.text
                ))
            case .table, .contentControl, .bookmarkMarker:
                // Non-paragraph body children are not anchor targets in
                // Phase 1. Tables are addressed via their own step types
                // (Phase 2c-pending — ooxml-swift#71).
                continue
            default:
                // Conservative: skip unknown body child types.
                continue
            }
        }
        return result
    }
}
