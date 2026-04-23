## ADDED Requirements

### Requirement: WordDocument mutation methods consult RelationshipIdAllocator instead of naive counter

The `WordDocument` struct's mutating methods that allocate new relationship IDs (`insertImage(path:)`, `insertImage(base64:)`, `insertImage(...at: InsertLocation)`, `addHeader(...)`, `addFooter(...)`, `addHyperlinkReference(...)`) SHALL obtain new rIds from a per-document `RelationshipIdAllocator` instance, NOT from the naive counter pattern (`baseId + headers.count + footers.count + images.count`). The allocator SHALL be lazily constructed on first rId-needing mutation, initialized from the document's `archiveTempDir` original rels XML (via the existing `RelationshipIdAllocator(originalRelsXML:additionalReservedIds:)` initializer) plus the typed model's already-assigned rIds. Subsequent rId-needing mutations within the same `WordDocument` value SHALL reuse the cached allocator.

For initializer-built documents (`archiveTempDir == nil`), the allocator SHALL be initialized with empty original rels XML — preserving current `create_document` behavior where rIds start from `rId4` (or `rId5` when numbering is present).

The `WordDocument` properties `nextImageRelationshipId` and `nextRelationshipId` SHALL be removed (or kept as `@available(*, deprecated)` thin wrappers calling the allocator) — direct callers of these properties in `Document.swift` `insertImage` paths SHALL be replaced with `allocator.allocate()` calls.

#### Scenario: Insert image into reader-loaded thesis returns ID that does not collide with existing rels

- **GIVEN** a thesis docx is loaded via `DocxReader.read(from: thesisURL)` where the source `word/_rels/document.xml.rels` already contains rIds `rId1` through `rId24` (e.g., styles, settings, fontTable, numbering, 6 headers, 4 footers, 13 images)
- **WHEN** `doc.insertImage(path: "fig1.png", widthPx: 800, heightPx: 600, at: .beforeText("Anchor", instance: 1))` is called
- **THEN** the returned rId is `"rId25"` (max(observed) + 1, where observed includes 24 from original)
- **AND** the inserted Drawing's `r:embed` attribute equals `"rId25"`
- **AND** subsequent `doc.insertImage(...)` calls return `"rId26"`, `"rId27"`, etc. with no repeats

#### Scenario: Sequential image inserts preserve allocator state across mutations

- **GIVEN** a `WordDocument` value loaded from a thesis with 24 existing rels (`rId1`-`rId24`)
- **WHEN** three sequential `insertImage` calls are made on the same `WordDocument` value
- **THEN** the first call allocates `rId25`, the second `rId26`, the third `rId27`
- **AND** none of `rId25`/`rId26`/`rId27` collide with any pre-existing rId in the source rels
- **AND** the allocator's internal state persists across the three calls (lazy property cached, not rebuilt per mutation)

#### Scenario: Initializer-built document allocates from rId4 baseline

- **GIVEN** a fresh `var doc = WordDocument()` (no `archiveTempDir`)
- **WHEN** `doc.insertImage(...)` is called twice
- **THEN** the first call returns `"rId4"` (or `"rId5"` if numbering was added before insertImage)
- **AND** the second call returns `"rId5"` (or `"rId6"` with numbering)
- **AND** behavior matches pre-v0.13.3 `create_document` callers (no regression)

##### Example: NTPU thesis with 24 rels gets new image inserted at rId25

Given source rels XML containing:
```xml
<Relationship Id="rId1" Type="...styles" Target="styles.xml"/>
<Relationship Id="rId7" Type="...header" Target="header1.xml"/>
<Relationship Id="rId13" Type="...image" Target="media/image1.png"/>
<Relationship Id="rId24" Type="...hyperlink" Target="https://..."/>
<!-- ...20 other rels in rId2-rId23 range... -->
```

After `var doc = try DocxReader.read(from: thesisURL)`, then `try doc.insertImage(path: "new.png", ..., at: .beforeText("Anchor", instance: 1))`:
- `allocator.observedMax` was `24` (parsed from original rels)
- `allocator.allocate()` returns `"rId25"`
- The new `ImageReference` carries `id: "rId25"`
- The new Drawing's `<a:blip r:embed="rId25"/>` matches
- After `DocxWriter.write(doc, to: outURL)`, the merged rels XML contains all 24 originals PLUS one new `<Relationship Id="rId25" Type="...image" Target="media/new.png"/>` with no duplicates

### Requirement: ooxml-swift IO layer is fully serial; parallel primitives forbidden

The `packages/ooxml-swift/Sources/OOXMLSwift/IO/` directory SHALL NOT contain any usage of parallel execution primitives. Specifically forbidden symbols:

- `DispatchQueue.concurrentPerform`
- `DispatchQueue.global` (in any context)
- `DispatchQueue.async` (in any context)
- `withTaskGroup`
- `withThrowingTaskGroup`
- `Task.detached` (with no isolation domain)
- `withUnsafeContinuation` (when used to bridge to a parallel primitive)

Rationale: `DocxReader.read` parses XML using Foundation's `XMLDocument` / `XMLElement`, which wraps libxml2. libxml2 documents are NOT thread-safe at the document level — lazy property access on shared element nodes from multiple threads can race. Additionally, the save-durability stack's `recover_from_autosave` requires that re-parsing the same source bytes produces deterministic in-memory state; parallel chunk parsing introduces non-determinism (chunk ordering can affect attribute caches even when distinct paragraphs are parsed independently).

The serial-only policy SHALL be enforced via a regression test that greps the IO source files and asserts zero matches for the forbidden symbols.

#### Scenario: DocxReader.read uses serial chunk parsing

- **GIVEN** a thesis docx with 1000+ paragraphs in the body
- **WHEN** `DocxReader.read(from: thesisURL)` is invoked
- **THEN** parsing runs entirely on the calling thread (no parallel dispatch)
- **AND** the resulting `WordDocument.body.children` array is identical across multiple invocations of `DocxReader.read` against the same source bytes (deterministic ordering and content)
- **AND** `package/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` does NOT contain the substring `concurrentPerform`

#### Scenario: Regression test catches reintroduction of parallelism

- **GIVEN** a developer adds `DispatchQueue.concurrentPerform(iterations: ...) { ... }` to any file under `packages/ooxml-swift/Sources/OOXMLSwift/IO/`
- **WHEN** the test suite runs
- **THEN** `SerialOnlyOOXMLTests.testNoParallelPrimitivesInOOXMLIO` fails
- **AND** the failure message lists the file paths and line numbers where forbidden primitives appear

##### Example: Grep-based assertion

The test SHALL execute the equivalent of:
```bash
grep -rnE 'concurrentPerform|withTaskGroup|withThrowingTaskGroup|DispatchQueue\\.global|DispatchQueue\\..*\\.async|Task\\.detached' \
    packages/ooxml-swift/Sources/OOXMLSwift/IO/
```
and assert the result count is zero. Match found at any path → test fails with the matched lines as the failure message.

