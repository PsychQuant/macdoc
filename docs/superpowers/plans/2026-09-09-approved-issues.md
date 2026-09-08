# Approved macdoc issues implementation

User-approved 2026-09-09. Repo: PsychQuant/macdoc. Branch base 28d87d0.

## Global Constraints

Use Taiwan Traditional Chinese. Preserve existing work. No release, merge or issue close. Every commit references its scoped issue. No edits to .build/checkouts. Worktree-only implementation. Use test-first RED/GREEN and independent review.

## Task 1: CLI binary resolution (#187)

Implement the approved detailed plan at docs/superpowers/plans/2026-09-09-issue-187.md. Its old Draft / no-PlanMode paragraphs are superseded by user's explicit implementation request. Use debug/release build configuration, MACDOC_TEST_BINARY absolute executable override, no fallback, test-runner-only path logging, regression tests for all helper consumers. Adapt throwing getter callers. Do not change independent DocxIntegration behavior.

## Task 2: Portable bibliography tests (#186)

Three bib-apa-to-{html,json,md}-swift packages: committed synthetic .bib fixture via Bundle.module resources; four previously external-path end-to-end tests must execute with explicit per-format title/subtitle/link/anchor/JSON assertions. No missing-file skips. Test all three suites from clean build, guard #183 SUBTITLE regression.

## Task 3: Discoverable paragraphs-only (#181)

Follow approved detailed issue-181 plan. Default reverse emits conditional stderr only for document.xml paragraph-no-paraId; preserve coverage stdout and no duplicate. Test all other causes and modes. Update skill and plugin manifests accurately, leave binary_version at released value. No production release.

## Task 4: Document profiles (#185)

First write spec and track upstream dependencies. CLI/MCP share config.json profiles inherit/official; public pure formatting profile API in OOXML layer, no implicit config reads there. Official imports current Normal.dotm once as format-only immutable snapshot, A4 12pt styles/theme/paragraphs/margins then override Traditional Chinese font to 標楷體; no macros/body/PII/external links. Inherit preserves documents and omits new-document fonts without reading Normal. Explicit per-call selection overrides config. Existing edit/replay only changes profile when explicit. Missing/corrupt official snapshot fails. AI/OCR config writes must preserve unknown/document keys. Verify Mac and Windows Word where available; unavailable validation remains incomplete.

