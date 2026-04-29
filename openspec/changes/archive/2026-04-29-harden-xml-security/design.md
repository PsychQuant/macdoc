## Context

`DocxReader` and `DocxWriter` are the input/output boundary of `ooxml-swift`. Today they trust their input: 12 different `XMLDocument(data:)` call sites accept arbitrary bytes from the source archive without DTD scrubbing; the root-attribute string-prefix parser silently fails on legitimate prefix variants and has no length cap on attribute values; the writer concatenates attribute names directly into the output open-tag with no whitelist check.

Each of those gaps was identified in the verification of PsychQuant/che-word-mcp#56 (findings F10/F11/F12/F14). They share the same boundary, share the same error-handling style (throw on offence), and share the same "additive on already-malformed input" SemVer story — bundling them into one change keeps review and release overhead low and presents a coherent hardening story to downstream consumers.

The four sub-fixes touch:

- `Sources/OOXMLSwift/IO/DocxReader.swift` (DTD pre-scan; SAX-based root-attr parse; attribute-name + value-size validation in `splitAttributes`)
- `Sources/OOXMLSwift/IO/DocxWriter.swift` (`renderDocumentRootOpenTag` attribute-name validation)
- `Sources/OOXMLSwift/Models/OOXMLError.swift` (three new error cases)

## Goals / Non-Goals

**Goals:**

- Close DoS and corruption-transit attack surface at the `XMLDocument(data:)` and `splitAttributes` boundary in one coherent pass.
- Throw distinct, caller-actionable errors per offence type (`dtdNotAllowed`, `invalidAttributeName`, `attributeValueTooLarge`) so downstream tooling can distinguish "untrusted input" from "internal bug".
- Keep the public API surface stable for valid input; consumers that pass legitimate `.docx` files observe zero behavioural change.
- Ship as a SemVer patch (v0.21.3) so downstream `che-word-mcp` and other consumers can pull without breaking changes.

**Non-Goals:**

- Not adding a `lenientMode` switch that suppresses the new throws — hardening is unconditional, callers can `try?` if they accept silent failure.
- Not implementing a generic XML schema validator — caps and whitelists target injection patterns, not OOXML semantic conformance.
- Not patching every property-level XML parse path; this change scopes to the document/container root and `splitAttributes` only.
- Not auditing entity-expansion limits inside `XMLDocument(data:)` itself — Foundation does not expose a tunable; DTD pre-reject is the available knob.
- Not changing the existing 11 `XMLDocument(data:)` call sites' downstream parse logic; only adding the pre-scan guard.

## Decisions

### D1 — Throw, do not silently filter (F10/F12/F14)

When malformed or oversized input is detected, the reader/writer throws the dedicated `OOXMLError` case rather than silently dropping the offending element/attribute. Rationale:

1. Silent filter would mean malformed input transits part-way through parsing and the result diverges from the source — debugging that downstream is much harder than catching the throw at the boundary.
2. The throws are additive on already-malformed input; valid `.docx` files are unaffected.
3. Caller can `try?` if it wants degrade-not-crash semantics; the default loud failure preserves the audit trail.

### D2 — DTD pre-scan via raw `Data.range(of:)`, not via `XMLDocument` post-parse (F10)

`XMLDocument(data:)` already disables external entity resolution by default but **does not** stop internal entity expansion (the billion-laughs vector). The fastest reliable way to refuse DTD-bearing input is to scan the raw `Data` for `<!DOCTYPE` (case-insensitive) before construction:

```swift
private static func rejectDTD(_ data: Data, part: String) throws {
    let needle = "<!DOCTYPE".data(using: .ascii)!
    let needleLower = "<!doctype".data(using: .ascii)!
    if data.range(of: needle) != nil || data.range(of: needleLower) != nil {
        throw OOXMLError.dtdNotAllowed(part: part)
    }
}
```

