## Why

`DocxReader` and `DocxWriter` accept malicious `.docx` input that can trigger denial-of-service or transit data corruption: there is no DTD reject (billion-laughs / quadratic-blowup attack surface), root-element attribute parsing uses brittle string-prefix matching that silently fails on legitimate prefix variants and offers no length cap, and the writer emits attribute names without validating them against XML well-formedness rules. The four gaps were surfaced by the verification of PsychQuant/che-word-mcp#56 (findings F10/F11/F12/F14) and bundled here because they all touch the same input/output boundary and benefit from a single coherent hardening pass.

## What Changes

- **DTD pre-scan reject** (F10): all 12 `XMLDocument(data:)` call sites in `Sources/OOXMLSwift/IO/DocxReader.swift` reject input containing `<!DOCTYPE` (case-insensitive) before construction by throwing a new `OOXMLError.dtdNotAllowed(part:)`. OOXML spec disallows DTD declarations so this introduces no false-positive on legit input.
- **Root-attribute SAX parser** (F11): replace the string-prefix `parseContainerRootAttributes(rootElementOpenPrefix:)` with a `Foundation.XMLParser` SAX-style implementation. The new helper handles arbitrary namespace prefix variants (`<wordml:document>`, default-namespace `<document>`) natively, calls `parser.abortParsing()` after the first `didStartElement` to avoid full-document parse, and returns `[name: value]`. The old string-prefix signature is removed entirely (no fallback).
- **Attribute-name whitelist on emit + ingest** (F12): `DocxWriter.renderDocumentRootOpenTag` (`Sources/OOXMLSwift/IO/DocxWriter.swift` ~L702-740) validates every attribute name against `^[A-Za-z_:][A-Za-z0-9._:-]*$` before splicing into the open tag and throws `OOXMLError.invalidAttributeName(name:context:)` on violation. The reader-side `splitAttributes` performs the same check to fail fast at source.
- **Per-attribute-value byte cap** (F14): `DocxReader.splitAttributes` enforces a 64 KB hard cap per attribute value, throwing `OOXMLError.attributeValueTooLarge(name:byteSize:cap:)` when exceeded. Cap rationale: ~1000× the largest legit observed value; truncation would break namespace declarations.
- **OOXMLError additions**: new error cases `dtdNotAllowed(part:)`, `invalidAttributeName(name:context:)`, `attributeValueTooLarge(name:byteSize:cap:)` consolidated in `Sources/OOXMLSwift/Models/OOXMLError.swift` (existing file).
- **SemVer**: patch release (v0.21.3). Throws are additive on already-malformed input; no public API change for valid input.

## Non-Goals (optional)

- Not implementing a generic XML schema validator. Cap and whitelist target structural-injection attack patterns, not semantic OOXML conformance.
- Not adding a "lenient mode" flag to suppress the new throws. Hardening is unconditional — caller can catch and degrade.
- Not changing the existing 11 `XMLDocument(data:)` call sites' core parse logic; only adding pre-scan guard.
- Not addressing entity expansion limits inside `XMLDocument(data:)` itself (Foundation does not expose a tunable). DTD reject is the available knob.

## Capabilities

### New Capabilities

- `ooxml-input-hardening`: defines the DTD-reject, root-attribute SAX parser, attribute-name whitelist, and per-attribute-value byte-cap invariants that protect DocxReader/DocxWriter from malformed or malicious `.docx` input. Owns the new `OOXMLError` cases listed above.

### Modified Capabilities

(none. The new hardening is purely additive at the input boundary; no existing capability requirements are changing.)

## Impact

- **Affected code**:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxWriter.swift`
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/OOXMLError.swift`
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/Issue7XMLHardeningTests.swift`
- **APIs**: three new `OOXMLError` cases (additive enum extension); removal of `parseContainerRootAttributes(rootElementOpenPrefix:)` (was internal helper, no SemVer impact).
- **Dependencies**: none (`Foundation.XMLParser` is already linked).
- **Release**: ooxml-swift v0.21.3 patch; consumers (`che-word-mcp`) inherit on next dep bump. Release notes call out attack surface closure.
