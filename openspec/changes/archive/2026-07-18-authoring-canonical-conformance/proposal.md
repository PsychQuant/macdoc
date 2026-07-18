## Why

Any docx produced through the authoring path (`DocxWriter.writeDocument` + typed-model `toXML()`) fails DSL upgrade when exported by `ScriptTranscoder`: the whole `word/document.xml` part falls back to the raw carry channel (`dsl_ratio = 0`), so self-authored documents never get an editable Swift script surface (PsychQuant/ooxml-swift#85; downstream PsychQuant/che-word-mcp#173 — all 148 authoring tools affected).

Root cause (diagnosed on the issue, re-verified in code): two independent first-order blockers in the authoring serializer, each individually fatal to `ReverseExtractor`'s all-or-nothing `documentUpgrade`:

1. **Pretty-print whitespace** — the `writeDocument` template emits newlines between elements (after the root open tag and after `<w:body>`); `elementsOnly` rejects any whitespace-only text node (`Unsupported("non-element-content")`).
2. **Missing `w14:paraId`** — the `Paragraph.w14ParaId` field and emit path exist (v0.20.3+), but no authoring creation site ever fills the value, and the create-from-scratch root tag never declares the `w14` namespace; `extractParagraph` hard-requires paraId (`Unsupported("paragraph-no-paraId")`) because paraId is the stable `setRuns` addressing key.

The fix is tractable now because tree-first IO (v1.0 task 6.2, `retreeXMLParts`) already routes every saved XML part through `XmlTreeReader.parse → XmlTreeWriter.serialize`, so final package bytes come from the same serializer the transcoder's byte-equal trial gate uses. Quoting / self-closing conventions are already unified; only tree content (text nodes, attributes) differs.

## What Changes

- `DocxWriter.writeDocument` stops emitting inter-element whitespace in `word/document.xml` (transcoder-canonical compact form). Prolog form is unchanged (`setDocumentProlog` absorbs prolog variants).
- The create-from-scratch document root (empty `documentRootAttributes` fallback) emits the full Word-canonical namespace cloud (captured from the real-Word `90_template_ja.docx` baseline, including `mc:Ignorable`) instead of the current 2-namespace (`xmlns:w` + `xmlns:r`) template. **Behavior change**: create-from-scratch output bytes differ; documents with captured root attributes are unaffected.
- Typed-model paragraph authoring chokepoints (`appendParagraph`, `insertParagraph(_:at:)` index and `InsertLocation` variants) stamp a generated `w14:paraId` (8-hex, unique per document, Word value range) on paragraphs whose `w14ParaId` is nil; reader-parsed paragraphs keep their source state (absent stays absent). **Behavior change**: authoring output bytes gain paraId attributes; downstream golden/snapshot tests need refresh.
- New round-trip regression tests: pure-paragraph authoring docx → `ScriptTranscoder` export → document.xml `channel: dsl`; exported script → execute → byte-equal rebuild.
- `ooxml-script-transcode` spec gains an authoring-conformance requirement making the above normative.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `ooxml-script-transcode`: add requirement "Authoring path emits transcoder-canonical document.xml" — pure-paragraph documents built through the authoring API SHALL reverse-extract to the DSL channel and round-trip byte-equal; transcoder-side gates (`elementsOnly` strictness, paraId requirement, byte-equal trial) are explicitly NOT loosened.
- `ooxml-roundtrip-fidelity`: modify requirement "WordDocument preserves <w:document> root element attributes byte-equivalent across no-op round-trip" — the empty-`documentRootAttributes` fallback changes from minimal `xmlns:w` + `xmlns:r` to the full Word-canonical namespace cloud (captured-attributes path unchanged).

## Impact

- Affected specs: openspec/specs/ooxml-script-transcode/spec.md (delta), openspec/specs/ooxml-roundtrip-fidelity/spec.md (MODIFIED delta — create-from-scratch root fallback)
- Affected code:
  - Modified: packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift (template whitespace removal; full Word-canonical fallback root constant + ordered emit), packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift (paraId stamping in appendParagraph / insertParagraph), packages/ooxml-swift/Sources/OOXMLSwift/Models/InsertLocation.swift (paraId stamping in insertParagraph(at:)), packages/ooxml-swift/Sources/OOXMLSwift/Models/Section.swift (<w:cols> attribute order aligned to the reducer's canonical emit — residual byte divergence surfaced by the trial gate), packages/ooxml-swift/CHANGELOG.md (release notes for the two byte-level changes)
  - New: packages/ooxml-swift/Sources/OOXMLSwift/Models/ParaIdGenerator.swift (8-hex generator with per-document uniqueness), packages/ooxml-swift/Tests/OOXMLSwiftTests/ParaIdGeneratorTests.swift (generator contract), packages/ooxml-swift/Tests/OOXMLSwiftTests/AuthoringCanonicalConformanceTests.swift (reverse-to-dsl + byte-equal round-trip)
  - Removed: (none)
- Downstream: PsychQuant/che-word-mcp#173 bumps its ooxml-swift pin and adds consumer-side regression after this ships; PsychQuant/ooxml-swift#86 (rich-table canonical subset) stays blocked-by and out of scope.
- Conflict class C: ooxml-swift is a shared package (macdoc converters + che-word-mcp); serialize adjacent in-flight changes touching it.
