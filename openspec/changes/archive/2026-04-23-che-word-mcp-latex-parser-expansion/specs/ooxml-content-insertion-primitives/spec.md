## ADDED Requirements

### Requirement: MathAccent emits valid OMML accent element

The `ooxml-swift` package SHALL provide a `public struct MathAccent` conforming to `MathComponent` whose `toOMML()` method emits the ECMA-376 Part 1 §22.1.2.1 `<m:acc>` element. The struct MUST expose two stored properties: `base: [MathComponent]` (the math content under the accent) and `accentChar: String` (the combining diacritic codepoint). The emitted XML MUST follow the structure `<m:acc><m:accPr><m:chr m:val="<accentChar>"/></m:accPr><m:e><base OMML></m:e></m:acc>`. The `accentChar` value MUST be applied verbatim into the `m:val` attribute (XML-escaped where required by `<` `>` `&`). Callers MAY provide standard accent codepoints `\u{0302}` (circumflex, for `\hat`), `\u{0304}` (macron, for `\bar` and `\overline`), `\u{0303}` (tilde, for `\tilde`), `\u{0307}` (dot above, for `\dot`), or any other Unicode combining diacritic.

#### Scenario: Hat accent over single run

- **WHEN** `MathAccent(base: [MathRun(text: "x")], accentChar: "\u{0302}").toOMML()` is called
- **THEN** the output equals `<m:acc><m:accPr><m:chr m:val="̂"/></m:accPr><m:e><m:r><m:t>x</m:t></m:r></m:e></m:acc>`

#### Scenario: Bar accent over Greek letter

- **WHEN** `MathAccent(base: [MathRun(text: "ρ")], accentChar: "\u{0304}").toOMML()` is called
- **THEN** the output contains `<m:chr m:val="̄"/>` and `<m:e><m:r><m:t>ρ</m:t></m:r></m:e>` in that order

#### Scenario: Accent over composite base preserves nested structure

- **WHEN** `MathAccent(base: [MathSubSuperScript(base: [MathRun(text: "ε")], sub: [MathRun(text: "t")], sup: nil)], accentChar: "\u{0302}").toOMML()` is called
- **THEN** the output contains `<m:e><m:sSub><m:e><m:r><m:t>ε</m:t></m:r></m:e><m:sub><m:r><m:t>t</m:t></m:r></m:sub></m:sSub></m:e>`

#### Scenario: Accent character requiring XML escape

- **WHEN** `MathAccent(base: [MathRun(text: "y")], accentChar: "&").toOMML()` is called
- **THEN** the output contains `<m:chr m:val="&amp;"/>` and the call does not throw

### Requirement: ooxml-swift package version reflects MathAccent addition

The `ooxml-swift` package version SHALL be at least `0.11.0` in `Package.swift` and `CHANGELOG.md` SHALL contain a `## 0.11.0` entry naming `MathAccent` as the additive change. The CHANGELOG entry MUST mark this as additive and non-breaking.

#### Scenario: Package version metadata reflects 0.11.0

- **WHEN** the `ooxml-swift` repository is inspected at the tag `v0.11.0`
- **THEN** `CHANGELOG.md` contains a `## 0.11.0` (or equivalent `## [0.11.0]`) section that lists `MathAccent` as added
- **AND** the section explicitly states the change is additive and non-breaking
