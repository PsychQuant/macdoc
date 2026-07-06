## 1. Implementation

These tasks land the production code for the tree-backed Paragraph view in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift`. Tasks 1.1-1.4 are sequential (same file, sequential edits compound). Task 1.5 (gate flip) is sequential after 1.1-1.4 because flipping the gate before the API exists would re-break the build.

- [x] 1.1 Add the `xmlNode: XmlNode?` stored property and `Paragraph(xmlNode: XmlNode)` constructor to `Paragraph` per Decision 1: `Paragraph` stays a `struct`, not promoted to `class` — the new property holds a class reference so two value-copies share tree state. Implements the **Tree-backed Paragraph constructor** requirement
- [x] 1.2 Add `paragraph.id: String?` computed property per Decision 2: `id` is `String?` and reads `xmlNode?.stableID` with `lib:` UUID fallback — returns `xmlNode?.stableID` if present, else `"lib:\(libraryUUID.uuidString)"` if `libraryUUID` is set, else `nil`. Implements the **Paragraph identity derived from XmlNode stableID with libraryUUID fallback** requirement
- [x] 1.3 Convert `paragraph.text` and `paragraph.runs` to mode-aware computed properties per Decision 3: Getter `text` and `runs` are computed, not cached — when `xmlNode != nil`, walk the wrapped xmlNode's children at every access; when detached, return the legacy stored property values. Implements the **Tree-walking getters for text and runs** requirement
- [x] 1.4 Implement the tree-mutating `paragraph.text` setter (Phase 1 stub) per Decision 4: Setter `text` mutates tree directly (Phase 1 stub) — when tree-backed, replace the wrapped xmlNode's `<w:r>` children with one new `<w:r><w:t>X</w:t></w:r>` and call `markDirty()`. When detached, fall through to the existing legacy setter behavior. Implements the **Tree-mutating setter for text (Phase 1 stub)** requirement
- [x] 1.5 Replace auto-synthesized `Equatable` conformance with mode-aware implementation per Decision 5: Identity-based `Equatable`, not content-based — both tree-backed: identity-based via `===` on xmlNode; both detached: content equality on legacy stored properties; mixed: `false`. Implements the **Identity-based equality for tree-backed Paragraphs** requirement and preserves the **Public Paragraph API surface preserved during refactor** requirement (no public-API change beyond what is added in tasks 1.1-1.2)

## 2. Test gate + Phase 1 verification

- [x] 2.1 Flip the `#if false` compile gate to `#if true` (or remove the gate entirely while preserving the surrounding header comment) per Decision 6: Test gate flips, not removes — at the top of `packages/ooxml-swift/Tests/OOXMLSwiftTests/ParagraphTreeProjectionTests.swift`. Implements the **ParagraphTreeProjectionTests gate flipped to enabled** requirement
- [x] 2.2 Run `swift test --filter ParagraphTreeProjectionTests` and assert all 9 RED scaffold tests pass GREEN. Investigate any failure — failures here are real implementation gaps, not flaky tests
- [x] 2.3 Run `swift test` (the full ooxml-swift suite) and assert zero regressions on existing tests. Investigate any failure — most likely cause is identity-equality breaking a legacy test that compared two reader-produced paragraphs; if so, that test path needs to detect tree-backed mode and fall back to content equality, OR (cleaner) the test path was never tree-backed in the first place and the failure is unrelated

## 3. Downstream regression gate

- [x] 3.1 Run che-word-mcp's 271 production tests against the new ooxml-swift via `cd ../mcp/che-word-mcp && swift test 2>&1 | tail -30`. Assert zero failures and zero observable output diff versus the pre-change baseline per the **Public Paragraph API surface preserved during refactor** requirement. Document the test-pass count in the task close commit message

## 4. Release prep + sibling change handoff

- [x] 4.1 Bump ooxml-swift `Package.swift` version to v0.31.0 (or appropriate next minor) and update CHANGELOG.md with the new tree-backed Paragraph mode entry. Tag the release per the existing `cli-tools:cli-deploy` flow used in earlier ooxml-swift releases
- [x] 4.2 Mark `word-aligned-state-sync` Phase 1 task 2.1 (Refactor Paragraph to be a tree-backed view) as done in that change's tasks.md via `spectra task done` — this change is the production-code half of that task; the RED scaffold half landed earlier in that same change as commit c97de51
