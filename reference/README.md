# Reference Repos

外部參考資料索引。這個資料夾本身被 `.gitignore` 忽略(見 repo root `.gitignore` `reference/`),只有這份 `README.md` 進版控,讓任何 clone macdoc 的人知道要去哪裡把這些參考資料拉下來。

## 快速安裝

```bash
cd reference/
git clone https://github.com/dolanmiu/docx.git docx-js
git clone https://github.com/python-openxml/python-docx.git
git clone https://github.com/ml-explore/mlx-swift-lm.git
git clone https://github.com/jgm/pandoc.git
git clone https://github.com/apple/swift-argument-parser.git
git clone --depth 1 https://github.com/genspark-ai/genoffice.git   # 43M,只讀 source 不需要 history
# textutil-manpage.txt 已在版控中
```

## 索引

| 路徑 | 類型 | Upstream | 用途 |
|------|------|----------|------|
| `docx-js/` | git repo | https://github.com/dolanmiu/docx | Node.js OOXML 函式庫。`word-builder-swift` 是其 1:1 Swift 移植,寫新 API 前先看 JS 對應實作。**典範:typed builder** |
| `python-docx/` | git repo | https://github.com/python-openxml/python-docx | Python + lxml 的 OOXML 函式庫。**典範:tree-backed wrapper**——每個 `Document` / `Paragraph` / `Run` 包一個 lxml `_Element`,typed accessor 讀寫該 element。`word-aligned-state-sync` 的 Phase 1 (typed views as tree projections) 直接對照它。詳見 `docs/docx-libraries-comparison.md` |
| `mlx-swift-lm/` | git repo | https://github.com/ml-explore/mlx-swift-lm | Apple MLX Swift LLM runtime。`pdf-to-latex-swift` Phase 1 的 local GLM-OCR backend 用它載模型 |
| `pandoc/` | git repo | https://github.com/jgm/pandoc | Haskell 文件轉換工具。macdoc 不依賴 pandoc,純粹參考它怎麼處理邊界情況(複雜 table、field、footnote 跨段落) |
| `genoffice/` | git repo (shallow) | https://github.com/genspark-ai/genoffice | Genspark 的 AI-native office suite(Electron GUI)。**不是競品**——它沒有 MCP / CLI / public API,AI 綁自家雲端帳號;但 `packages/` 下的 engine 是純 TS、無 Electron 依賴,是**唯一同時涵蓋 docx + xlsx + pptx + pdf 的現代開源對照組**。看三件事:xlsx 缺口、patch-narrowly round-trip、pptx 功能廣度。Apache-2.0(`ee/` 另授權) |
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

### python-docx → `ooxml-swift` Phase 1 設計對照

`word-aligned-state-sync` Phase 1 要把 `Paragraph` / `Run` / `Table` / `SectionProperties` 從「typed model with parsed children」改成「typed view over shared XmlNode tree + op emitter on mutation」。python-docx 多年用 lxml-tree-backed wrapper 走過同樣的路,是最直接的參考實作。

關鍵參考路徑:
- `python-docx/src/docx/oxml/` — XML element 類別(對應我們的 `Tree/`)
- `python-docx/src/docx/oxml/parser.py` — element-class registration / lxml parser hook
- `python-docx/src/docx/document.py` — top-level Document API
- `python-docx/src/docx/blkcntnr.py` — block container 抽象(對應未來 `BodyChildren`)
- `python-docx/src/docx/text/paragraph.py` — typed wrapper 案例(怎麼從 lxml element 推 typed API)
- `python-docx/src/docx/comments.py` — comment 處理(macdoc Phase 1 的 Comment 重寫對照組)

注意:python-docx **沒有 op log**,直接 mutate lxml tree。macdoc 的 op log 是 differentiator——對照 python-docx 看「沒有 op log 怎麼處理同步」就會理解我們為什麼要加。

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

### genoffice → xlsx 缺口 / patch-narrowly round-trip / pptx 功能廣度

先講清楚定位,免得誤判:genoffice 是**桌面 GUI 套裝軟體**(Electron,五個 app 共用 engine 層),macdoc 是 CLI + MCP 的管線工具,兩者不是同一個品類,也不互相取代。它沒有 MCP server、沒有 public API、沒有自動化 CLI,AI 走 Genspark 帳號的雲端(本機不存 API key)。

