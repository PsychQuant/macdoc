# MacDoc CLI 測試

CLI 整合測試預設執行與測試本身相同建置組態的 `macdoc`：debug 測試使用
`.build/debug/macdoc`，release 測試使用 `.build/release/macdoc`。測試 helper 不會自行建置，也不會在
缺少目前組態的 binary 時改用另一組態。

一般 debug 驗證：

```sh
swift build
swift test --filter MacDocCLITests
```

release resolver 驗證：

```sh
swift build -c release
swift test -c release --filter CLITestHelperBinaryPathTests
```

使用 `--scratch-path` 時，必須透過 `MACDOC_TEST_BINARY` 明確指定同一 scratch path 內的絕對
可執行檔路徑；helper 不會猜測 SwiftPM 的私有目錄配置：

```sh
swift build --scratch-path .build-idd
BIN_DIR="$(swift build --scratch-path .build-idd --show-bin-path)"
MACDOC_TEST_BINARY="$BIN_DIR/macdoc" \
  swift test --scratch-path .build-idd --filter MacDocCLITests
```

`MACDOC_TEST_BINARY` 必須是非空、絕對且可執行的路徑。設定無效時測試會直接失敗，不會 fallback。
每次由 helper 執行 CLI 時，測試 runner 的 stderr 會記錄實際路徑；該行不會混入受測 CLI 的
`CLIResult.stdout` 或 `CLIResult.stderr`。

使用 `swift test --skip-build` 前，呼叫者必須先確保目前測試組態或 override 指向的 binary 已由
現行原始碼建置。`--skip-build` 只省略建置，無法證明既有產物是最新版本。
