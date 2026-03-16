# Error Messages 與輸出規範

## Error Messages

- 語言：**繁體中文**
- 用 `validatedInputURL()` 統一處理（輸出 `找不到輸入檔案: <path>`）
- 不要自己寫 `guard FileManager.default.fileExists`

```swift
// 正確
let inputURL = try validatedInputURL(input)

// 錯誤 — 不要這樣寫
guard FileManager.default.fileExists(atPath: inputURL.path) else {
    throw ValidationError("File not found: \(input)")  // ← 英文，不一致
}
```

## 輸出

- 用 `writeStringOutput(_:to:)` 統一處理 file/stdout 分流
- 寫入檔案後的狀態訊息寫到 stderr：`已寫入: <path>`
- 不要重複實作 output 邏輯

## CSS / Full Document

- `--full` 輸出完整 HTML 文件（DOCTYPE + head + CSS + body）
- `--css` 選擇 CSS 風格（值因格式而異）
- bib: `minimal`（學術 Times New Roman）, `web`（現代系統字體）
- srt: `dark`（深色主題）, `light`（淺色/列印）
- 不指定 `--full` 時只輸出 HTML fragment
