# convert 統一入口規範

## 原則

所有格式轉換必須走 `macdoc convert --to <format> <file>` 統一入口。
不再有 per-format 子命令（`word`, `html`, `srt` 等已移除）。

## 新增轉換路由的步驟

1. 在 `MacDoc+Convert.swift` 的 `switch (ext, target)` 加 case
2. 寫對應的 `private func convert<Source>To<Target>(inputURL:)` 方法
3. 用 `validatedInputURL()` 驗證輸入（不要自己寫 guard）
4. 用 `writeStringOutput()` 或 `convertToFile/convertToStdout` 輸出
5. 支援 `--full` 和 `--css`（如果輸出 HTML）
6. Error messages 用中文（`找不到輸入檔案:`）

## 已接線的路由（15 條）

```
(docx, md)     → WordConverter
(docx, html)   → WordToHTMLConverter
(docx, marker) → MarkerWordConverter（目錄輸出，不支援 stdout）
(html, md)     → HTMLConverter
(html, docx)   → HTMLToWordConverter（二進位輸出，不支援 stdout）
(md, html)     → MarkdownConverter（支援 --full + --html-extensions）
(md, docx)     → MarkdownToWordConverter（二進位輸出，不支援 stdout）
(srt, html)    → SRTConverter（支援 --full + --css dark|light）
(pdf, md)      → PDFToMarkdownConverter
(pdf, docx)    → PDFToDocxConverter（二進位輸出，不支援 stdout）
(tex, docx)    → TeXToDocxConverter（二進位輸出，不支援 stdout）
(bib, html)    → BibToAPAHTMLFormatter（支援 --full + --css minimal|web）
(bib, md)      → BibToAPAFormatter
(bib, json)    → BibToAPAJSONFormatter
```

## 輸出格式規則

### 文字格式（md, html, json）
- 預設輸出到 stdout
- 可用 `--output` 指定檔案

### 二進位格式（docx）
- docx 是二進位格式，不支援 stdout 輸出
- 未指定 `--output` 時自動生成輸出路徑（同目錄，改副檔名）

### 目錄格式（marker）
- marker 是目錄結構輸出（`.md` + `_meta.json` + `images/`）
- 不支援 stdout 輸出
- 必須用 `--output` 指定輸出目錄

## 額外 flags

- `--frontmatter` — Word → Markdown 時輸出 YAML frontmatter
- `--html-extensions` — HTML → Markdown 時保留 `<u>/<sup>/<sub>/<mark>` 為 raw HTML
- `--full` — HTML 輸出時包含完整文件結構（DOCTYPE + head + CSS + body）
- `--css <style>` — HTML 輸出時選擇 CSS 風格

## 不該做的事

- 不要建新的 top-level subcommand 來做轉換（用 `convert`）
- 不要在 `convert` 裡重複實作 CLIHelpers 已有的功能
- 不要用英文 error messages
- 不要讓 docx/marker 輸出支援 stdout
