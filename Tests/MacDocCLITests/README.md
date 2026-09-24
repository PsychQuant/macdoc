# MacDoc CLI 測試

使用共用 `CLITestHelper` 的 CLI 整合測試，預設執行與測試本身相同建置組態的 `macdoc`：debug
測試使用 `.build/debug/macdoc`，release 測試使用 `.build/release/macdoc`。helper 不會自行建置，
也不會在缺少目前組態的 binary 時改用另一組態。這項規則不適用於下述使用自有 resolver 的
`MacDocDocxIntegrationTests`。

一般 debug 驗證：

```sh
swift build
swift test --filter MacDocCLITests
```

release resolver 驗證目前必須停用 Swift Testing runner：

```sh
swift build -c release
swift test -c release --disable-swift-testing \
  --filter CLITestHelperBinaryPathTests
```

本輪曾觀察到：若未加 `--disable-swift-testing`，Swift Testing runner 會把
`--test-bundle-path` 傳給產品 `macdoc`，導致指令失敗；相關錯誤由
[#188](https://github.com/PsychQuant/macdoc/issues/188) 追蹤。另一個替代流程是使用預設的 debug
XCTest bundle，並明確指定 release 產品 binary。這會驗證 override 流程，但不等同於驗證 release
測試 bundle 的編譯組態接線。下列命令直接保留 `swift test` 的 exit status，並不是自動驗收
script；命令 exit 0 後，仍須人工核對同一次輸出確實含有精確的 release binary log，且
`testNoteToHTMLSmoke` 顯示 passed、不是 skipped：

```sh
swift build -c release
RELEASE_BIN="$(swift build -c release --show-bin-path)/macdoc"
MACDOC_TEST_BINARY="$RELEASE_BIN" \
  swift test --disable-swift-testing --filter NoteHTMLConvertTests
```

同一次輸出應可見 `[macdoc-test] binary=<RELEASE_BIN 的精確絕對路徑>`，以及
`NoteHTMLConvertTests.testNoteToHTMLSmoke`（或 XCTest 等價名稱）passed；缺少任一項或顯示 skipped
都不能算完成 release-product 驗證。

`NoteHTMLConvertTests` 會透過 `CLITestHelper.run` 實際啟動指定的 release 產品 binary；此時測試
程式本身仍是預設的 debug XCTest bundle。

使用 `--scratch-path` 時，請以 `mktemp` 建立工作樹外的暫存目錄，並透過
`MACDOC_TEST_BINARY` 明確指定該 scratch path 內的絕對可執行檔路徑；helper 不會猜測 SwiftPM
的私有目錄配置：

```sh
SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macdoc-swiftpm.XXXXXX")"
swift build --scratch-path "$SCRATCH_DIR"
BIN_DIR="$(swift build --scratch-path "$SCRATCH_DIR" --show-bin-path)"
MACDOC_TEST_BINARY="$BIN_DIR/macdoc" \
  swift test --scratch-path "$SCRATCH_DIR" --filter MacDocCLITests
```

`MacDocDocxIntegrationTests` 使用自己的 resolver，不受 `MACDOC_TEST_BINARY` 控制；即使以 release
組態執行，它仍固定解析目前工作目錄的 `.build/debug/macdoc`。使用 scratch path 時，這組測試可能
因 fixture 缺少而 skip，也可能直接執行工作目錄中較舊的 debug binary，而不是 skip。不要以該組
測試的綠燈推論 scratch path 或 release 的產品 binary 已受測。

這個獨立 resolver 的邏輯（cwd-relative、忽略環境變數）自 [#192](https://github.com/PsychQuant/macdoc/issues/192)
起抽成 `DocxIntegrationBinaryResolver`，有自己的單元測試（`DocxIntegrationBinaryResolverTests`）
覆蓋「binary 存在」「binary 缺席」「即使注入 `MACDOC_TEST_BINARY` 也不受影響」三種情境。這不是
把它併進 `CLITestHelper` 變成統一 resolver——兩者刻意保持獨立，見該型別的文件註解。

`MACDOC_TEST_BINARY` 必須是非空、絕對且可執行的路徑。設定無效時測試會直接失敗，不會 fallback；
但已 export 的有效路徑只表示檔案可執行，不保證它對應目前組態或現行原始碼，也不保證新鮮度。
`CLITestHelper.run`（以及透過它呼叫的 `convert`）會把實際 binary path 記錄到測試 runner 的
stderr；直接呼叫 `binaryPath` 或 `runProcess` 不會記錄。這項日誌不含 mtime，也不會混入受測
CLI 的 `CLIResult.stdout` 或 `CLIResult.stderr`。

若 `MACDOC_TEST_BINARY` 指向一個目錄（例如不小心少打了 `/macdoc` 這段檔名），`binaryPath`
現在會乾淨地擲出 `BinarySelectionError.unavailable`，訊息明確指出「這是一個目錄，不是可執行
檔」；先前 `FileManager.isExecutableFile(atPath:)` 對有執行位元的目錄一律回傳 `true`（幾乎所有
目錄都符合，那個位元就是讓目錄可以被 `cd` 進去的），guard 會誤判通過，一路傳到
`Process.run()` 才丟出難以辨識的底層錯誤。`unavailable` 與 `invalidOverride` 兩個 case 現在都
conform `CustomStringConvertible`，依「目錄／無執行權限／不存在」三種情況給出不同措辭（見
`BinarySelectionError.description`），但 `Equatable` 比較的仍是原始關聯值，不受此影響。

使用 `swift test --skip-build` 前，呼叫者必須先確保目前測試組態或 override 指向的 binary 已由
現行原始碼建置。`--skip-build` 只省略建置；即使已 export override，也無法證明既有產物是最新版本。

## `[macdoc-test] binary=...` 診斷寫入的已知風險（評估，未修復）

`CLITestHelper.run` 目前用未包裝的 `FileHandle.standardError.write(Data(...))` 把實際 binary
path 寫到 stderr。這支 API 在寫入端遇到已關閉的 pipe（fd 失效）時，Apple 文件記載會丟出
`NSFileHandleOperationException`——一個 Objective-C exception，Swift 的 `do/catch` 攔截不到，
會讓整個測試 process 異常終止。

[#192](https://github.com/PsychQuant/macdoc/issues/192) 要求評估改用會拋出 Swift `Error` 的
`try? FileHandle.standardError.write(contentsOf:)`。已用一支獨立 spike（在 `Pipe` 上關閉讀取端
模擬壞掉的管線，不動到真實 stderr）驗證兩支 API 在兩種情境下的行為：

| SIGPIPE 處置 | `write(_:)`（現行） | `write(contentsOf:)` |
|---|---|---|
| 預設（未忽略，XCTest/Swift Testing process 的正常狀態）| write(2) syscall 本身觸發 SIGPIPE，**整個 process 直接被訊號終止**，Foundation 根本沒機會處理 | **同樣被訊號直接終止**——`try?` 攔截不到訊號 |
| 已明確 `signal(SIGPIPE, SIG_IGN)` | 丟出不可攔截的 `NSFileHandleOperationException`（process 仍會 crash）| 丟出可 `try?` 吞掉的 Swift `Error`（不會 crash）|

結論：`write(contentsOf:)` 只在「SIGPIPE 已被整個 process 忽略」這個前提下才比 `write(_:)` 安全；
在 XCTest/Swift Testing process 預設的訊號處置下，兩者在遇到已關閉的 stderr pipe 時都會讓整個
測試 process 被 SIGPIPE 直接終止，與呼叫哪支 API 無關。要真正堵住這個缺口，需要在測試 process
啟動時就 `signal(SIGPIPE, SIG_IGN)`——但那是影響整個共用 XCTest process、所有測試都會遭殃的
全域改動，超出這行診斷寫入的合理範圍，因此**未採用**，現行程式碼維持 `write(_:)` 不變。若未來
真的要處理「stderr fd 在測試期間被關閉」這個場景，正確的修法是在測試 process 入口處全域忽略
SIGPIPE，而不是逐一替換每個 `FileHandle.write` 呼叫。

## Xcode Test Navigator 與 SwiftPM `.build` 的差異

本文件其餘部分的所有指令（`swift build` / `swift test --filter ...`）都假設從命令列以 SwiftPM
驅動，binary 固定落在 `.build/<configuration>/macdoc`——`CLITestHelper.binaryPath` 的預設路徑正
是照這個假設寫的。

若改用 Xcode 的 Test Navigator（開啟 `Package.swift` 後以 ⌘U 執行、或點測試左側的菱形圖示執行
單一測試），Xcode 會改用自己的 **DerivedData**（預設在
`~/Library/Developer/Xcode/DerivedData/<ProjectName>-<hash>/Build/Products/<Configuration>/`）建置
與快取產物，**不會**寫到這個 repo 的 `.build/` 目錄。`CLITestHelper` 完全不知道 DerivedData 的存
在——它的預設路徑只認 `.build/debug` 或 `.build/release`，在 Xcode 驅動的測試執行中永遠找不到
對應的 `macdoc` binary，導致 `resolveBinaryURL` 擲出 `unavailable`（而不是 fallback 到
DerivedData）。

要在 Xcode 裡跑這些測試，必須先在命令列跑過一次對應組態的 `swift build`，讓 `.build/<configuration>/macdoc`
存在；或明確在 Xcode 的 scheme／測試計畫環境變數裡設定 `MACDOC_TEST_BINARY` 指向想要驗證的實際
binary 路徑（例如某次命令列 `swift build --scratch-path ...` 產出的 binary）。單純從 Xcode 內部
建置並不會讓這些測試自動找到 Xcode 自己編譯出的 binary——`.build` 與 DerivedData 是兩套互不相通
的產物目錄。

## `make test-release`（#188 的腳本化替代流程）

```sh
make test-release
```

固化上面「release resolver 驗證」段落的既有替代流程：先 `make release`（`swift build -c
release` + metallib），再以 `swift build -c release --show-bin-path` 解析出的路徑設定
`MACDOC_TEST_BINARY`，最後對預設 debug XCTest bundle 跑 `swift test --disable-swift-testing`。
迴歸測試在 `scripts/tests/make-test-release.sh`（用假的 `swift` 指令斷言呼叫序列，秒級執行，
不需要真的建置）。

### #188 現況（2026-09-24 複驗）：目前無法重現

issue #188 記載的原始重現基準是 macdoc e339b40（未記錄精確 toolchain 版本）。本次在目前
worktree HEAD（3427eee7）、以下 toolchain 下，**逐字重跑 issue 本文的重現指令**：

```sh
swift build -c release
swift test -c release --filter 'CLITestHelperBinaryPathTests|MarkdownOMathRouteTests|WordReverse' -v
```

Toolchain：`swift-driver version: 1.168.6 Apple Swift version 6.4
(swiftlang-6.4.0.34.1 clang-2100.3.34.1)`，`Target: arm64-apple-macosx27.2.0`，macOS 27.2
(26B5086k)。

結果：**完整成功**，未觀察到 `--test-bundle-path` 錯誤——XCTest 26 tests 全部 passed（含
`CLITestHelperBinaryPathTests`、三組 `WordReverse*Tests`），Swift Testing 17 tests 全部 passed
（`MarkdownOMathRouteTests` 套件），exit code 0。重跑兩次（一次因外部 `timeout 300` 在連結階段被
中斷、一次不設 timeout 完整跑到底）結果一致。

另外，依 #188 diagnosis 的靜態假說（testTarget 直接依賴 executableTarget 這種 package-graph
形狀本身觸發此限制）建了一個最小 throwaway 套件（同形狀：ArgumentParser `@main`
executableTarget + 直接依賴它的 testTarget，內含 XCTest 與 Swift Testing 各一），分別以
`ParsableCommand` 與 `AsyncParsableCommand`（macdoc 實際使用的協定）兩種變體在 `-c release` 下跑
`swift test`，**兩者皆完整通過，同樣未重現**。

**結論**：目前無法確認此限制仍是活的缺陷——可能是自 issue 記錄以來 Xcode/Swift toolchain 已修正
此行為，也可能原始失敗與某次特定的建置中斷/暫存狀態有關而非決定性的套件結構問題（本次確實有
一次因外部 timeout 使建置在連結中途被打斷，重跑後才乾淨完成，顯示建置狀態確實可能是變因之一）。
上方的 `make test-release` 仍保留作為低成本防禦性做法（與本文件既有建議的指令一致），但這不代表
「已修復」；若之後在其他機器/CI 上重現此錯誤，請補上當時的 `swift --version` 輸出與是否為乾淨
建置，一併記錄於 #188。
