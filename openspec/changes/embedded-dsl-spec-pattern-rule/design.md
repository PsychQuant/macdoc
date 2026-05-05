## Context

`mdocx-syntax` (sibling change, slated to be moved to canonical specs after this one) produced the first embedded-DSL spec in this repo: `openspec/specs/mdocx-grammar/spec.md` with 15 Requirements, 36 Scenarios, 5 SBE Examples, and a non-normative composition tree in the corresponding design.md. The choice to use Requirements + Scenarios + Examples (rather than EBNF / PEG / context-free grammar notation) was made implicitly during that change — driven by two facts:

1. The DSL's grammar is enforced by the Swift compiler via `@resultBuilder` + protocol conformance + typed parameters. There is no separate parser to specify with a context-free grammar.
2. The reverse direction (`OOXML` to DSL source) needs to satisfy testable behavioural scenarios (round-trip equality, byte-equal IDs), not parse-validity rules.

The pattern works, but it is undocumented. Future embedded DSLs in macdoc — `.mpdf` (PDF document scripts), `.mbib` (bibliography APA scripts), `.mpptx` (PowerPoint scripts), and any further authoring surfaces that share the m-prefix family from `extension-first-dsl.md` — will face the same "what shape should the spec take?" question. Without a recorded rule, the next author will either:

- Default to EBNF / PEG out of academic instinct, producing notation that doesn't match how the host-language compiler enforces the syntax (and that the reverse transcoder cannot be tested against), or
- Re-derive the same pattern from scratch, inconsistently with `mdocx-grammar`.

Related existing rules:

- `.claude/rules/extension-first-dsl.md` covers the file-extension naming contract and AI-as-default-author principle. It does not cover spec shape.
- `.claude/rules/heuristic-output.md` covers converter output discipline. Unrelated to spec shape.
- `.claude/rules/native-macos-compat.md` covers framework choice. Unrelated.

There is currently no rule covering "given you have an embedded DSL, what should its Spectra spec look like?" — this change fills that gap.

## Goals / Non-Goals

**Goals:**

- Codify the embedded vs external DSL distinction so future authors classify their DSL correctly before writing the spec.
- Lock the spec composition for embedded DSLs (Requirements + Scenarios + SBE Examples + non-normative composition tree in design.md) so future embedded DSL specs are structurally consistent with `mdocx-grammar`.
- Standardise the composition-tree notation conventions (`[A | B]*`, `[X]+`, body-arrow, nesting-prefix) so trees across different DSL specs read uniformly.
- Cross-reference the new rule from `extension-first-dsl.md` (companion rule on file-extension contracts) and `docs/swift-as-document-source.md` (narrative DSL design) so authors landing on the existing artefacts find the spec-shape rule when they need it.

**Non-Goals:**

- Prescribing spec shape for external DSLs (with their own parser like SQL, regex, or custom config languages). External DSLs may legitimately need EBNF / PEG; this rule is scoped to embedded DSLs only.
- Prescribing implementation patterns for embedded DSLs (e.g., how to write `@resultBuilder` types, how to design op-log envelopes). Those belong in implementation-specific design.md or capability specs, not in a meta-rule.
- Modifying the existing `mdocx-grammar` spec. It already conforms to the pattern this rule codifies; the rule is descriptive of what already works.
- Modifying `extension-first-dsl.md` substantively. Only a short cross-reference is added.
- Defining how to write specs for non-DSL capabilities. The general Spectra spec template covers those; this rule adds embedded-DSL-specific guidance only.

## Decisions

### Decision 1: Embedded vs external DSL distinction is the rule's first gate

The rule MUST open with a decision tree that classifies the candidate DSL as embedded (host language enforces syntax via type system / result builder / macros) or external (custom parser consumes a separate grammar). Only the embedded branch is in scope; the external branch points to "use EBNF / PEG / your parser-generator's input format as appropriate" and exits.

**Rationale**: The whole point of this rule is to stop authors from defaulting to EBNF for embedded DSLs. The first sentence the author reads must establish the classification.

**Alternatives considered:**

- *Cover both embedded and external in one rule*. Rejected: doubles the rule's surface, dilutes the embedded-specific guidance, and external-DSL spec shape is well-covered by parser-generator literature outside this repo.
- *Make the distinction implicit and dive straight into pattern*. Rejected: an author with a custom parser would silently apply the wrong template.

### Decision 2: Spec composition is Requirements plus Scenarios plus SBE Examples plus non-normative composition tree

The rule MUST prescribe four ingredients for embedded DSL specs:

1. **Requirements** (normative SHALL / MUST language) — one per locked grammar decision.
2. **Scenarios** (WHEN / THEN under each Requirement) — testable behavioural assertions.
3. **SBE Examples** (`##### Example:` blocks) — concrete GIVEN / WHEN / THEN with literal source / output values, used as parameterised test inputs.
4. **Composition tree** (in design.md, non-normative) — ASCII visualisation of legal child sets per layer.

EBNF, PEG, BNF, ABNF, and similar context-free-grammar notations MUST NOT be used.

**Rationale**: This is the shape `mdocx-grammar` proved out. Requirements plus Scenarios are how Spectra specs express normative behaviour; SBE Examples make scenarios executable as tests; composition tree provides the bird's-eye view that flat Requirements lists obscure. EBNF would describe a parser that does not exist (the host compiler is the parser).