Applied uniformly at all 12 `XMLDocument(data:)` call sites in `DocxReader.swift` (L127, L149, L158, L205, L263, L295, L349, L398, L407, L490, L583 and any other matches discovered during apply). The `part` argument carries human-readable provenance ("document.xml" / "headerN.xml" / "footnotes.xml") so the error tells the caller *which* part triggered the reject.

### D3 — Foundation `XMLParser` SAX for root attributes, removing string-prefix fallback (F11)

`parseContainerRootAttributes(rootElementOpenPrefix:)` is replaced by an `XMLParser` subclass that:

1. Implements `parser:didStartElement:namespaceURI:qualifiedName:attributes:`.
2. On the first call, captures the `attributes` dictionary into the result and calls `parser.abortParsing()`.
3. Returns `[name: value]` to the caller.

This handles arbitrary namespace prefixes (`<wordml:document>`, `<document xmlns="...">`) natively and avoids the substring-match fragility. The previous `rootElementOpenPrefix:` overload is **removed entirely** — there is no fallback path. Failure to parse (truly malformed XML) returns `[:]`, which the caller already treats as "fall back to hardcoded namespace template".

### D4 — Attribute-name whitelist regex, applied at both ingest and emit (F12)

A single regex `^[A-Za-z_:][A-Za-z0-9._:-]*$` (XML 1.0 NameChar production, conservative subset) is applied at:

- `DocxReader.splitAttributes` — fail-fast on ingest so malformed names cannot transit into `documentRootAttributes`.
- `DocxWriter.renderDocumentRootOpenTag` — second-line defence on emit, in case a name reached the writer through a path that bypassed `splitAttributes`.

Both throw `OOXMLError.invalidAttributeName(name:context:)` where `context` is `"document root"` or `"split-attributes"` so the caller can disambiguate.

### D5 — 64 KB per-attribute-value cap (F14)

`DocxReader.splitAttributes` enforces a hard cap of 64 KB per attribute value (measured in UTF-8 bytes), throwing `OOXMLError.attributeValueTooLarge(name:byteSize:cap:65536)` when exceeded. Cap rationale:

| Attribute | Realistic max length |
|-----------|---------------------|
| `mc:Ignorable` (most extreme — lists ignorable namespace prefixes) | ~200 chars |
| `xmlns:*` (URL) | 80–150 chars |
| Other root attributes | <100 chars |
| **Cap** | **65 536 bytes** (~ 1000× safety margin) |

Truncation is **not** an option — a truncated attribute value would break a namespace declaration (missing closing quote, unparseable URL).

### D6 — Single consolidated `OOXMLError.swift` extension

The three new cases (`dtdNotAllowed(part:)`, `invalidAttributeName(name:context:)`, `attributeValueTooLarge(name:byteSize:cap:)`) are added to the existing `Sources/OOXMLSwift/Models/OOXMLError.swift` enum. Each case carries enough context for the caller to log, surface, and disambiguate without re-parsing the input.

## Risks / Trade-offs

- **Risk: legitimate edge cases trip the new throws.** Mitigation: `mc:Ignorable` worst-observed case is ~200 chars, three orders of magnitude under the 64 KB cap. The DTD reject is spec-anchored (OOXML disallows DTD). The attribute-name regex matches XML 1.0 NameChar.
- **Risk: SAX-based `XMLParser` is slower than substring matching for the root-attribute parse.** Mitigation: only invoked once per part on read; `abortParsing()` after first element is essentially free; the latency is dwarfed by the subsequent `XMLDocument(data:)` parse.
- **Trade-off: throwing on the writer side (D4) means a corrupted source can prevent save.** This is intentional — saving an invalid XML file is worse than failing the save. Caller can repair `documentRootAttributes` and retry.
- **Risk: removing the `parseContainerRootAttributes(rootElementOpenPrefix:)` signature is a binary-compatibility break for any external user of this internal helper.** Mitigation: this helper is `internal` (not `public`), so no SemVer break. Audit confirms no external use within the workspace.
