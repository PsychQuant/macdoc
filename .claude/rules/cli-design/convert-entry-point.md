# convert 統一入口規範

## 原則

所有格式轉換必須走 `macdoc convert --to <format> <file>` 統一入口。
舊的 per-format 子命令（`word`, `html`, `srt`）保留為 alias，但 help text 提示改用 `convert`。

## 新增轉換路由的步驟

1. 在 `MacDoc+Convert.swift` 的 `switch (ext, target)` 加 case
2. 寫對應的 `private func convert<Source>To<Target>(inputURL:)` 方法
3. 用 `validatedInputURL()` 驗證輸入（不要自己寫 guard）
4. 用 `writeStringOutput()` 或 `convertToFile/convertToStdout` 輸出
5. 支援 `--full` 和 `--css`（如果輸出 HTML）
6. Error messages 用中文（`找不到輸入檔案:`）

## 已接線的路由

```
(docx, md)  → WordConverter
(html, md)  → HTMLConverter
(md, html)  → MarkdownConverter
(srt, html) → SRTConverter（支援 --full + --css dark|light）
(bib, html) → BibToAPAHTMLFormatter（支援 --full + --css minimal|web）
(bib, md)   → BibToAPAFormatter
(bib, json) → BibToAPAJSONFormatter
```

## 不該做的事

- 不要建新的 top-level subcommand 來做轉換（用 `convert`）
- 不要在 `convert` 裡重複實作 CLIHelpers 已有的功能
- 不要用英文 error messages
