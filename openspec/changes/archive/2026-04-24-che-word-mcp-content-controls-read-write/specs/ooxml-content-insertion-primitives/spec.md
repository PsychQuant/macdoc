## ADDED Requirements

### Requirement: WordDocument.updateContentControl modifies SDT text content by id

The `WordDocument` model SHALL expose an `updateContentControl(id: Int, newText: String) throws` method. The method locates the ContentControl with the given id in the document tree, replaces its text runs with a single run containing `newText`, and leaves `<w:sdtPr>` properties untouched.

If no ContentControl with the given id exists, the method SHALL throw `WordError.contentControlNotFound(id)`.

If the target ContentControl's type cannot hold plain text (picture, dropDownList, comboBox, checkbox, group, repeatingSection), the method SHALL throw `WordError.unsupportedSDTType(type)`.

#### Scenario: Update text on plain-text ContentControl

- **GIVEN** a WordDocument containing a plain-text ContentControl with id=100000 and current text "TBD"
- **WHEN** `updateContentControl(id: 100000, newText: "Acme")` is called
- **THEN** the ContentControl's content is a single run with text "Acme"
- **AND** the ContentControl's sdt properties (tag, alias, type, lockType, placeholder) are unchanged

#### Scenario: Update fails on not-found id

- **WHEN** `updateContentControl(id: 999999, newText: "x")` is called on a document without that id
- **THEN** the method throws `contentControlNotFound(999999)`

### Requirement: WordDocument.replaceContentControlContent replaces full content XML

The `WordDocument` model SHALL expose a `replaceContentControlContent(id: Int, contentXML: String) throws` method that replaces the entire `<w:sdtContent>` region of the identified ContentControl with the supplied XML fragment.

The method SHALL validate `contentXML` against an element whitelist. If the XML contains `<w:sdt>`, `<w:body>`, `<w:sectPr>`, or an XML declaration, the method SHALL throw `WordError.disallowedElement(elementName)`.

#### Scenario: Replace with single-paragraph fragment

- **WHEN** `replaceContentControlContent(id: 100000, contentXML: "<w:p><w:r><w:t>Hello</w:t></w:r></w:p>")` is called
- **THEN** the ContentControl's `<w:sdtContent>` now contains one paragraph with text "Hello"

#### Scenario: Reject nested SDT

- **WHEN** `replaceContentControlContent` is called with `contentXML` containing `<w:sdt>`
- **THEN** the method throws `disallowedElement("w:sdt")`

### Requirement: WordDocument.deleteContentControl removes SDT with optional content preservation

The `WordDocument` model SHALL expose a `deleteContentControl(id: Int, keepContent: Bool = true) throws` method.

When `keepContent=true`, the method unwraps the ContentControl's children (runs, paragraphs, or tables) into the parent container at the SDT's former position.

When `keepContent=false`, the method removes the ContentControl and all its children.

If the id is not found, the method SHALL throw `WordError.contentControlNotFound(id)`.

#### Scenario: Delete with keep_content preserves inline text

- **GIVEN** a paragraph with runs ["Before", SDT(id=100000, content="middle"), "After"]
- **WHEN** `deleteContentControl(id: 100000, keepContent: true)` is called
- **THEN** the paragraph's runs are ["Before", "middle", "After"]

#### Scenario: Delete without keep_content removes content

- **GIVEN** the same paragraph
- **WHEN** `deleteContentControl(id: 100000, keepContent: false)` is called
- **THEN** the paragraph's runs are ["Before", "After"]

### Requirement: WordDocument.allocateSdtId uses max-plus-one strategy

The `WordDocument` model SHALL expose a `allocateSdtId() -> Int` method that returns `max(existing_sdt_ids) + 1`, or `1` if no SDTs exist. The method SHALL walk the entire document tree (including nested SDTs inside tables, headers, footers, and comments) to compute the maximum.

The method SHALL cache the computed max on first call and maintain it via `+1` on subsequent calls within the same Document session. Cache invalidation happens when the document is re-read from disk.

#### Scenario: Empty document allocates id 1

- **GIVEN** a WordDocument with no SDTs
- **WHEN** `allocateSdtId()` is called
- **THEN** the return value is `1`

#### Scenario: Existing SDTs with sequential ids

- **GIVEN** a WordDocument with SDT ids [1, 2, 3]
- **WHEN** `allocateSdtId()` is called
- **THEN** the return value is `4`

#### Scenario: Existing SDTs with random ids from v3.7.x

- **GIVEN** a WordDocument with SDT ids [456789, 123456, 789012]
- **WHEN** `allocateSdtId()` is called
- **THEN** the return value is `789013`

### Requirement: ContentControl model supports nested children

The `ContentControl` struct SHALL include a `children: [ContentControl]` field to represent nested SDTs. When a ContentControl has `type=.group` or `type=.repeatingSection`, it MAY hold nested ContentControls as children.

The struct SHALL include a `parentSdtId: Int?` field for upward traversal. Top-level SDTs have `parentSdtId=nil`.

#### Scenario: Group with two plain-text children

- **GIVEN** a group ContentControl (id=100) containing two plain-text ContentControls (ids=101, 102)
- **WHEN** the parent's `children` is accessed
- **THEN** it returns two ContentControls with `parentSdtId=100`

### Requirement: RepeatingSection model supports item-level update

The `RepeatingSection` struct SHALL expose `updateItem(atIndex: Int, newText: String) throws` for modifying a single item's text content. Out-of-range index SHALL throw `WordError.repeatingSectionItemOutOfBounds(index, count)`.

#### Scenario: Update middle item

- **GIVEN** a RepeatingSection with items ["A", "B", "C"]
- **WHEN** `updateItem(atIndex: 1, newText: "B-updated")` is called
- **THEN** the section's items are ["A", "B-updated", "C"]

### Requirement: RepeatingSection emits allowInsertDeleteSections attribute

The `RepeatingSection` struct SHALL include an `allowInsertDeleteSections: Bool` property (default `true`) that emits `<w15:repeatingSection w15:allowInsertDeleteSections="1|0"/>` in `toSdtPrXML()`.

#### Scenario: Disabled insert/delete

- **GIVEN** a RepeatingSection with `allowInsertDeleteSections=false`
- **WHEN** `toSdtPrXML()` is called
- **THEN** the output contains `<w15:repeatingSection w15:allowInsertDeleteSections="0"/>`

