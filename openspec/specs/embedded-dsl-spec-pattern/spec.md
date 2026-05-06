# embedded-dsl-spec-pattern Specification

## Purpose

TBD - created by archiving change 'embedded-dsl-spec-pattern-rule'. Update Purpose after archive.

## Requirements

### Requirement: Embedded versus external DSL classification gate

Before writing a Spectra spec for any new domain-specific language (DSL) authoring surface in this repo, the author SHALL classify the DSL as either embedded or external. The classification SHALL be performed against this binary criterion: a DSL is embedded when its syntax is enforced at compile time by the host programming language's type system, result builders, or macros (no separate parser exists); a DSL is external when a custom parser consumes a separate grammar at runtime or build time.

This rule SHALL apply only to embedded DSLs. External DSLs are out of scope; their specs MAY use any grammar notation appropriate to the parser-generator in use (EBNF, PEG, ABNF, BNF, or hand-written parser combinators) and SHALL NOT be governed by this rule.

#### Scenario: Swift result-builder DSL classified as embedded

- **WHEN** the candidate DSL is a Swift `@resultBuilder` plus protocol-conforming types whose nesting is enforced by Swift's type checker (e.g., `WordDocument { Section { Paragraph { ... } } }`)
- **THEN** the author SHALL classify it as embedded
- **AND** SHALL apply this rule's spec-shape requirements to the resulting capability spec

#### Scenario: Hand-written parser for separate grammar classified as external

- **WHEN** the candidate DSL is a separate text format consumed by a hand-written or generator-built parser at runtime (e.g., a `.bib` file consumed by a BibLaTeX parser)
- **THEN** the author SHALL classify it as external
- **AND** SHALL NOT apply this rule's spec-shape requirements; the spec MAY use EBNF or PEG as appropriate

##### Example: classification table

| Candidate DSL                                                        | Classification | Reason                                                       |
| -------------------------------------------------------------------- | -------------- | ------------------------------------------------------------ |
| Swift `@resultBuilder` for `.mdocx`                                  | Embedded       | Swift compiler enforces nesting via type checker             |
| Swift macro expanding to typed AST nodes                             | Embedded       | Swift compiler validates expansion at compile time           |
| TypeScript JSX-style component tree                                  | Embedded       | TypeScript compiler enforces props and children types        |
| Standalone text format with custom recursive-descent parser          | External       | Parser is the syntax authority, runs at parse time           |
| Mini-language inside a string literal (e.g., regex, SQL, glob)       | External       | String contents have their own parser independent of host    |
| YAML / JSON config with schema validation                            | External       | YAML / JSON parser is the syntax authority                   |


<!-- @trace
source: embedded-dsl-spec-pattern-rule
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093007.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-144550.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143856.log
-->

---
### Requirement: Embedded DSL spec composition

A capability spec for an embedded DSL SHALL contain four ingredients and SHALL NOT contain context-free grammar notation:

1. **Requirements**: one `### Requirement: <name>` block per locked grammar decision, written in normative SHALL / MUST language.
2. **Scenarios**: at least one `#### Scenario: <name>` block per Requirement, written in WHEN / THEN form, expressing testable behavioural assertions.
3. **SBE Examples**: at least one `##### Example: <name>` block per non-trivial Requirement, providing concrete GIVEN / WHEN / THEN values usable as parameterised test inputs. A Requirement is non-trivial when it involves data transformation, ordering, structural composition, or boundary conditions.
4. **Composition tree**: a non-normative ASCII visualisation of the legal child set at each DSL layer, placed in the change's `design.md` (NOT in `spec.md`), under a section heading such as "Grammar reference (composition tree)".

Context-free-grammar notations (EBNF, PEG, BNF, ABNF, similar production-rule formalisms) SHALL NOT appear in either the spec or the design for an embedded DSL. The single permitted exception is when the embedded DSL contains a string-literal mini-language whose contents have their own parser — in that case, EBNF MAY apply only to the mini-language string contents, NOT to the embedded DSL's structural grammar.

#### Scenario: spec contains all four ingredients

- **WHEN** an author writes the capability spec for a new embedded DSL
- **THEN** `specs/<capability>/spec.md` contains at least one Requirement, each Requirement contains at least one Scenario, each non-trivial Requirement contains at least one SBE Example
- **AND** the corresponding `design.md` contains a "Grammar reference (composition tree)" section

#### Scenario: EBNF in embedded DSL spec is rejected at review

- **WHEN** an author submits a spec containing an EBNF / PEG / BNF / ABNF production rule for the embedded DSL's structural grammar
- **THEN** the reviewer SHALL request removal and replacement with Requirements + Scenarios + composition tree
- **AND** the change SHALL NOT be archived until the formal-grammar block is removed

#### Scenario: EBNF for string-literal mini-language is permitted

- **WHEN** an embedded DSL accepts a string literal whose contents are parsed as a separate mini-language (e.g., a query expression, a date format, a regex)
- **THEN** the spec MAY include an EBNF / PEG block describing the mini-language string contents
- **AND** the spec MUST clearly delimit the EBNF block to the mini-language scope, NOT the embedded DSL's structural grammar


