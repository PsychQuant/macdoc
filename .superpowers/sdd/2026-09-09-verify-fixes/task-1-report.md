# Task 1 Report — #187 formal-review repair

## 結果

- 實作 commit：`389d250dcd98163e6dadffd4d70a82c79a45d2a2`（`test: close CLI binary verification gaps (#187)`；以下以 `389d250` 簡寫）。
- 基準：`7d77600790d877ba35fa74089d14915f0659a61b`。
- 行為與文件修改只包含 `Tests/MacDocCLITests/CLITestHelperBinaryPathTests.swift` 與 `Tests/MacDocCLITests/README.md`，另新增本報告 `.superpowers/sdd/2026-09-09-verify-fixes/task-1-report.md`；沒有修改產品 CLI、`MacDocDocxIntegrationTests` resolver 或 mtime 政策。
- F5 的 GitHub 稽核紀錄由父任務處理；本任務依限制沒有任何 GitHub 寫入。

## 執行命令與證據

| 階段 | 命令 | Exit | 結果 |
|---|---|---:|---|
| 聚焦基線 | `swift test --filter CLITestHelperBinaryPathTests` | 0 | 8 tests，0 failures |
| RED／mutation | 暫時把 `binaryPath` 的 debug/release 分支反轉後執行 `swift test --filter CLITestHelperBinaryPathTests` | 1 | 9 tests，1 failure（1 unexpected）；新增 getter 測試因錯選 `.build/release/macdoc` 而失敗，既有 8 tests 仍通過 |
| GREEN／debug | 還原正確分支後執行 `swift test --filter CLITestHelperBinaryPathTests` | 0 | 9 tests，0 failures |
| GREEN／release XCTest | `swift test -c release --disable-swift-testing --filter CLITestHelperBinaryPathTests` | 0 | 9 tests，0 failures；輸出明列 `Building for production...`，build 191.47s |
| 完整 CLI suite（唯一一次） | `swift test --filter MacDocCLITests` | 0 | XCTest 95（4 skipped）＋ Swift Testing 43，共 138 tests，0 failures |
| 格式／範圍 | `git diff --check` | 0 | 無 whitespace error |

## 真實組態接線

新增的 `testBinaryPathUsesActualTestBuildConfiguration` 直接呼叫 throwing getter `CLITestHelper.binaryPath`，不是把組態字串傳給 resolver。測試先保存並清除程序的 `MACDOC_TEST_BINARY`，再以 `defer` 還原原值（原本未設定則維持未設定）。同一測試分別在真實 debug 與 release XCTest bundle 執行；release 指令明確使用 `--disable-swift-testing` 避開 #188。分支反轉 mutation 只讓這個測試失敗，證明它能攔截 F3 所述回歸。

## README 修補

- release 正道明列 `--disable-swift-testing` 與 #188；另列「debug XCTest bundle ＋明確 release override」替代流程，並說明兩者證據不同。
- scratch path 改用 `mktemp -d` 的工作樹外目錄；說明獨立 DocxIntegration resolver 不受 override 控制，且可能因 cwd 的預設 debug binary 或 fixture 缺少而 skip。
- 明列 `--skip-build` 與已 export override 都不保證產物新鮮或組態一致。
- 日誌主張收窄為 `run` 及透過它呼叫的 `convert`；`binaryPath`／`runProcess` 不記錄，且不含 mtime。

## SwiftPM pins

每次 SwiftPM 執行都因 sibling editable dependencies 移除 `Package.resolved` 的 `ooxml-swift` 與 `pdf-to-latex-swift` remote pins。本任務僅用 `apply_patch` 補回 HEAD 原值；最後工作檔與 HEAD 的 SHA-1 均為 `eb7cbc96a43c1318b3dc550ab464b1bbeacf0881`，沒有提交鎖檔變更。

## 自我審查與限制

- F1–F4 均有對應 README 或真實 getter 測試；F5 明確留給父任務，避免越權寫 GitHub。
- 完整 suite 的 4 個 XCTest skip：DocxIntegration 缺 `.docx` fixture 2 個、Note PDF 頁數不足 1 個、Word table fixture 缺少 1 個；Swift Testing 另印出 playwright 未安裝而略過 E2E／自動路徑，但其 43 tests 全數通過。
- 建置仍有既存 warning：`Tests/MacDocCLITests/Fixtures/README.md` 未由 target 處理，以及既存未使用變數／dependency deprecation；皆非 #187 範圍，未順手修改。
- 未執行 README 的 scratch 替代流程；debug、release 與完整 CLI suite 已直接執行。沒有 publish、push、tag、merge、close、VM 或 GitHub 動作。