**真正有參考價值的是 `packages/` 那層**——官方描述為「All pure TypeScript, no Electron dependency」,可以完全脫離 GUI 單獨閱讀。這是目前少見的、同時涵蓋 docx + xlsx + pptx + pdf 四種格式的現代開源實作。

三個具體對照點:

**1. xlsx——macdoc 唯一缺的 OOXML 主格式**

macdoc 有 word / pptx / keynote / pdf,沒有 Excel。genoffice 的做法是 UI 用 Univer core(Apache-2.0),import/export 走 Rust sidecar(calamine + IronCalc)。
- `genoffice/packages/file-parse/src/xlsx.ts` — 解析入口,先看它把 xlsx 拆成什麼中介結構
- `genoffice/apps/sheets/` — 上層怎麼消費

注意這是「要不要做 xlsx」的判斷材料,不是「該做」的理由。先問自己的工作流有沒有 Excel 需求,不要為了對齊功能表而追賽道。

**2. patch-narrowly / byte-preserving round-trip——跟 `ooxml-swift` op log 同目標、不同解法**

genoffice 的 docx 存檔只重新產生被改動的段落,未觸碰的 block 保留原始 bytes,其餘 zip entry 逐 byte 複製。目的跟 `word-aligned-state-sync` 的 op log 一樣(存檔不破壞 Word 版面),但走的是「差異化重生」而非「op 重放」。
- `genoffice/packages/docx-engine/src/patch.ts` — 核心 patch 邏輯
- `genoffice/packages/docx-engine/src/text-patch.ts` — 文字層級的窄幅修改
- `genoffice/packages/docx-engine/src/parse.ts` / `scan.ts` — 解析與掃描(patch 的前置)
- `genoffice/packages/docx-engine/src/generate.ts` — 產生端
- `genoffice/packages/pptx-engine/src/zip.ts` — zip entry 保留策略

對照重點:python-docx 是「直接 mutate tree、沒有 op log」,genoffice 是「保留原 bytes + 窄幅重生」,macdoc 是「op log 重放」。三種解法擺在一起看,才知道 op log 的成本換到了什麼。

完整研究筆記（含 byte 保證邊界、Word-canonical 詞彙與三方比較）：
[`docs/genoffice-roundtrip-comparison.md`](../docs/genoffice-roundtrip-comparison.md)。

**3. pptx 功能廣度——`pptx-swift` 的擴充 checklist**

`genoffice/packages/pptx-engine/src/` 有 macdoc 目前沒有的項目,可當功能對照表:`smartart.ts` / `smartart-layout.ts`、`custgeom.ts`(自訂幾何)、`animation.ts`、`theme-apply.ts`、`format-brush.ts`、`slide-transfer.ts`、`table-style.ts`。

**授權注意**:Apache-2.0,但 `ee/` 目錄保留給未來的 enterprise 模組(另一套 GenOffice Enterprise License)。GenOffice / Genspark 名稱與 logo 是 Mainfunc, Inc. 商標。當**設計參考**讀沒問題;若要逐行移植實作到 Swift,先確認 Apache-2.0 的 NOTICE 保留義務與 macdoc 自身授權相容。

**成熟度警語**:clone 當下(2026-08-04)發布版是 v0.4.110,pre-1.0,354 stars / 3 watchers。`main` 的 commit history 極短且訊息形如 `Sync snapshot (2026-08-03) (#6)`——是**內部開發、定期推 snapshot 出來**的模式,不是長期公開開發史,所以看不到 PR 討論、design rationale、bug 修復的來龍去脈,只能讀最終碼。程式碼本身看起來紮實(有 CI、Vitest、ESLint、SECURITY.md),但**不要當作經過長期生產驗證的參考**——跟 pandoc、python-docx 那種十年老專案不是同一個信賴等級。

上游仍在活躍同步(上次 snapshot 距 clone 僅一天),所以這份 clone 會很快過時。要更新直接 `cd reference/genoffice && git pull`;因為是 `--depth 1` 淺 clone,必要時 `git fetch --unshallow` 才拿得到完整歷史(但如上所述,歷史本身資訊量不高)。

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

