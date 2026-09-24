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

## 已接線的路由（17 種轉換，24 個副檔名／目標組合；另有不做格式轉換的 tokens 測量路由）

`switch (ext, target)` 裡每個 case 算一種轉換；一個 case 常接受多個副檔名別名
（如 `("html", "md"), ("htm", "md")`），每個別名各算一組副檔名／目標組合。
17 種轉換 + tokens = `macdoc convert` 目前總共處理的 18 種輸出。與 `cli-spec.yaml`
的 `conversions`（`macdoc convert` 底下那些）對得上就是對的，這裡只是給人看的摘要，
改路由時兩邊要一起改（見上面「新增轉換路由的步驟」）。

```
(docx, md)                    → WordConverter
(docx, html)                  → WordHTMLConverter
(docx, marker)                 → MarkerWordConverter（目錄輸出，不支援 stdout）
(html, md), (htm, md)          → HTMLConverter（支援 --html-extensions，保留 <u>/<sup>/<sub>/<mark> 為 raw HTML）
(html, pdf), (htm, pdf)        → playwright pdf CLI（二進位輸出，不支援 stdout，需要 playwright）
(html, docx), (htm, docx)      → HTMLToWordConverter（二進位輸出，不支援 stdout）
(md, html), (markdown, html)   → MarkdownConverter（支援 --full）
(md, docx), (markdown, docx)   → MarkdownToWordConverter（二進位輸出，不支援 stdout；支援 --math）
(srt, html)                    → SRTConverter（支援 --full + --css dark|light；沒帶 --css 時這條路由自己預設 dark，見 #216）
(bib, html)                    → BibToAPAHTMLFormatter（支援 --full + --css minimal|web；沒帶 --css 時預設 web）
(bib, md)                      → BibToAPAFormatter
(bib, json)                    → BibToAPAJSONFormatter
(pdf, md)                      → PDFToMD.PDFConverter
(pdf, docx)                    → PDFToDOCXConverter（二進位輸出，不支援 stdout）
(tex, docx)                    → TeXToDOCXConverter（二進位輸出，不支援 stdout）
(note, html), (ntb, html)      → NoteConverter（目錄或 stdout 輸出；支援 --full + --css dark|light，沒帶 --css 時預設 dark；只認舊版 plist .note，現代 FlatBuffers .ntb 會被拒絕）
(note, pdf), (ntb, pdf)        → NoteToPDFConverter（二進位輸出，不支援 stdout；同上只認舊版 .note）
(*, tokens)                    → TokenCountCommandRunner（不是格式轉換，是量測路由；--model gpt-4o 離線、claude-sonnet-4-6 需要 --allow-network）
```

## 輸出格式規則

### 文字格式（md, html, json）
- 預設輸出到 stdout
- 可用 `--output` 指定檔案

### 二進位格式（docx, pdf）
- docx/pdf 是二進位格式，不支援 stdout 輸出
- 未指定 `--output` 時自動生成輸出路徑（同目錄，改副檔名）
- pdf 輸出需要外部 `playwright` CLI（`pip install playwright && playwright install chromium`）

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
