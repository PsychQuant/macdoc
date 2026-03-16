# Unix CLI 通用慣例

macdoc CLI 遵循標準 Unix 命令列工具的設計慣例。

## 規則

1. **檔案放最後** — `macdoc convert --to md file.docx`，不是 `macdoc convert file.docx --to md`
2. **stdout 是預設輸出** — 不指定 `--output` 時寫到 stdout，可 pipe 給其他工具
3. **stderr 寫狀態訊息** — 進度、警告、「已寫入: path」等用 `FileHandle.standardError`
4. **exit code** — 0 = 成功，非零 = 失敗（swift-argument-parser 自動處理）
5. **input format 從副檔名自動偵測** — 不需要使用者指定 `--from`
6. **`--stdout` 強制輸出到 stdout** — 覆蓋 `--output`（stdout 優先）
7. **`--` long flags** — 遵循 GNU 慣例（`--to`, `--output`, `--full`），不用單 dash
8. **靜默原則** — 成功時不輸出多餘訊息到 stderr，除非寫檔時報告路徑