<!-- @trace
source: embedded-dsl-spec-pattern-rule
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093007.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-144550.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143856.log
-->

---
### Requirement: Composition tree notation conventions

The non-normative composition tree placed in `design.md` SHALL use a standardised notation so trees across different embedded DSL specs read uniformly. The notation SHALL be:

- `[A | B]*` denotes zero or more children, each of which is either A or B.
- `[X]+` denotes one or more X children.
- A right-arrow glyph between a container name and its body content denotes the body's legal child set ("expands to").
- A box-drawing nesting prefix (filesystem-tree style) denotes a child element nested under its parent.
- Each leaf SHALL be annotated with whether it is a leaf (no children, no text) or a container (and what its body shape is).
- Each non-obvious node SHALL carry a "Reading hints" cross-reference to the corresponding Decision or Open Item in the same `design.md` that explains why the structure is non-obvious.

Graphical tree formats (Mermaid, Graphviz, embedded SVG) SHALL NOT be used for the composition tree. ASCII text is the required form because it renders identically across markdown viewers, pastes cleanly into AI prompts, and stays in version control as plain text diff.

#### Scenario: tree uses standard alternation and nesting notation

- **WHEN** a `design.md` contains a composition tree
- **THEN** the tree SHALL use `[A | B]*` for zero-or-more alternation, `[X]+` for one-or-more, a right-arrow glyph for body expansion, and a box-drawing prefix for nesting
- **AND** SHALL NOT invent local notations or omit the conventions

#### Scenario: non-obvious nodes carry reading hints

- **WHEN** a tree node represents a structurally surprising decision (e.g., a DSL container that exists only at the DSL layer and inverts to a different OOXML structure on serialisation)
- **THEN** the tree SHALL include a "Reading hints" line below the tree that names the node and points to the Decision or Open Item explaining the surprise

##### Example: reference tree (excerpt from `mdocx-grammar` design.md)

- **GIVEN** an embedded DSL where `WordDocument` contains one or more `Section` containers, each `Section` contains a sequence of paragraphs and other block-level content
- **WHEN** the design.md visualises this composition
- **THEN** the tree SHALL render as:
  ```
  WordDocument
    [Section]+ nested under WordDocument
         [Paragraph | Table | Hyperlink | Bookmark | WordComponent]* nested under Section
  ```
  using the box-drawing prefix in place of "nested under" prose, with each layer annotated for leaf vs container shape, and a "Reading hints" footer naming `Section` (cross-reference to the Decision explaining why `Section` is a DSL container despite OOXML's marker structure)


<!-- @trace
source: embedded-dsl-spec-pattern-rule
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093007.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-144550.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143856.log
-->

---
### Requirement: Cross-reference discoverability from companion artefacts

When a new embedded DSL change introduces a capability spec governed by this rule, the change SHALL update at least two existing artefacts to cross-reference the new spec:

1. The repo's file-extension registration table in `.claude/rules/extension-first-dsl.md` SHALL include a row pointing to the new capability spec.
2. Any narrative design document that introduced the DSL informally (e.g., `docs/swift-as-document-source.md` for `.mdocx`) SHALL include a cross-reference link to the new capability spec, placed near the relevant section.

Conversely, the new capability spec SHALL cross-reference the existing rule files it inherits from (`.claude/rules/extension-first-dsl.md` and `.claude/rules/embedded-dsl-spec-pattern.md` itself) and the reference implementation spec (`mdocx-grammar` for the first cohort, the most recently archived embedded DSL spec for later cohorts).

#### Scenario: change updates extension-first-dsl table

- **WHEN** a change introduces an embedded DSL governed by this rule
- **THEN** the change's `tasks.md` SHALL include a task that updates `.claude/rules/extension-first-dsl.md` to add a row in the "已註冊副檔名" table
- **AND** the row SHALL link to both the narrative design doc (if any) and the new capability spec

#### Scenario: narrative design doc gets back-link

- **WHEN** an existing narrative design doc introduced the DSL informally before the spec was written
- **THEN** the change's `tasks.md` SHALL include a task that adds a cross-reference link from the narrative doc to the new capability spec
- **AND** the link SHALL appear at or near the section of the narrative doc that introduced the DSL surface

##### Example: cross-reference graph

- **GIVEN** an embedded DSL `.mxyz` with capability spec `xyz-grammar`, narrative doc `docs/swift-as-xyz-source.md`, and existing extension table at `.claude/rules/extension-first-dsl.md`
- **WHEN** the change archives
- **THEN** the cross-reference graph SHALL be:
  ```
  extension-first-dsl.md (table row for .mxyz) -- links to --> docs/swift-as-xyz-source.md AND specs/xyz-grammar/spec.md
  docs/swift-as-xyz-source.md (intro section) -- links to --> specs/xyz-grammar/spec.md
  specs/xyz-grammar/spec.md (header note) -- links to --> .claude/rules/extension-first-dsl.md AND .claude/rules/embedded-dsl-spec-pattern.md
  ```

<!-- @trace
source: embedded-dsl-spec-pattern-rule
updated: 2026-05-06
code:
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-084624.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-093007.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-144550.log
  - docs/swift-as-document-source.md
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143856.log
-->