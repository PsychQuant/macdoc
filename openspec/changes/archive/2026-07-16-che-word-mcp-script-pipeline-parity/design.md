## Context

The script pipeline's authority chain: ooxml-swift owns the transcoders (ReverseExtractor / ScriptExporter / ScriptImporter, v1.4.0), macdoc's word reverse CLI is a thin wrapper over them, and the acceptance semantics (Stage B byte-equal, dual-track coverage, strict slots) are pinned in the `ooxml-script-transcode` and `template-content-slots` specs. che-word-mcp sits outside this chain: pinned to ooxml-swift 0.24 (semver cap < 1.0.0), single 16,100-line Server.swift, 242 snake_case tool definitions, none of them pipeline verbs.

Hard facts from the #134 diagnosis: (a) trial dependency resolution fails — latex-math-swift 0.1.0 requires ooxml-swift < 1.0.0, word-to-md-swift likewise; (b) macdoc's own graph already builds word-to-md-swift against ooxml main (= v1.4 commit) because word-builder-swift declares a branch requirement that overrides the whole graph — proving word-to-md-swift's source 1.4-compatible; (c) latex-math-swift has no macdoc-side consumer, so its 1.4 compatibility is unproven. User decisions locked in #134's Clarity Surface + the discuss convergence: interface AND behavior parity; migration bundled in this change; three named tools; 0.x minors for intermediaries.

## Goals / Non-Goals

**Goals:**

- MCP users drive the full imitation pipeline (reverse → coverage → slots → rebuild) without leaving Claude, with the same guarantees as the CLI.
- Byte-for-byte behavior parity between MCP and CLI outputs for the same docx, guaranteed structurally (shared code path) and guarded by tests.
- che-word-mcp lands on the ooxml-swift 1.x line, ending the four-minor-line capability drift.

**Non-Goals:**

- Op-based rewrite of existing tools (deprecation warnings tolerated; separate line).
- Any change to CLI behavior or to the ooxml-swift transcoders themselves.
- 1.0 releases for latex-math-swift / word-to-md-swift.
- pptx pipeline surfaces.

## Decisions

**Decision 1 — Parity by construction: handlers call the same transcoder entry points as the CLI.** The three tool handlers wrap ReverseExtractor.reverse / ScriptExporter.exportSwift(log:slots:) / ScriptImporter.parse + WordDocument.apply + writeAuthoringPackage — the exact APIs MacDoc+Word.swift uses. No logic is reimplemented in the MCP layer. Alternative rejected: implementing pipeline logic in Server.swift and asserting parity by comparison tests only — comparison tests catch drift after it happens; a shared code path prevents it from existing.

**Decision 2 — Tool contract (frozen at first release).** Names and schemas follow the 242-definition convention (snake_case, verb-first, no prefix):
- export_script(source_path, output_path, slots?: [{name, para_id}]) → summary {dsl_parts, form_gaps_empty, slot_count}. The CLI's paragraphs-only legacy mode is deliberately NOT exposed: its implementation is macdoc-side (not shared-library), so offering it would force the MCP layer to reimplement logic (violating Decision 1), and it carries no byte-equal guarantee — contrary to this change's parity goal.
- get_script_coverage(source_path) → {parts: [{part_path, channel, bytes, dsl_ratio}], aggregate_ratio}
- execute_script(script_path, output_path, verify_byte_equal_against?: path) → {written, verified?: bool, broken_parts?: [path]}
Strict-mode failures (unknown para_id, non-substitutable slot target, transcode errors) surface as MCP tool errors carrying the underlying TranscodeError description — never silent degradation. Alternative rejected: a single multiplexed script_pipeline tool with a mode parameter — breaks the one-verb-one-tool convention of the existing surface and makes schemas union-typed.

**Decision 3 — Dependency versioning: intermediaries release 0.x minors.** latex-math-swift and word-to-md-swift bump their ooxml requirement to from: 1.4.0 and release the next 0.x minor. A dependency's major bump is not a breaking change of their own API surface; 0.x semver carries no stability contract that would force 1.0 ceremony. Alternative rejected: promoting both to 1.0 — orthogonal decision with its own obligations, not needed to unblock resolution.

**Decision 4 — Migration scope: hard breaking only.** Fix what stops compilation/tests on 1.4 (RunProperties.rawChildren removal, tree-only IO path adjustments); leave direct-typed-mutation deprecation warnings in place. Evidence this is bounded: word-to-md-swift compiles green against 1.4 using the same model APIs. Alternative rejected: opportunistic op-based migration of touched tools — scope creep into a 16,100-line file under a parity deadline.

