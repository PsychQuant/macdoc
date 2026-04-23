# Reference Repos

外部參考資料索引。這個資料夾本身被 `.gitignore` 忽略(見 repo root `.gitignore` `reference/`),只有這份 `README.md` 進版控,讓任何 clone macdoc 的人知道要去哪裡把這些參考資料拉下來。

## 快速安裝

```bash
cd reference/
git clone https://github.com/dolanmiu/docx.git docx-js
git clone https://github.com/ml-explore/mlx-swift-lm.git
git clone https://github.com/jgm/pandoc.git
git clone https://github.com/apple/swift-argument-parser.git
# textutil-manpage.txt 已在版控中
```

## 索引

| 路徑 | 類型 | Upstream | 用途 |
|------|------|----------|------|
| `docx-js/` | git repo | https://github.com/dolanmiu/docx | Node.js OOXML 函式庫。`word-builder-swift` 是其 1:1 Swift 移植,寫新 API 前先看 JS 對應實作 |
| `mlx-swift-lm/` | git repo | https://github.com/ml-explore/mlx-swift-lm | Apple MLX Swift LLM runtime。`pdf-to-latex-swift` Phase 1 的 local GLM-OCR backend 用它載模型 |
| `pandoc/` | git repo | https://github.com/jgm/pandoc | Haskell 文件轉換工具。macdoc 不依賴 pandoc,純粹參考它怎麼處理邊界情況(複雜 table、field、footnote 跨段落) |
| `swift-argument-parser/` | git repo | https://github.com/apple/swift-argument-parser | Apple 官方 CLI 解析器。`macdoc` CLI 已是使用者,這裡留一份方便查 source-level 行為(尤其是 subcommand dispatch、ExitCode) |
| `textutil-manpage.txt` | 單檔 | [textutil(1) macOS man page](https://ss64.com/mac/textutil.html) | macOS 內建 `textutil` 的 manual。`macdoc convert` 的 CLI 語法對齊 textutil(見 `.claude/rules/cli-design/textutil-compat.md`),改 CLI 前對一下 |

## 用途與 macdoc 的對照

### docx-js → `word-builder-swift`

`word-builder-swift` 的設計原則是「1:1 mirror of docx.js 9.6.x」。寫 `Paragraph`、`Table`、`Run`、`SectionProperties` 等 builder API 時,先看 `docx-js/src/file/<component>` 對應的 TypeScript 類別,確認參數名、chain 行為、預設值。

關鍵參考路徑:
- `docx-js/src/file/document/` — 文件根結構
- `docx-js/src/file/paragraph/` — 段落 builder
- `docx-js/src/file/table/` — 表格(含 merge 邏輯)
- `docx-js/src/file/drawing/` — 圖片 anchor/inline

### mlx-swift-lm → `pdf-to-latex-swift` / `ocr-swift`

`ocr-swift` 的 MLX backend 直接 import `MLXLMCommon`。要改 sampling、streaming、tokenizer 行為前先看:
- `mlx-swift-lm/Libraries/MLXLMCommon/` — 共用 protocol
- `mlx-swift-lm/Libraries/MLXLLM/` — LLM runtime
- `mlx-swift-lm/Libraries/MLXVLM/` — vision-language model(GLM-OCR 是 VLM)

### pandoc → 格式轉換邊界情境

不直接使用 pandoc 產出。純粹當「黃金對照」——寫 `word-to-md` / `html-to-md` / `pdf-to-md` 遇到詭異輸入(nested table、複雜 list、cross-reference)時,丟同一份檔案給 pandoc 看它怎麼處理,再決定 macdoc 要不要跟進。

關鍵參考路徑:
- `pandoc/src/Text/Pandoc/Readers/Docx.hs` — Word 讀取邏輯
- `pandoc/src/Text/Pandoc/Readers/HTML.hs` — HTML 讀取邏輯
- `pandoc/src/Text/Pandoc/Writers/Markdown.hs` — Markdown 輸出邏輯

### swift-argument-parser → `macdoc` CLI

`macdoc` 的 `Sources/MacDocCLI/` 全部基於 `ArgumentParser`。遇到奇怪行為(subcommand completion、async command、ValidationError 訊息控制)時查:
- `swift-argument-parser/Sources/ArgumentParser/Parsable Types/` — ParsableCommand / AsyncParsableCommand
- `swift-argument-parser/Sources/ArgumentParser/Parsable Properties/` — @Option / @Argument / @Flag

### textutil-manpage → CLI 語法對齊

macdoc 的 `convert` 子命令語法刻意跟 macOS 內建 `textutil` 靠攏,為的是讓「已經會 textutil」的使用者零學習成本。改 `convert` 入口前對照這份 man page 確認語義一致:

- `-convert <format>` ↔ `macdoc convert --to <format>`
- `-output <file>` ↔ `macdoc convert --output <file>`
- `-stdout` ↔ `macdoc convert --stdout`
- `-cat` ↔(不支援,合併多檔不在 scope 內)

詳見 `.claude/rules/cli-design/textutil-compat.md`。

## 外部官方規範連結(非本地 clone)

實作 OOXML / OMML / DrawingML 時常查的官方規範,集中列這裡方便開新視窗。

### OOXML 規範
- [ECMA-376 (Office Open XML)](https://ecma-international.org/publications-and-standards/standards/ecma-376/) — WordprocessingML 在 Part 1 §17
- [ISO/IEC 29500](https://www.iso.org/standard/71691.html) — ECMA-376 的 ISO 版本

### Microsoft 文件
- [Open XML SDK 文件](https://learn.microsoft.com/en-us/office/open-xml/open-xml-sdk) — 範例豐富度遠勝 ECMA 規範本身
- [WordprocessingML schema 參考](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing) — `<w:*>` 元素查表
- [DrawingML schema 參考](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing) — `<a:*>` 元素查表
- [Office Math (OMML) 文件](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.math) — `<m:*>` 元素查表

### Office.js:Word 物件模型對照

Office.js 是 Word 本體暴露的 JavaScript API,直接反映 OOXML 的能力面。`che-word-mcp` 的功能擴充 roadmap(見 [PsychQuant/che-word-mcp#43](https://github.com/PsychQuant/che-word-mcp/issues/43))就是以 Office.js 為鏡整理出 20 項可擴充 OOXML 功能——實作新功能前先查 Office.js 對應的物件,對照 Word 本體如何暴露該能力再決定 Swift API 設計。

- [Office.js Word API 參考](https://learn.microsoft.com/en-us/javascript/api/word) — 主文件,類別/方法/屬性查表
- [Word API 需求集](https://learn.microsoft.com/en-us/javascript/api/requirement-sets/word/word-api-requirement-sets) — WordApi 1.1 ~ 1.9 版本相容性,判斷功能穩定度
- [Office.js Document API](https://learn.microsoft.com/en-us/javascript/api/word/word.document) — Document 根物件、sections/body/contentControls 入口
- [Office.js Paragraph API](https://learn.microsoft.com/en-us/javascript/api/word/word.paragraph) — 段落操作、inline 元素、格式
- [Office.js Table API](https://learn.microsoft.com/en-us/javascript/api/word/word.table) — 表格、合併儲存格、條件格式
- [Office.js ContentControl API](https://learn.microsoft.com/en-us/javascript/api/word/word.contentcontrol) — SDT 結構化文件標籤
- [Office Add-ins 範例程式庫](https://github.com/OfficeDev/office-js-snippets) — 可直接在 Word 的 Script Lab 執行的範例

### 其他 OOXML 函式庫(非 clone,線上對照)
- [officegen / docx.js (Node)](https://github.com/Ziv-Barber/officegen) — 跟 `dolanmiu/docx` 不同實作,有時邊界情況處理得更好
- [python-docx](https://github.com/python-openxml/python-docx) — 最成熟的 Python OOXML 函式庫
- [docx4j (Java)](https://www.docx4java.org/trac/docx4j) — 有 schema browser

### 除錯工具
- [Open XML SDK Productivity Tool](https://github.com/dotnet/Open-XML-SDK) — 反編譯任何 .docx 為產生它的 C# 程式碼
- [OMML2MML.xsl](https://github.com/microsoft/Office-Open-XML-File-Format-Resources) — Microsoft 釋出的 OMML ↔ MathML XSLT
- [OOXML Hacking (Eric White 部落格)](https://ericwhite.com/blog/) — 前 MS Open XML team 的邊界情境筆記

### PDF / OCR / 其他
- [PDFKit (Apple)](https://developer.apple.com/documentation/pdfkit) — macdoc 所有 PDF 文字提取的基礎
- [Vision framework (Apple)](https://developer.apple.com/documentation/vision) — `che-pdf-mcp` 的 OCR backend
- [MLX (Apple)](https://ml-explore.github.io/mlx/) — `ocr-swift` MLX backend 的基礎
- [Semantic Scholar API](https://api.semanticscholar.org/) — `che-zotero-mcp` 的學術搜尋
- [BibLaTeX manual](https://www.ctan.org/pkg/biblatex) — `bib-apa-swift` APA 7 styling 的格式依據

## 新增條目時的約定

把新東西加到這份 README 的同時:

1. **是 git repo** → `cd reference && git clone <upstream>` ,並在上方「快速安裝」與「索引」兩節補一行
2. **是單檔** → 直接放 `reference/` 根目錄(像 `textutil-manpage.txt`),索引補一行
3. **是官方網頁連結** → 只更新「外部官方規範連結」那節,不用動 clone

記得 commit 的是 `reference/README.md`,不要把 clone 的 repo commit 進來(`.gitignore` 會擋,但加 `-f` 會繞過)。
