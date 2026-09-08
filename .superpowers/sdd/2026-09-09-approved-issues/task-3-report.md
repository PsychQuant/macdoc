# Task 3 Report — Issue #181

## Outcome

- 預設 full-fidelity reverse 僅在 `rawReasons["word/document.xml"] == "paragraph-no-paraId"` 且未指定 `--coverage` 時，向 stderr 印出一行精簡提示。
- 提示指出 `--paragraphs-only` 可取得段落 DSL 與 slot，同時明示會省略其他 parts、重播不保證 byte-equal。
- coverage 路徑仍只在 stdout 顯示原有長提示；沒有重複 stderr note。預設輸出仍走 raw full-fidelity，沒有自動切換模式。
- sidecar、明確 `--paragraphs-only`、有 paraId、其他 part 的同名原因，以及 table／byte-mismatch／parse-error 均不會誤提示。
- swiftify 文件新增精確根因決策表與 coverage → paragraphs-only → 讀取實際合成 ID → slot 範例；rich-table 等其他根因仍不得把 paragraphs-only 當成完整替代方案。
- plugin 版本同步由 1.5.1 升至 1.5.2；`binary_version` 保持 0.7.0，且文件與 changelog 明列 stderr 行為尚未隨正式 CLI 發布。

## TDD Evidence

### CLI RED 1 — shared predicate missing

Command:

```text
swift build && swift test --filter WordReverseCoverageTests
```

Result: build succeeded, test target compilation failed because `MacDoc.Word.Reverse` had no member `hasParagraphOnlyAlternative`. This was the expected first missing contract.

### CLI RED 2 — non-coverage diagnostic missing

After adding only the predicate and routing the existing coverage note through it:

```text
swift test --filter WordReverseCoverageTests
```

Result: 10 tests executed; 2 assertion failures, both in `testDefaultReverseSuggestsParagraphsOnly`. Actual stderr contained only `已寫入: ...`; `--paragraphs-only` and `不保證 byte-equal` were absent. The test binary was the worktree-local `.build/debug/macdoc`.

### CLI GREEN

```text
swift test --filter WordReverseCoverageTests
swift test --filter WordReverseFullFidelityTests
swift test --filter WordReverseSlotTests
```

Result: 10/10, 3/3, and 3/3 passed respectively, 0 failures. The added no-paraId paragraphs-only slot test confirms the generated `p1` can parameterize `body`, while default no-paraId output still contains `carryPart` and no `Paragraph(id:)` DSL block.

### Skill reference-reader RED/GREEN

RED on the unmodified swiftify skill (fresh reference-only reader): it concluded there was no readable Swift + named-slot route for a no-paraId/no-table document and reported that the reference supplied no command to switch to readable DSL or use another slot locator. It correctly retained the rich-table negative boundary.

GREEN on the updated skill (fresh reference-only reader): it selected coverage → paragraphs-only → inspect the actual synthetic `pN` → `--slot` → render; explicitly warned that byte equality, layout, and complete formatting are not guaranteed; did not recommend paragraphs-only as a full rich-table alternative; and distinguished CLI 0.7.0's existing paragraphs-only feature from the unreleased stderr hint.

## Verification

```text
swift test --filter MacDocCLITests
```

Result:

- XCTest: 88 tests executed, 4 optional fixture tests skipped, 0 failures.
- Swift Testing: 43 tests passed in 5 suites, 0 failures.
- Total executed: 131 tests; 0 failures. Optional skips were missing local `.docx` fixtures, a single-page synthetic note unsuitable for a ≥2-page density check, and unavailable Playwright paths reported by existing tests.
- Every CLI invocation reported the worktree-local debug binary path: `.build/debug/macdoc`.

Additional checks:

```text
jq -e '.version == "1.5.2" and .binary_version == "0.7.0"' plugins/macdoc/.claude-plugin/plugin.json
jq -e '.plugins[] | select(.name == "macdoc") | .version == "1.5.2" and .binary_version == "0.7.0"' .claude-plugin/marketplace.json
git diff --check
```

All returned exit 0.

## Files

- `.claude-plugin/marketplace.json`
- `Sources/MacDocCLI/MacDoc+Word.swift`
- `Tests/MacDocCLITests/WordReverseCoverageTests.swift`
- `Tests/MacDocCLITests/WordReverseSlotTests.swift`
- `plugins/macdoc/.claude-plugin/plugin.json`
- `plugins/macdoc/CHANGELOG.md`
- `plugins/macdoc/skills/swiftify/SKILL.md`
- `.superpowers/sdd/2026-09-09-approved-issues/task-3-report.md`

## Concerns / Boundaries

- 沒有修改 upstream OOXML 套件、沒有新增旗標、沒有發布 CLI、沒有推送或建立 PR。
- release Swift Testing runner 的 #188 已知問題不在本次範圍；本次驗收使用 debug runner。
- `--paragraphs-only` 是有意識的保真取捨，不是 full-fidelity 的自動 fallback。
