# docflow — CLAUDE.md

> Git-flow analog for documents — semantic synthesis, multi-version comparison, evidence-after-commit workflows for academic writing & ML notebooks.

## Purpose

把 git 的 mental model（branch / merge / diff / log / blame）套到 document workflow，但作用層是 **semantic 不是 line-level**。

典型場景：學生作業 vs 老師 reference、原 draft vs reviewer 意見、本年 lecture vs 去年 lecture、英中雙語版同步。

**不是 git replacement** — git 已經很會處理 line-level diff/merge；docflow 處理 git 不擅長的「dimension-level semantic blend」。

## Skills

| Skill | 用途 | Status |
|-------|------|--------|
| `/docflow:doc-synth` | Semantic synthesis between 2+ document versions（按 dimension 挑優整合） | **v1.0** ✓ |
| `/docflow:doc-compare` | N-dimensional side-by-side comparison.md 自動產出 | TODO |
| `/docflow:doc-verdict` | N versions per-question master_verdict.md 表格 | TODO |
| `/docflow:doc-multiimpl` | 強制 N alternative 都跑完整 implementation 再 commit | TODO |

## Supported formats

- `.tex` — section-based dimension extraction
- `.md` — heading-based dimension extraction
- `.ipynb` — cell-based dimension extraction
- `.docx` — section-based via `che-word-mcp` integration

## Mental model

| Action | git | docflow |
|---|---|---|
| Branch | 多 file copy（A.tex / B.tex / C.tex） | 同 |
| Diff | line-level | dimension-level（section / heading / cell） |
| **Merge** | line-level auto + conflict markers | **semantic：user 按 dimension 挑 take A / B / hybrid** |
| Log | commit history | provenance sidecar `<output>.synth.json` |
| Blame | line → commit | dimension → source doc |

## Development

- Plugin structure: see [official plugin-dev](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/plugin-dev)
- Update after changes: `/devtools:plugin-update docflow`
- Health check: `/devtools:plugin-health`
- Local iterate: `claude --plugin-dir ./plugins/docflow`（在本 repo 根目錄執行）

## 設計起源

`kiki830621/2026-winston` session（ASSG3 retrospective revision + ML HW2 final_v2 won't-fix + 「merge vs synthesis vs revision」術語討論，2026-05-12）。當時手動做了 3 次 comparison.md + 1 次 master_verdict.md + 1 次 multi-impl pilot，發現工作流可以 systematize 成 plugin。
