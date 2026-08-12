## Context

macdoc's note routes are compiled against `NoteToHTML` and `NoteToPDF`, whose shared legacy parser expects a ZIP entry ending in `Session.plist`. Modern Notability exports observed from app version 16.8.1 instead contain the FlatBuffers document entry `noteBundle`. The private source fixture cannot be committed, and a full schema implementation is intentionally out of scope, but ZIP central-directory names are sufficient to distinguish the two generations without reading note content.

The root resolver already contains ZIPFoundation 0.9.20 transitively. MacDocCLI must declare that package directly before importing its product; this changes the manifest dependency surface but does not introduce a second ZIP implementation.

## Goals / Non-Goals

**Goals:**

- Identify legacy and modern Notability containers from archive entry names before calling either converter.
- Reject modern containers with one stable Traditional Chinese diagnostic for HTML and PDF, including files renamed from `.ntb` to `.note`.
- Preserve existing successful legacy `.note` conversion and existing malformed/unknown ZIP diagnostics.
- Ensure generation rejection happens before stdout, output-directory, or PDF-file creation.
- Document the exact support boundary.

**Non-Goals:**

- Parse FlatBuffers or inspect `noteBundle`, index, manifest, audio, image, or thumbnail payload bytes.
- Extract assets or synthesize degraded HTML/PDF.
- Change `NoteCore`, `NoteToHTML`, or `NoteToPDF` public APIs in this phase.
- Infer format generation from `manifest.json` contents or an app-version string.

## Decisions

### Classify from normalized ZIP entry names without extracting payloads

`NotabilityContainerDetector` opens the input with ZIPFoundation in read-only mode and enumerates entry paths only. It normalizes path separators, discards empty and `.` components, and recognizes an entry by its final path component so both top-level modern archives and archives wrapped in one export directory are classified. It never calls archive extraction and never opens an entry payload.

The classification is `legacy` when any regular entry ends in `Session.plist`; otherwise it is `modernFlatBuffers` when any regular entry ends in `noteBundle`; otherwise it is `unknown`. Legacy takes precedence if both markers exist because the downstream parser has a concrete supported path and must not be denied by an unrelated extra entry.

Alternatives rejected:

- Suffix-only classification cannot detect a modern container renamed to `.note` and contradicts the issue evidence that entry structure is authoritative.
- Reading `manifest.json` exposes unnecessary payload and its `appVersion` is not a schema version.
- Extracting to a temporary directory repeats the downstream parser's work and expands archive traversal exposure.

### Gate both HTML and PDF note routes before converter construction

The `.note` and `.ntb` HTML/PDF switch cases call one preflight function before invoking either converter. `modernFlatBuffers` throws a fixed `ValidationError` stating that a modern `.ntb` FlatBuffers container was detected and only legacy plist-based `.note` with `Session.plist` is supported. `legacy` continues to the converter. `unknown` also continues so the established invalid-ZIP or missing-session error remains authoritative for corrupt and unrelated inputs.

Alternatives rejected:

- Catching only `NoteError.missingSessionPlist` after conversion can occur after extraction and cannot serve `.ntb`, which is currently rejected by the extension switch.
- Implementing the message only in `NoteCore` would require an upstream release and would not make macdoc route `.ntb` inputs in the current delivery.

### Prove behavior with synthetic metadata-only archives

Tests create tiny ZIP archives containing fixed non-sensitive bytes for `noteBundle`, `version`, and `manifest.json`. They invoke the compiled CLI for `.ntb → html`, `.ntb → pdf`, and a modern archive renamed `.note → html`, assert exact non-zero diagnostics and empty stdout, and assert the requested output path remains absent. Existing synthetic `Session.plist` route tests continue to prove no legacy regression.

No real Notability fixture, recording, thumbnail, handwritten data, title, identifier, or manifest value is committed.

### Qualify documentation rather than overstate support

README and CONVERSIONS SHALL describe legacy `.note` HTML/PDF as implemented and modern `.ntb` as detected-but-not-supported. They SHALL state that FlatBuffers handwriting/timeline replay is not implemented and SHALL not present asset extraction as available.

## Implementation Contract

**Behavior:** `macdoc convert --to html modern.ntb --output out` and the equivalent PDF command SHALL fail before creating `out`. A ZIP carrying `noteBundle` under a `.note` suffix SHALL fail identically. A ZIP carrying `Session.plist` SHALL retain the existing converter behavior.

**Interface / data shape:** the detector is an internal MacDocCLI value with a classification enum containing `legacy`, `modernFlatBuffers`, and `unknown`. It accepts a file URL and returns a classification without exposing entry names or payloads to callers. The exact modern-container diagnostic is:

`偵測到新版 Notability .ntb 容器（noteBundle／FlatBuffers）；目前僅支援舊版 plist-based .note（Session.plist）`

**Failure modes:** inability to open or classify an archive returns `unknown`; the existing converter then supplies the established invalid/missing-session diagnostic. The detector SHALL not log input paths, entry lists, manifest data, note contents, or archive bytes. A modern classification always fails locally without network activity.

**Acceptance criteria:** RED tests first fail because `.ntb` is reported as an unsupported route and renamed `.note` receives the legacy missing-session diagnostic. After implementation, compiled CLI tests assert exact stderr, empty stdout, non-zero exit, and absent HTML/PDF destination; existing Note HTML/PDF smoke tests and the full root suite pass. Spectra validation and diff privacy scanning pass.

**Scope boundaries:** phase 0 ends at classification, precise rejection, and documentation. Full FlatBuffers parsing and asset export remain explicit future work.

## Risks / Trade-offs

- [Risk] A future container uses a different root marker. → Unknown archives fall through to established diagnostics; do not guess from app version.
- [Risk] A malicious archive includes both markers. → Legacy precedence preserves the only supported parser path; ZIPFoundation payload extraction remains downstream and unchanged.
- [Risk] Entry enumeration itself processes an attacker-controlled central directory. → Use ZIPFoundation's read-only archive API and never extract or read entry payloads in the detector.
- [Risk] Direct dependency declaration can drift from the transitive resolver. → Use the existing 0.9.20-compatible package requirement and verify Package.resolved remains on the audited revision already present in the root lockfile.
