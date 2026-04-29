## ADDED Requirements

### Requirement: create_style accepts inheritance and gallery args

The MCP tool `create_style` SHALL accept the following optional args in addition to its existing required ones:

- `based_on: string` — emits `<w:basedOn w:val="based_on"/>` so the new style inherits properties from the named style
- `linked_style_id: string` — emits `<w:link w:val="linked_style_id"/>` to associate this style with a paragraph↔character partner
- `next_style_id: string` — emits `<w:next w:val="next_style_id"/>` so pressing Enter after this style switches to the named style
- `q_format: bool` — emits `<w:qFormat/>` to surface the style in Word's Quick Style Gallery
- `hidden: bool` — emits `<w:hidden/>` to hide from the styles pane
- `semi_hidden: bool` — emits `<w:semiHidden/>` to hide from default UI but show when used

When omitted, the v3.9.x default behavior is preserved (no inheritance, no gallery, visible).

#### Scenario: Create style with full inheritance metadata

- **WHEN** the tool is invoked with `style_id: "Heading 1 Bold", style_name: "Heading 1 Bold", based_on: "Heading 1", next_style_id: "Normal", q_format: true`
- **THEN** the new style XML contains `<w:basedOn w:val="Heading 1"/>`, `<w:next w:val="Normal"/>`, and `<w:qFormat/>`

### Requirement: update_style accepts inheritance and gallery args

The MCP tool `update_style` SHALL accept the same six new optional args as `create_style` (`based_on`, `linked_style_id`, `next_style_id`, `q_format`, `hidden`, `semi_hidden`).

For each provided arg, the tool SHALL update the corresponding XML element. For `q_format` / `hidden` / `semi_hidden`, passing `false` SHALL remove the corresponding element if present.

Omitted args SHALL leave the existing XML state untouched.

#### Scenario: Toggle qFormat off

- **GIVEN** a style with `<w:qFormat/>` present
- **WHEN** the tool is invoked with `q_format: false` for that style
- **THEN** the style XML no longer contains `<w:qFormat/>`

### Requirement: get_style_inheritance_chain returns ancestor chain

The MCP tool `get_style_inheritance_chain` SHALL accept `doc_id` (or `source_path`) + `style_id` and return an array containing the queried style and all its ancestors via `basedOn` references, ordered from queried style upward to root.

If the style does not exist, the tool SHALL return error `not_found`.

If the chain contains a cycle, the tool SHALL return the chain prefix up to the first revisited style and include `cycle_detected: true` in the response.

Each entry in the returned array SHALL include: `style_id`, `style_name`, `style_type`, `based_on` (id of next ancestor or null at root).

#### Scenario: Three-level chain

- **GIVEN** styles `Normal`, `Heading 1` (basedOn=Normal), `Heading 1 Bold` (basedOn=Heading 1)
- **WHEN** the tool is invoked with `style_id: "Heading 1 Bold"`
- **THEN** the response is `[{Heading 1 Bold, basedOn=Heading 1}, {Heading 1, basedOn=Normal}, {Normal, basedOn=null}]`

#### Scenario: Cycle detection

- **GIVEN** styles A (basedOn=B) and B (basedOn=A) — pathological cycle
- **WHEN** the tool is invoked with `style_id: "A"`
- **THEN** the response includes `cycle_detected: true` and the chain stops at the first revisit

### Requirement: link_styles binds paragraph and character styles

The MCP tool `link_styles` SHALL accept `doc_id` + `paragraph_style_id` + `character_style_id` and emit `<w:link>` on both styles pointing to each other.

The tool SHALL return error `not_found` if either style does not exist or `type_mismatch` if the paragraph_style_id is not a paragraph style or character_style_id is not a character style.

#### Scenario: Link Heading 1 paragraph to Heading 1 Char character

- **GIVEN** paragraph style `Heading1` and character style `Heading1Char`
- **WHEN** the tool is invoked with `paragraph_style_id: "Heading1", character_style_id: "Heading1Char"`
- **THEN** `Heading1` style XML contains `<w:link w:val="Heading1Char"/>`
- **AND** `Heading1Char` style XML contains `<w:link w:val="Heading1"/>`

### Requirement: set_latent_styles configures Quick Style Gallery defaults

The MCP tool `set_latent_styles` SHALL accept `doc_id` + `latent_styles: [LatentStyleEntry]`.

`LatentStyleEntry` includes: `name: string`, `ui_priority: int?`, `semi_hidden: bool?`, `unhide_when_used: bool?`, `q_format: bool?`.

The tool SHALL emit a `<w:latentStyles>` block in styles.xml replacing any existing one.

When `latent_styles` is empty, the tool SHALL remove the `<w:latentStyles>` block entirely.

#### Scenario: Hide built-in Heading 9 from gallery

- **WHEN** the tool is invoked with `latent_styles: [{name: "Heading 9", ui_priority: 9, semi_hidden: true, unhide_when_used: false, q_format: false}]`
- **THEN** styles.xml contains a `<w:latentStyles>` block with one `<w:lsdException>` for Heading 9 with the specified attributes

### Requirement: add_style_name_alias adds a localized name to a style

The MCP tool `add_style_name_alias` SHALL accept `doc_id` + `style_id` + `lang` (BCP 47 code) + `name`. The tool SHALL append a localized `<w:name>` entry to the target style.

If the style does not exist, the tool SHALL return error `not_found`.

If a name alias already exists for the same `lang`, the tool SHALL replace it (not add a duplicate).

#### Scenario: Add German alias for Heading 1

- **GIVEN** style `Heading 1` with English-only name
- **WHEN** the tool is invoked with `style_id: "Heading 1", lang: "de-DE", name: "Überschrift 1"`
- **THEN** the style's name family includes the German alias