**Office.js vs Common API**:Office.js 其實是兩個 object model——Word-specific(`Word.*`)+ Common API(`Office.*`)。macdoc 關心的只有前者(OOXML 功能),Common API(dialog、UI、settings)不對映 OOXML,不參考。

**核心參考**
- [Word JavaScript API 主頁](https://learn.microsoft.com/en-us/javascript/api/word) — 所有類別/方法/屬性查表入口
- [Word JavaScript API overview](https://learn.microsoft.com/en-us/office/dev/add-ins/reference/overview/word-add-ins-reference-overview) — 官方導覽,理解 Office.js / Common API 的區分
- [Word JavaScript 物件模型概念](https://learn.microsoft.com/en-us/office/dev/add-ins/word/word-add-ins-core-concepts) — RequestContext、LoadOptions、proxy object 等基礎概念(重要:這些是 Office.js 基建,**不對映 OOXML**,不用實作)
- [Word API 需求集](https://learn.microsoft.com/en-us/javascript/api/requirement-sets/word/word-api-requirement-sets) — WordApi 1.1 ~ 1.9 版本相容性,判斷功能穩定度

**常用類別深入**
- [Word.Document](https://learn.microsoft.com/en-us/javascript/api/word/word.document) — 文件根物件,sections / body / contentControls 入口
- [Word.Paragraph](https://learn.microsoft.com/en-us/javascript/api/word/word.paragraph) — 段落操作、inline 元素、格式
- [Word.Table](https://learn.microsoft.com/en-us/javascript/api/word/word.table) — 表格、合併儲存格、條件格式(§9)
- [Word.ContentControl](https://learn.microsoft.com/en-us/javascript/api/word/word.contentcontrol) — SDT 結構化文件標籤(§1)
- [Word.Style](https://learn.microsoft.com/en-us/javascript/api/word/word.style) / [ParagraphFormat](https://learn.microsoft.com/en-us/javascript/api/word/word.paragraphformat) — 樣式系統(§8)
- [Word.Shape](https://learn.microsoft.com/en-us/javascript/api/word/word.shape) / [InlinePicture](https://learn.microsoft.com/en-us/javascript/api/word/word.inlinepicture) — 圖片與形狀(§10)
- [Word.TrackedChange](https://learn.microsoft.com/en-us/javascript/api/word/word.trackedchange) / [Revision](https://learn.microsoft.com/en-us/javascript/api/word/word.revision) — 修訂(§2)
- [Word.Comment](https://learn.microsoft.com/en-us/javascript/api/word/word.comment) — 註解(§7)
- [Word.Bookmark](https://learn.microsoft.com/en-us/javascript/api/word/word.bookmark) / [Field](https://learn.microsoft.com/en-us/javascript/api/word/word.field) / [Hyperlink](https://learn.microsoft.com/en-us/javascript/api/word/word.hyperlink) — 跳轉與動態內容(§5、§14、§17)
- [Word.CustomXmlPart](https://learn.microsoft.com/en-us/javascript/api/word/word.customxmlpart) — 自訂 XML 資料(§11)

**實驗與範例**
- [Script Lab](https://learn.microsoft.com/en-us/office/dev/add-ins/overview/explore-with-script-lab) — Word 內建的互動式 Office.js playground。實作新功能前先在這裡跑 Office.js 看 Word 實際行為,再決定 Swift 怎麼做
- [Office Add-ins 範例程式庫](https://github.com/OfficeDev/office-js-snippets) — Script Lab 可直接 import 的 snippets,找 `Word/` 資料夾
- [Word add-in 教學](https://learn.microsoft.com/en-us/office/dev/add-ins/tutorials/word-tutorial) — 官方 hands-on tutorial

**Issue #43 尚未納入 roadmap 但 Office.js 有暴露的類別**(未來 sub-issue 候選)
- `Word.Annotation` — 段落註記(Word 2021+,不是 Comment)
- `Word.Bibliography` — 參考文獻源管理(跟 `che-zotero-mcp` 生態可能整合點)
- `Word.TableOfContents` / `Word.Index` — 目錄與索引的專屬類別(issue #43 §5 只談 TOC field,沒涵蓋這層 API)
- `Word.Coauthor` / `Word.Conflict` / `Word.CoauthoringLock` — 即時協作(Word Online,多半跟 macdoc headless 場景無關,優先級最低)

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