**Alternatives considered:**

- *Composition tree in spec.md instead of design.md*. Rejected: spec.md uses normative SHALL / MUST language; mixing in non-normative visualisation dilutes the normative voice. design.md is already the home for rationale plus visual aids.
- *Allow optional EBNF appendix*. Rejected: opens the door to EBNF-as-normative drift and creates two sources of truth for the same grammar.
- *Composition tree as required artefact only when DSL has 3+ layers*. Rejected: arbitrary threshold; any embedded DSL benefits from the visualisation.

### Decision 3: Composition tree notation conventions

The rule MUST standardise the notation used in composition trees so trees across DSLs read uniformly:

- `[A | B]*` — zero or more of either A or B.
- `[X]+` — one or more of X.
- A right-arrow glyph between a container name and its body — container body / "expands to".
- A box-drawing nesting prefix (filesystem-tree style) — child element nested under its parent.
- Each leaf annotates whether it is a leaf (no children, no text) or a container (and what its body shape is).
- Each non-obvious node carries a "Reading hints" cross-reference to the corresponding Decision or Open Item that explains why the structure is non-obvious.

**Rationale**: Without standardisation, each tree invents its own notation and readers re-learn the conventions per spec. The notation choices (regex-like alternation plus filesystem-style nesting plus arrow for body) are immediately legible to the target audience (AI authors plus human reviewers) without a notation legend.

**Alternatives considered:**

- *Use Mermaid diagrams or graphical trees*. Rejected: graphical formats render unreliably across markdown viewers (GitHub vs IDE vs terminal), don't paste cleanly into AI prompts, and are heavyweight for the small trees typical of an embedded DSL.
- *Adopt EBNF-style production rule notation but call it "tree"*. Rejected: defeats the purpose by reintroducing parser-grammar mental model.

### Decision 4: Cross-references go both ways

The new rule MUST cross-reference `extension-first-dsl.md` (companion rule) and `mdocx-grammar` spec (reference implementation). The existing `extension-first-dsl.md` MUST be updated with a cross-reference back to the new rule, and `docs/swift-as-document-source.md` §10 MUST add a cross-reference to the new rule, so any author landing on extension-naming or narrative DSL design finds the spec-shape rule.

**Rationale**: Rules are useless if the author doesn't find them at the moment of need. The natural entry point for embedded DSL design is either "I need an extension" (extension-first-dsl.md) or "I'm thinking about how the Swift script should look" (swift-as-document-source.md). Both must point to the spec-shape rule.

**Alternatives considered:**

- *Single cross-reference from extension-first-dsl.md only*. Rejected: misses authors who arrive via the narrative design doc.
- *Add cross-reference from CLAUDE.md*. Rejected: CLAUDE.md is already large; meta-rule cross-references don't belong at the top-level entry doc.

## Risks / Trade-offs

- *Rule outgrows its scope when next embedded DSL is materially different from `.mdocx`* — Mitigation: the rule is opt-in for embedded DSLs that match the same pattern (Swift `@resultBuilder` plus reverse-direction transcoder). When `.mpdf` / `.mbib` / `.mpptx` land, if their architecture diverges (e.g., they don't have a reverse transcoder), this rule is updated to either narrow its scope or expand to cover the new variant.
- *EBNF prohibition is too rigid for hybrid cases* — Acknowledged: a future DSL might legitimately mix embedded host syntax with a small string-literal mini-grammar (e.g., a query expression embedded as a string). In that case, the EBNF appendix MAY apply only to the mini-grammar string contents, NOT to the embedded DSL's structural grammar. Rule will note this exception path explicitly.
- *Rule duplicates content from `mdocx-grammar` spec and design.md* — Acknowledged: some duplication is intentional (the rule must be self-contained for new authors). Cross-references replace bulk duplication where possible; the composition-tree notation conventions appear once in the rule and are referenced (not copied) into each DSL's design.md.
- *Author skips the rule and writes EBNF anyway* — Mitigation: the analyzer cannot enforce this directly. Discovery via cross-references is the primary control; secondary control is review (any future DSL spec PR should be reviewed against this rule).

## Open Questions

(no open decisions — all four Decisions above are locked.)

## Follow-ups discovered during apply

- **Drift record** (task 3.1 reverse-verification against `mdocx-grammar`): the existing `mdocx-grammar` spec.md has no header note linking back to `.claude/rules/extension-first-dsl.md` and `.claude/rules/embedded-dsl-spec-pattern.md`. Requirement 4 of this change's spec prescribes the new spec SHALL carry such a note. The drift is acknowledged: per this change's Non-Goals ("Modifying the existing `mdocx-grammar` spec"), the retro-fit is deferred. Follow-up: when the next change touches `mdocx-grammar` (most naturally the archive of `mdocx-syntax` into `openspec/specs/mdocx-grammar/spec.md`, or the first `word-aligned-state-sync` Phase 7 implementation change that re-opens the spec), add the header note then. Future embedded DSL specs (`.mpdf`, `.mbib`, `.mpptx`) MUST include the note from day one — they are governed by the rule from inception, not retro-fitted.
