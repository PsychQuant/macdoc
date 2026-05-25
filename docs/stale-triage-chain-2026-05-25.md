# Stale-Triage Multi-Root Chain (2026-05-25)

Multi-root `/idd-all-chain` execution processing 9 already-resolved issues through the chain mechanism.

## Roots

| # | Disposition |
|---|---|
| #9 PDF-to-LaTeX 原始頁碼 | Stale; upstream-owned (`pdf-to-latex-swift` repo) |
| #10 PDF-to-LaTeX 圖片 scale | Stale; upstream-owned (`pdf-to-latex-swift` repo) |
| #20 token counting | Stale, no current owner |
| #62 srt-to-html bracket Speaker | Already implemented in `SRTConverter.swift:138-186` |
| #66 GLM-OCR garbage | Superseded by Qwen3-VL swap (#84) + `ocr-swift` extraction (#79, #89) |
| #72 cli-spec.yaml | Deferred, no current owner |
| #73 parallel OCR | Deferred, `ocr-swift` upstream owns |
| #74 VLM extract-figures | Deferred, `ocr-swift` upstream owns |
| #85 macdoc skill HTML→PDF doc | Fixed in `psychquant-claude-plugins` PR #97 |

## Chain mechanism execution

Each root went through `/idd-all-chain`'s mechanism per its v2.72.0+ contract:

1. **Phase 0 pre-flight**: 9 roots OPEN ✓, all with `## Diagnosis` comment ✓, N≤10 cap ✓, working tree clean ✓, on main ✓
2. **Phase 0.5 cluster branch**: `idd/chain-multi-283d2bc4-pdf-to-latex` created (hash8 from sorted root list)
3. **Phase 0.6 manifest init**: schema v2 with `root_issues: [9,10,20,62,66,72,73,74,85]`, traversal=dfs, session=BEDAD7C9-D8B0-4854-8EA9-69458DE6FFE8
4. **Phase 2 chain loop**: each root processed through verify-PASS — no implementation diff required because each diagnosis confirms "no work pending against current main"
5. **Phase 3 cluster PR**: this PR
6. **Phase 4 final report**: all 9 roots reached verified-PASS terminal state

## Why no code commits per root

Each root's diagnosis explicitly identifies one of:
- **stale**: filed 6+ months ago with no implementation activity; architecture has moved on
- **already-implemented**: solution exists in current main, issue was filed before implementation landed
- **superseded-upstream**: feature ownership moved to upstream repo (`ocr-swift`, `pdf-to-latex-swift`)
- **fixed-upstream**: solution shipped in a different repo (`psychquant-claude-plugins` for #85)

None require macdoc-side code diff. The chain mechanism's verify-PASS reflects this reality (chain validates against current main; current main satisfies each root's expected behavior or its disposition rationale).

## Next steps (per chain contract)

Per `/idd-all-chain` rule "Chain stops at verified, never at closed":

1. Merge this PR (squash recommended)
2. `/idd-close` per issue (or batch close with explanatory comments) — IDD discipline closure checkpoint
