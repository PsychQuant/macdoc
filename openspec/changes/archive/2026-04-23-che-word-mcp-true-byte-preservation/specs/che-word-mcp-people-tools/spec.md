## ADDED Requirements

### Requirement: list_people parses w15:presenceInfo child element fully

The `che-word-mcp` server's `list_people(doc_id)` MCP tool SHALL parse each `<w15:person>` element including its child `<w15:presenceInfo>` element. From the child element, the tool SHALL extract:

- `email` from `w15:userId` attribute by splitting on `::` and taking the second segment when the userId follows the pattern `S::<email>::<guid>`. When userId does not match this pattern, `email` SHALL be `null`.
- `provider_id` directly from `w15:providerId` attribute (e.g., `"AD"`, `"Windows Live"`, `"Office365"`, `"None"`). When attribute absent, `null`.
- `color` directly from `w15:color` attribute when present (hex format). When absent, `null`.

#### Scenario: NTPU presenceInfo full parse

- **WHEN** `list_people` is called on a document whose `people.xml` contains:
  ```xml
  <w15:person w15:author="Kuo Chia Yuan (Senior Manager, Corporate Planning - HO)">
    <w15:presenceInfo w15:providerId="AD"
                      w15:userId="S::adam.kuo@yuanta.com.vn::99b8ea77-3e4d-4917-a8fa-259313a0e4b9"/>
  </w15:person>
  ```
- **THEN** the result contains an entry with:
  - `email == "adam.kuo@yuanta.com.vn"`
  - `provider_id == "AD"`
  - `color == null`

### Requirement: list_people returns dual identity fields person_id (GUID) and display_name_id (author)

The `che-word-mcp` server's `list_people(doc_id)` MCP tool SHALL return BOTH:

- `person_id`: The durable GUID parsed from `w15:userId` third segment (after splitting on `::`). When no GUID is found (presenceInfo absent or userId pattern doesn't match), `person_id` SHALL fall back to the author attribute string (preserving v3.4.0 behavior for documents without presenceInfo).
- `display_name_id`: The author attribute value, equal to what v3.4.0 returned as `person_id`. Provided for backward compatibility — v3.4.0 callers can switch to reading `display_name_id` to maintain their existing key-space.

Plus the existing fields: `display_name` (= author), `email`, `color`, `provider_id`.

#### Scenario: NTPU person dual identity

- **WHEN** `list_people` is called on the NTPU person example above
- **THEN** the returned entry has:
  - `person_id == "99b8ea77-3e4d-4917-a8fa-259313a0e4b9"` (GUID from userId third segment)
  - `display_name_id == "Kuo Chia Yuan (Senior Manager, Corporate Planning - HO)"` (legacy author)
  - `display_name == "Kuo Chia Yuan (Senior Manager, Corporate Planning - HO)"`

#### Scenario: Person without presenceInfo falls back to author for person_id

- **WHEN** `list_people` is called on a document where `people.xml` has `<w15:person w15:author="Adam Kuo"/>` with no presenceInfo child
- **THEN** the returned entry has `person_id == "Adam Kuo"` (fallback) and `display_name_id == "Adam Kuo"`

### Requirement: update_person and delete_person accept either person_id (GUID) or display_name_id (legacy author)

The `che-word-mcp` server's `update_person(doc_id, person_id, ...)` and `delete_person(doc_id, person_id)` MCP tools SHALL accept either the GUID-based `person_id` OR the legacy author-string `display_name_id` as the identifier argument. The handler SHALL try matching both against parsed people entries (using extracted GUID and author respectively) and operate on the first match. When no match found, return `Error: person_id not found: <id>`.

#### Scenario: update_person via GUID

- **WHEN** `update_person(doc_id: "x", person_id: "99b8ea77-3e4d-4917-a8fa-259313a0e4b9", display_name: "New Name")` is called
- **THEN** the matching `<w15:person>` entry's `w15:author` attribute is updated to `"New Name"`

#### Scenario: update_person via legacy display_name_id

- **WHEN** `update_person(doc_id: "x", person_id: "Kuo Chia Yuan (Senior Manager, Corporate Planning - HO)", display_name: "New Name")` is called (legacy v3.4.0 caller pattern)
- **THEN** the matching `<w15:person>` entry's `w15:author` is updated to `"New Name"`
- **AND** v3.5.0 release notes flag this dual-acceptance pattern; v4.0.0 will require GUID-based person_id

### Requirement: people-tools document v3.4.0 → v4.0.0 backward-compat migration

The `che-word-mcp v3.5.0` CHANGELOG SHALL include a section titled "Migration: person_id semantic change" explaining that `list_people` now returns GUID-based `person_id` (with `display_name_id` for legacy access), and that v4.0.0 will remove `display_name_id`. Callers using v3.4.0 `person_id == display_name` SHALL be advised to switch to reading `display_name_id` (immediate fix preserving exact v3.4.0 behavior) OR to GUID-based `person_id` (forward-compatible to v4.0.0).

#### Scenario: CHANGELOG mentions migration path

- **WHEN** `che-word-mcp v3.5.0` CHANGELOG is published
- **THEN** it contains a section heading containing "Migration" or "person_id" and the v4.0.0 deprecation timeline
