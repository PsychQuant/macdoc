# ooxml-paragraph-text-mirror Specification — script-variant-anchor-matching delta

## ADDED Requirements

### Requirement: Anchor lookup MAY normalize math script variants when explicitly requested

OOXMLSwift paragraph/body-child text anchor lookup SHALL support an explicit option for math-script-insensitive matching. The default lookup mode SHALL remain exact matching.

When math-script-insensitive matching is enabled, the lookup implementation SHALL normalize both the searched document text (haystack) and the caller-provided anchor text (needle) through the same math-script canonicalization table before matching.

The canonicalization table SHALL map supported Unicode subscript and superscript digits, signs, grouping characters, and common Latin letters to their closest ASCII representation. Characters not listed in the table SHALL remain unchanged.

The option MUST NOT change `Paragraph.flattenedDisplayText()`, OMML `visibleText`, export text output, or any other read API output.

#### Scenario: Default exact mode preserves current mismatch

- **GIVEN** a paragraph whose flattened display text is `"H0 is rejected"`
- **WHEN** anchor lookup searches for `"H₀"` with default options
- **THEN** no match is returned

#### Scenario: Unicode subscript needle matches ASCII haystack when enabled

- **GIVEN** a paragraph whose flattened display text is `"H0 is rejected"`
- **WHEN** anchor lookup searches for `"H₀"` with math-script-insensitive matching enabled
- **THEN** the paragraph's body-child index is returned

#### Scenario: ASCII needle matches Unicode subscript haystack when enabled

- **GIVEN** a paragraph whose flattened display text is `"H₀ is rejected"`
- **WHEN** anchor lookup searches for `"H0"` with math-script-insensitive matching enabled
- **THEN** the paragraph's body-child index is returned

#### Scenario: Superscript and subscript letters normalize consistently

- **GIVEN** a paragraph whose flattened display text is `"xᵢ + y²"`
- **WHEN** anchor lookup searches for `"xi + y2"` with math-script-insensitive matching enabled
- **THEN** the paragraph's body-child index is returned

#### Scenario: nth-instance selection counts normalized matches

- **GIVEN** body paragraphs flatten to `["H0 first", "H₀ second"]`
- **WHEN** anchor lookup searches for `"H₀"` with instance `2` and math-script-insensitive matching enabled
- **THEN** the second paragraph's body-child index is returned

#### Scenario: Unsupported characters are preserved

- **GIVEN** a paragraph containing an unsupported Unicode symbol that is not in the math-script canonicalization table
- **WHEN** math-script-insensitive lookup runs
- **THEN** that symbol remains unchanged for matching purposes

---

### Requirement: Math visible text output remains unchanged by script-variant matching

Math-script-insensitive matching SHALL be implemented as a lookup-time normalization mode only. It SHALL NOT alter OMML visible-text generation or paragraph flattening output.

#### Scenario: OMML subscript visible text remains ASCII

- **GIVEN** an OMML subscript expression representing `H₀`
- **WHEN** its visible text is read
- **THEN** the output remains the existing ASCII mirror, such as `"H0"`
- **AND** no Unicode subscript character is introduced by the matcher option

#### Scenario: flattenedDisplayText is unaffected

- **GIVEN** a paragraph containing the OMML expression for `H₀`
- **WHEN** `flattenedDisplayText()` is called
- **THEN** the result remains identical to exact-mode behavior
- **AND** enabling math-script-insensitive lookup elsewhere does not mutate the paragraph or its flattened output
