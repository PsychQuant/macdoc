## ADDED Requirements

### Requirement: Authoring path emits transcoder-canonical document.xml

Documents built through the authoring API (create-from-scratch `WordDocument` plus paragraph append/insert with plain or formatted runs) and saved by the docx writer SHALL produce a `word/document.xml` that reverse extraction upgrades to the DSL channel, restricted to the extractor's current canonical subset (pure-paragraph content). The writer SHALL emit compact element-only structure (no whitespace-only text nodes between elements), and the create-from-scratch document root SHALL declare the full Word-canonical namespace cloud (every namespace declaration plus `mc:Ignorable`, values and attribute order captured from the real-Word baseline fixture). Conformance SHALL be achieved entirely on the writer side: the extractor's gates (element-only strictness, paraId requirement, byte-equal trial, minimal authoring-default root vocabulary) remain unchanged, and the extractor SHALL NOT synthesize missing attributes or normalize whitespace to admit non-canonical input.

#### Scenario: pure-paragraph authoring document upgrades to the DSL channel

- **WHEN** a document is created from scratch via the authoring API, paragraphs are appended through the authoring chokepoints, the document is saved, and reverse extraction runs on the saved package
- **THEN** the coverage report lists `word/document.xml` with `channel: dsl` and per-part DSL coverage 100%

#### Scenario: exported script rebuilds the authoring document byte-equal

- **WHEN** the script exported from such a document is executed to rebuild a docx
- **THEN** the rebuilt `word/document.xml` bytes equal the source part bytes exactly

#### Scenario: authoring output contains no inter-element whitespace

- **WHEN** an authoring-built document is saved
- **THEN** parsing `word/document.xml` yields element-only children under `w:document` and `w:body` with no text nodes between elements

#### Scenario: create-from-scratch root carries the full Word-canonical cloud

- **WHEN** a document with no captured root attributes is saved and reverse extraction runs
- **THEN** the root open tag matches the baseline fixture's namespace cloud byte-for-byte, the operation log contains one `setDocumentRoot` operation reproducing that cloud, and the part still upgrades to the DSL channel

#### Scenario: bypassing the authoring chokepoints stays on the raw channel

- **WHEN** a paragraph is injected into the body without passing through the authoring chokepoints and the saved document is reverse-extracted
- **THEN** the part stays on the raw channel and the form-gap report names `paragraph-no-paraId` with the located path

### Requirement: Authoring chokepoints stamp w14:paraId

The paragraph authoring chokepoints (append and both insert variants) SHALL stamp a generated `w14:paraId` on any incoming paragraph whose paraId is nil and SHALL preserve a caller-supplied value verbatim. Generated values SHALL be 8 uppercase hexadecimal characters whose numeric value lies strictly between 0x00000000 and 0x80000000 (exclusive), SHALL be unique among all paragraph paraIds in the target document, and SHALL come from an injectable generator so tests can pin deterministic sequences. Paragraphs parsed from existing packages SHALL keep their source state: a source paragraph without paraId SHALL NOT gain one from loading or re-saving the document.

#### Scenario: appended paragraph receives a generated paraId

- **WHEN** a paragraph with nil paraId is appended through an authoring chokepoint
- **THEN** the serialized `<w:p>` opening tag carries `w14:paraId` with a conforming generated value

##### Example: generated value format

- **GIVEN** a document whose existing paragraphs use paraIds `11111111` and `2AB4C9F0`
- **WHEN** the generator produces the next paraId
- **THEN** the value matches `[0-9A-F]{8}`, differs from both existing values, and its numeric value is greater than 0x00000000 and less than 0x80000000

#### Scenario: caller-supplied paraId is preserved

- **WHEN** a paragraph whose paraId is preset to `3F2A0001` is inserted through an authoring chokepoint
- **THEN** the serialized paragraph carries exactly `w14:paraId="3F2A0001"`

#### Scenario: two insertions never collide

- **WHEN** two paragraphs with nil paraId are inserted into the same document
- **THEN** their generated paraIds differ

#### Scenario: no backfill on round-trip of legacy documents

- **WHEN** an existing package whose paragraphs lack `w14:paraId` is opened and saved without paragraph edits
- **THEN** no paragraph in the written `word/document.xml` gains a `w14:paraId` attribute
