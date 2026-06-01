# NoteFixtureGenerator

Synthesizes a minimal valid Notability `.note` archive for `Note→HTML` / `Note→PDF` smoke tests in CI.

## Why a generator, not a committed binary?

Per [`CLAUDE.md` global rule](../../../../CLAUDE.md) "Git 隱私邊界": the real Apple Notes content (`test-files/筆記 *.note`) contains personal data and cannot be committed to the public repo. A generator produces synthetic content by construction — zero PII, no manual audit needed.

Strategy A (synthetic Swift generator) was chosen over Strategy B (hand-authored throwaway export) and Strategy C (AppleScript-driven Notes export) per the Plan-tier deliberation on `PsychQuant/macdoc#100`. Trade-offs documented in the Implementation Plan comment on that issue.

## How the generator works

1. **Pre-encoded `Session.plist`** — embedded as a base64 `Data` constant in `NoteFixtureGenerator.swift`. Generated once via Python `plistlib.UID` (~314 bytes raw, ~420 chars base64). The minimal object graph contains only what `NoteCore.NoteParser` requires: `$top.root → richText → pageLayoutArray` (one page). All other fields (Handwriting Overlay, contentPlaybackEventManager, paperSizingBehavior, recordings, images) are omitted — the parser handles their absence gracefully.

2. **`generate(at:)`** stages the layout (one inner dir `macdoc-fixture/` with `Session.plist` inside) in a temp directory, then invokes `/usr/bin/zip -r` to pack into a `.note` archive at the target URL.

3. **No persistent fixture file**. The generator runs at test setup time (called from `CLITestHelper.noteFixture()` as fallback when no `test-files/*.note` is present).

## Verifying the generator after `NoteCore` updates

If a future `note-core-swift` version changes its parser contract, `testGeneratorProducesParseableNote` in `NoteFixtureGeneratorTests.swift` will fail. To regenerate the embedded `Session.plist`:

```python
# See NoteFixtureGenerator.swift comment for the full graph schema.
import plistlib
session = {
    "$archiver": "NSKeyedArchiver",
    "$version": 100000,
    "$top": {"root": plistlib.UID(1)},
    "$objects": [
        "$null",
        {"$class": plistlib.UID(5), "richText": plistlib.UID(2)},
        {"$class": plistlib.UID(5), "pageLayoutArray": plistlib.UID(3)},
        {"$class": plistlib.UID(6), "NS.objects": [plistlib.UID(4)]},
        "page-1",
        {"$classname": "NotabilityRoot", "$classes": ["NotabilityRoot", "NSObject"]},
        {"$classname": "NSArray", "$classes": ["NSArray", "NSObject"]},
    ],
}
data = plistlib.dumps(session, fmt=plistlib.FMT_BINARY)
print(__import__("base64").b64encode(data).decode())
```

Replace `sessionPlistBase64` in `NoteFixtureGenerator.swift` with the new output, then add any new required fields to the object graph.

## What the tests assert

- `testGeneratorProducesParseableNote` — `NoteCore.NoteParser` accepts the synthetic output without throwing
- `testGeneratorOutputHasZeroPII` — output bytes contain no PII markers; parsed title is recognizably synthetic
- `testGeneratorIsDeterministic` — two invocations produce notes with equivalent structural fields
- `testGeneratorOutputSizeIsSmall` — output is under 5 KB

## Related

- `PsychQuant/macdoc#100` — Plan-tier issue that drove this work
- `PsychQuant/note-core-swift` — NoteCore.NoteParser is the source of truth for accepted `.note` formats
- `Tests/MacDocCLITests/CLITestHelper.swift` — `noteFixture()` resolution order: pre-generated `Fixtures/mini.note` → synthesized via this generator → `test-files/*.note` → `XCTSkip`