**Decision 5 — New handlers live in a new file; Server.swift only gains registrations.** ScriptPipelineTools.swift holds the three handlers + shared helpers; Server.swift gets the tool registrations wired into its existing list. Rationale: Server.swift is already 16,100 lines; the repo's single-file architecture is historical, not normative, and registration-plus-satellite-file is the lowest-friction incremental structure. Alternative rejected: inline growth of Server.swift (compounds the maintenance problem this line keeps paying for).

**Decision 6 — Two-layer parity guard.** Layer 1 (CI-runnable): in-process test builds a five-layer synthetic docx via typed ops, runs export → execute through the MCP handler functions, asserts Stage B byte-equality via PartFidelity. Layer 2 (maintainer-gated): with MACDOC_TEMPLATE_DIR and a macdoc binary present (MACDOC_CLI_PATH), run the real JPA template through the MCP handlers and through the CLI, assert the exported scripts and the rebuilt docx part sets are byte-identical. Layer 2 skips loudly when either gate is absent. Alternative rejected: only cross-checking against the CLI — couples CI to a macdoc build; only in-process — never exercises the actual CLI equivalence claim.

**Decision 7 — Release chain order is a dependency order, not a preference.** latex-math-swift release → word-to-md-swift release → che-word-mcp (bump + migration + tools + tests) → make release-signed (Developer ID + notarize, keychain profile che-mcps-notary) → macdoc marketplace bump of plugins/che-word-mcp plugin.json version + binary_version and marketplace.json (#116: binary_version changes only on binary release — this IS a binary release). Skipping the marketplace step leaves users' wrappers downloading the old binary.

## Implementation Contract

**Behavior.** After this change, an MCP client connected to che-word-mcp can: (1) call export_script on a real Word docx and receive a full-fidelity `.mdocx.swift` script identical byte-for-byte to what macdoc word reverse produces for the same inputs; (2) call get_script_coverage and read the same per-part and aggregate numbers the CLI --coverage report prints; (3) call execute_script and get a rebuilt docx that is Stage-B byte-equal to the reference (and, when verify_byte_equal_against is passed, a verified: true/false verdict with the broken part list on false); (4) designate slots at export and substitute content at execute time with strict-mode failures surfacing as tool errors.

**Interface / data shape.** Tool names and schemas per Decision 2, registered alongside the existing tools. Slot designations: array of objects with name (lowercase Swift identifier) and para_id (w14:paraId hex string). Coverage rows: part_path, channel ("dsl" | "raw"), bytes, dsl_ratio in [0,1].

**Failure modes.** Dependency resolution failures are impossible post-chain (pins verified in tests via swift package resolve in CI). Transcode strict-mode errors map to MCP error responses with the TranscodeError description; file-not-found and unwritable-output map to the server's existing path-error conventions. The Layer-2 parity test skips (not fails) without its gates; the Layer-1 parity test has no gate and must always run.

**Acceptance criteria.** (a) All existing che-word-mcp tests green on ooxml-swift 1.4.0; (b) Layer-1 parity test green in plain swift test; (c) Layer-2 parity test green on the maintainer machine against the JPA template; (d) 90_template_ja document.xml reports per-part dsl_ratio 1.0 through get_script_coverage; (e) signed release published and marketplace manifests bumped per #116.

**Scope boundaries.** In: two intermediary manifest bumps + releases, che-word-mcp migration, three tools, parity tests, release + marketplace sync. Out: existing-tool reshaping, op-based migration, CLI changes, ooxml-swift changes, pptx.

## Risks / Trade-offs

- [latex-math-swift breakage unknown until its bump builds] → it is the first task; if breakage is large the change pauses there and the estimate is revised before touching che-word-mcp (user already bundled migration in-scope, so this is sequencing, not scope, risk).
- [Server.swift migration surface unknown until resolution unblocks] → bounded by Decision 4 (hard breaking only) and by the word-to-md-swift compatibility evidence; if a tool's behavior regresses under 1.4 the existing per-tool tests catch it.
- [Marketplace sync forgotten after release] → release task explicitly includes the /plugin-update step per common-release-flow.md; acceptance (e) makes it un-skippable.
- [MCP payloads for large docx (16MB+ scripts)] → export_script writes to output_path on disk and returns a summary, never inlines script text in the response; execute_script likewise returns paths + verdicts.

## Migration Plan

Order: latex-math-swift 0.2.0 (or next minor) → word-to-md-swift next minor → che-word-mcp Package.swift bumps all three → swift package clean (payload struct layouts changed across the 0.x→1.x line) → migration fixes → tools + tests → make release-signed → macdoc marketplace bump. Rollback: che-word-mcp is a leaf consumer; reverting its Package.swift pin restores the old build, and intermediary releases are additive (no consumer is forced to move).

## Open Questions

- None blocking. The exact next-minor version numbers for the two intermediaries are read from their repos' latest tags at implementation time.
