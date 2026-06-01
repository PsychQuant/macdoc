# DocxWorkflowLib

Layer 3 manifest-driven docx-edit library on top of [word-builder-swift](https://github.com/PsychQuant/word-builder-swift) v1.0.0.

DocxWorkflowLib turns a declarative JSON manifest into a sequence of `LensDocument` `apply(_:)` calls against an existing `.docx` baseline, then `emit`s the resulting document. It pairs with verification post-conditions (image count, paragraph minimums, byte-preserved parts, libxml2 validity) so the same manifest is replayable across docx baselines without runtime drift.

## Quick example

```swift
import Foundation
import DocxWorkflowLib  // single import — re-exports WordBuilderSwift + OOXMLSwift

let data = try Data(contentsOf: URL(fileURLWithPath: "manifest.json"))
let manifest = try JSONDecoder().decode(Manifest.self, from: data)

let executor = Executor()
let result = try executor.apply(
    manifest: manifest,
    baselineURL: URL(fileURLWithPath: manifest.baseline),
    outputURL: URL(fileURLWithPath: manifest.output),
    warnHandler: { warning in
        FileHandle.standardError.write(Data((warning + "\n").utf8))
    }
)

print("Applied: \(result.appliedStepCount), skipped: \(result.skippedPendingStepCount)")

if let assertions = manifest.verify {
    try Verifier().verify(
        assertions,
        baselineURL: URL(fileURLWithPath: manifest.baseline),
        outputURL: URL(fileURLWithPath: manifest.output)
    )
}
```

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Manifest (JSON-Codable)                                         │
│    baseline + output + [Step] + VerifyAssertions?                │
└─────────────────────────┬────────────────────────────────────────┘
                          │
                          ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌────────────┐
│ Manifest     │→ │ AnchorResolver│→│ EditPlanner  │→ │ Executor   │
│ (Codable)    │  │ (text → ID)  │  │ ([any Edit]) │  │ (LensDoc.) │
└──────────────┘  └──────────────┘  └──────────────┘  └────────────┘
                                                            │
                                                            ▼
                                                   ┌────────────────┐
                                                   │ Verifier       │
                                                   │ (post-cond.)   │
                                                   └────────────────┘

  Foundation: word-builder-swift v1.0.0 + ooxml-swift Edit algebra
```

## Phase 1 step types

**Runtime-functional** (Reducer cases shipped in `ooxml-swift` Phase 2c):
- `replace_text`, `insert_paragraph`, `set_paragraph_style`
- `wrap_link`, `set_bold`, `set_italic`, `set_underline`, `remove_paragraph`

**Spec-documented but Reducer-pending** (tracker: [ooxml-swift#71](https://github.com/PsychQuant/ooxml-swift/issues/71)):
- `insert_image`, `insert_table`, `set_cell_text`, `insert_equation`

The executor emits a warning to the `warnHandler` for each pending step and continues without applying, matching the `try?` idiom established in `word-builder-swift` v1.0.0 examples.

## Anchor semantics (deterministic)

| Outcome | Behavior |
|---|---|
| Exact-one match | Succeeds |
| Multi-match (≥2) | `AnchorError.ambiguous` — user must lengthen the substring |
| Zero match | `AnchorError.notFound` |
| `paragraph_index` out of range | `AnchorError.indexOutOfRange` |

No first-match-wins. The "replicable pipelines" use case demands deterministic resolution.

## Verify post-conditions (Phase 1)

| Field | Effect |
|---|---|
| `expected_images: Int` | Assert `<a:blip>` count equals N |
| `expected_paragraphs_min: Int` | Assert paragraph count ≥ N |
| `expected_bookmarks_min: Int` | Assert bookmark count ≥ N |
| `libxml2_valid: Bool` | Assert OOXML parts parse cleanly (Foundation `XMLParser` Phase 1) |
| `byte_preserved_parts: [String]` | Assert post-c14n byte-equality for matched parts |

## Status

v0.1.0 — Layer 3 implementation per [openspec change `macdoc-docx-workflow-cli`](https://github.com/PsychQuant/macdoc/tree/main/openspec/changes/macdoc-docx-workflow-cli) (in-progress).

## License

MIT.
