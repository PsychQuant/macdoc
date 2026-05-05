## 1. Author the rule file

These tasks fill `.claude/rules/embedded-dsl-spec-pattern.md` section by section. The file is created in task 1.1 and successive tasks append sections in spec-defined order. Sections within the same file MUST be authored sequentially (single-file edits cannot run parallel).

- [x] 1.1 Create `.claude/rules/embedded-dsl-spec-pattern.md` with frontmatter / opening preamble that names the rule, states its scope (embedded DSL specs only), and links to `mdocx-grammar` spec as the reference implementation; covering Decision 1: Embedded vs external DSL distinction is the rule's first gate and Requirement "Embedded versus external DSL classification gate"
- [x] 1.2 Append the spec composition section to `.claude/rules/embedded-dsl-spec-pattern.md` listing the four ingredients (Requirements + Scenarios + SBE Examples + non-normative composition tree) and the EBNF / PEG / BNF / ABNF prohibition with the string-literal mini-language exception; covering Decision 2: Spec composition is Requirements plus Scenarios plus SBE Examples plus non-normative composition tree and Requirement "Embedded DSL spec composition"
- [x] 1.3 Append the composition tree notation section to `.claude/rules/embedded-dsl-spec-pattern.md` with the standardised glyphs (`[A | B]*`, `[X]+`, body-arrow, box-drawing nesting prefix), leaf-vs-container annotation rule, and "Reading hints" cross-reference rule, plus the prohibition on graphical tree formats (Mermaid / Graphviz / SVG); covering Decision 3: Composition tree notation conventions and Requirement "Composition tree notation conventions"
- [x] 1.4 Append the cross-reference discoverability section to `.claude/rules/embedded-dsl-spec-pattern.md` describing the bidirectional cross-reference contract between the rule, the file-extension table in `extension-first-dsl.md`, the narrative design doc, and the new capability spec; covering Decision 4: Cross-references go both ways and Requirement "Cross-reference discoverability from companion artefacts"

## 2. Update existing artefacts to point at the new rule

These tasks update files that an author looking for embedded DSL guidance will plausibly land on first, so they discover the new rule.

- [x] 2.1 [P] Update `.claude/rules/extension-first-dsl.md` to add a "Related rules" cross-reference subsection (or append to an existing related-rules block) linking to `.claude/rules/embedded-dsl-spec-pattern.md`, and update the row for `.mdocx` in the "已註冊副檔名" table to also link the `mdocx-grammar` capability spec as the reference implementation example
- [x] 2.2 [P] Update `docs/swift-as-document-source.md` §10 (the `.mdocx` extension reasoning section) with a sentence-level cross-reference link pointing readers to `.claude/rules/embedded-dsl-spec-pattern.md` for the spec-shape rule when they next need to write a grammar specification

## 3. Verify the rule works on a real example

- [x] 3.1 Walk through `openspec/specs/mdocx-grammar/spec.md` against each of the four Requirements in the new rule, confirming the existing spec already conforms (it is the reference implementation); record any drift between the rule's prescribed shape and the existing spec, and either correct the rule or flag the drift for a follow-up change
