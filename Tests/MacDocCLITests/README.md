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
測試 bundle 的編譯組態接線。判定成功時不能只看 `swift test` 的 exit 0；還必須在同一份 log
確認實際啟動 release 路徑，且 NoteHTML 測試不是 skip：

```sh
swift build -c release
RELEASE_BIN="$(swift build -c release --show-bin-path)/macdoc"
TEST_LOG="$(mktemp "${TMPDIR:-/tmp}/macdoc-release-test.XXXXXX")"
MACDOC_TEST_BINARY="$RELEASE_BIN" \
  swift test --disable-swift-testing --filter NoteHTMLConvertTests 2>&1 | tee "$TEST_LOG"
grep -F "[macdoc-test] binary=$RELEASE_BIN" "$TEST_LOG"
grep -E "NoteHTMLConvertTests.*testNoteToHTMLSmoke.*passed" "$TEST_LOG"
```

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

`MACDOC_TEST_BINARY` 必須是非空、絕對且可執行的路徑。設定無效時測試會直接失敗，不會 fallback；
但已 export 的有效路徑只表示檔案可執行，不保證它對應目前組態或現行原始碼，也不保證新鮮度。
`CLITestHelper.run`（以及透過它呼叫的 `convert`）會把實際 binary path 記錄到測試 runner 的
stderr；直接呼叫 `binaryPath` 或 `runProcess` 不會記錄。這項日誌不含 mtime，也不會混入受測
CLI 的 `CLIResult.stdout` 或 `CLIResult.stderr`。

使用 `swift test --skip-build` 前，呼叫者必須先確保目前測試組態或 override 指向的 binary 已由
現行原始碼建置。`--skip-build` 只省略建置；即使已 export override，也無法證明既有產物是最新版本。
