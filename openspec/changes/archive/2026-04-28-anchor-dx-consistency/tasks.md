# Tasks — anchor-dx-consistency

Recommended order: helper → conflict detection (4 tools) → text_instance validation (4 spots) → tool-prefix sweep (4 tools only — global sweep is a separate `error-prefix-sweep` follow-up change) → tests → release. Each `## ` group ships as one commit.

Cross-references:
- **Spec deltas** (`specs/che-word-mcp-insertion-tools/spec.md`): R1 *Conflicting anchor parameters MUST be rejected with structured error*; R2 *text_instance MUST be ≥ 1 when explicitly specified*; R3 *Error messages from `return "Error: ..."` lines MUST be tool-prefixed*.
- **Design topics** (`design.md`): §1 *Conflict detection algorithm (#71)*; §2 *text_instance validation (#72)*; §3 *Tool-prefix error messages (#70)*; *Cross-cutting: backward-compat note* (SemVer rationale); *Cross-cutting: error message language*; *Test strategy*; *Out of scope (decisions made)*.

## Phase 1 — Helper + conflict detection

Implements spec requirement *Conflicting anchor parameters MUST be rejected with structured error* (R1) per design §1 *Conflict detection algorithm (#71)*.

- [x] 1.1 Add `detectPresentAnchors(_:anchors:)` static helper near top of `Server.swift` (above `dispatch()`); per-anchor type-aware predicate map per design §1. Foundation for spec requirement *Conflicting anchor parameters MUST be rejected with structured error*.
- [x] 1.2 Apply to `insertParagraph` (`Server.swift:6594-`): conflict check before existing dispatcher chain — implements spec R1 for `insert_paragraph`
- [x] 1.3 Apply to `insertEquation` display-mode branch (`Server.swift:8701-`): conflict check before display dispatcher (inline branch unchanged) — implements spec R1 for `insert_equation` display
- [x] 1.4 Apply to `insertImageFromPath` (`Server.swift:7829-`): conflict check before existing dispatcher — implements spec R1 for `insert_image_from_path`
- [x] 1.5 Apply to `insertCaption` (`Server.swift:12071-`): conflict check before existing dispatcher (caption-specific anchor set: `paragraph_index` / `after_image_id` / `after_table_index` / `after_text` / `before_text`) — implements spec R1 for `insert_caption`
- [x] 1.6 Update tool descriptions in 4 schema definitions to add: `"Specify exactly one anchor; multiple anchors return Error."` per design §1 surface change

## Phase 2 — text_instance validation

Implements spec requirement *text_instance MUST be ≥ 1 when explicitly specified* (R2) per design §2 *text_instance validation (#72)*.

- [x] 2.1 Add explicit-< 1 guard after `text_instance` read in `insertParagraph`, implementing spec requirement *text_instance MUST be ≥ 1 when explicitly specified* for `insert_paragraph`
- [x] 2.2 Same in `insertEquation` (display branch) — implements spec R2 for `insert_equation`
- [x] 2.3 Same in `insertImageFromPath` — implements spec R2 for `insert_image_from_path`
- [x] 2.4 Same in `insertCaption` — implements spec R2 for `insert_caption`

## Phase 3 — Tool-prefix sweep, scoped to 4 #61-target tools

Implements spec requirement *Error messages from `return "Error: ..."` lines MUST be tool-prefixed* (R3) per design §3 *Tool-prefix error messages (#70)*.

Per design §3 *Phasing*, this change covers only the 4 `#61`-target tools. The remaining ~41 `return "Error: ..."` lines elsewhere in `Server.swift` are tackled by a separate follow-up change `error-prefix-sweep` to keep this bundle under the 15-task scope guideline (see design *Out of scope (decisions made)*).

- [x] 3.1 Rewrite all `return "Error: ..."` in `insertParagraph` with `insert_paragraph:` prefix, implementing spec requirement *Error messages from `return "Error: ..."` lines MUST be tool-prefixed* for `insert_paragraph`
- [x] 3.2 Same for `insertEquation` (both display + inline branches; tool name `insert_equation`) — implements spec R3 for `insert_equation`
- [x] 3.3 Same for `insertImageFromPath` — implements spec R3 for `insert_image_from_path`
- [x] 3.4 Same for `insertCaption` — implements spec R3 for `insert_caption`

## Phase 4 — Tests (per design *Test strategy*)

- [x] 4.1 Create `Tests/CheWordMCPTests/AnchorDXConsistencyTests.swift`
- [x] 4.2 Conflict detection: 4 tools × 3 combinations = 12 sub-tests (validates spec R1 Scenarios)
- [x] 4.3 text_instance validation: 4 tools × {-1, 0} = 8 sub-tests (validates spec R2 Scenarios)
- [x] 4.4 Backward-compat happy path: 4 tools × 1 = 4 sub-tests asserting single-anchor still works (validates spec R1 *one anchor → unchanged behavior* Scenario)
- [x] 4.5 Tool-prefix mechanical regression pin: 1 grep-based sub-test on `Server.swift` source asserting zero un-prefixed `return "Error: ..."` lines in 4 target tools only (per design §3 *Phasing*; global pin is `error-prefix-sweep`'s job)
- [x] 4.6 Run full suite: expect 201 → 226 (+25, 0 fail / 9 skip)

## Phase 5 — Release artifacts (v3.16.0 — minor bump per design *Cross-cutting: backward-compat note + SemVer rationale*)

- [x] 5.1 `mcpb/manifest.json` 3.15.3 → 3.16.0; description prefix summarizing behavior change per design *Cross-cutting: backward-compat note*
- [x] 5.2 `CHANGELOG.md` v3.16.0 entry with explicit "BREAKING (input validation)" callout + migration guidance per design *Cross-cutting: backward-compat note*; error messages stay English per design *Cross-cutting: error message language*
- [x] 5.3 `swift build -c release`; rebuild mcpb bundle + bare binary; verify shasum identity
- [x] 5.4 `git tag v3.16.0 && git push origin main v3.16.0`
- [x] 5.5 `gh release create v3.16.0` upload mcpb + bare binary

## Phase 6 — Marketplace sync

- [x] 6.1 Bump `psychquant-claude-plugins/.claude-plugin/marketplace.json` che-word-mcp entry 3.15.3 → 3.16.0
- [x] 6.2 Bump `plugins/che-word-mcp/.claude-plugin/plugin.json` 3.15.3 → 3.16.0
- [x] 6.3 Description prefix v3.16.0 summary
- [x] 6.4 Commit + push + `claude plugin marketplace update` + `claude plugin update`

## Phase 7 — Issue close-out

- [x] 7.1 Post Implementation Complete to #71 (primary tracker for Bundle B)
- [x] 7.2 Pointer comments to #70 + #72 referencing #71's master URL (per pointer-URL SOP)
- [x] 7.3 Auto-update 3 issue bodies → phase: implemented
- [ ] 7.4 `/idd-verify` Bundle B (joint verify against #71)
- [ ] 7.5 `/idd-close` 3 issues per-issue (per Step 7 batch rule)

---

## Out-of-bundle handoff (NOT counted as tasks; tracked here for visibility — do NOT execute as part of `spectra-apply`)

These are follow-up workstreams referenced by this change's design but executed separately. They are intentionally written without `- [ ]` checkboxes so `spectra-apply` does not pull them into the active task list.

### Handoff A — close #67 as wontfix-with-rationale (separate small fix outside Spectra)

Per design *Out of scope (decisions made)*:

- Update `insertEquation` schema description to articulate why inline rejects anchors (run-inside-paragraph shape; semantics ill-defined)
- CHANGELOG entry explaining the rationale; close #67 as wontfix-with-rationale
- If a real workflow needs inline anchors later, design new explicit anchors (e.g. `inline_at_end_of_paragraph`, `inline_at_run_index`) as a separate Spectra change

### Handoff B — open `error-prefix-sweep` change (separate Spectra change after this archives)

Per design §3 *Phasing* — global sweep of the remaining 41 `return "Error: ..."` lines across ~50 unfamiliar handlers in Server.swift:

- Open new Spectra change `error-prefix-sweep` after this change archives
- Mechanical rewrite — group commits by logical tool family (paragraph CRUD / table CRUD / styles / etc.) for reviewability
- Extend Phase 4.5 grep regression pin to global scope (zero un-prefixed `return "Error: ..."` anywhere in Server.swift)
- Bundle as v3.16.x patch release (mechanical, no behavior change)
