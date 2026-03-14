# Modular Architecture: Recomposable Packages

## 核心原則

> **每個 package 是獨立的街道，不是大樓裡的某一層。**
>
> CLI、MCP、App 是不同的交通工具，開過同一條街。街道不因為車子改變而改變。

Package 不屬於任何特定的消費者（CLI、MCP、App）。
消費者選擇需要的 package 組合，而 package 本身不知道誰在使用它。

---

## Package 分類

### Layer 1: Format Packages（格式層）

負責讀寫特定格式，不包含任何轉換邏輯。

| Package | 職責 | 方向 |
|---------|------|------|
| `ooxml-swift` | 讀寫 .docx (OOXML) | 雙向 |
| `markdown-swift` | 生成 Markdown | 寫 |
| `marker-swift` | 圖片分類 + Marker 格式輸出 | 寫 |
| `surya-swift` | OCR 文字辨識 | 讀 |
| `pdf-to-latex-swift` | PDF block 偵測 + AI 轉寫 LaTeX | 讀→寫 |
| `biblatex-apa-swift` | 解析 .bib 檔 + APA 7 驗證 | 讀（外部 repo） |

格式 package 的規則：
- **只處理一種格式**
- **不依賴其他格式 package**（`ooxml-swift` 不知道 Markdown 的存在）
- **可獨立發布、獨立使用**

### Layer 2: Protocol / Model Packages（協議層）

定義轉換器的共用介面和語意模型，不包含最終輸出實作。

| Package | 內容 |
|---------|------|
| `common-converter-swift` | `DocumentConverter` protocol, `StreamingOutput` protocol, `ConversionOptions`, `ConversionError` |
| `bib-apa-swift` | `APAReference` 語意模型, `APAStyler` (BibEntry → APAReference), `APAReferenceRenderer` protocol |

協議 package 的規則：
- **只依賴 Layer 1 format packages**（`bib-apa-swift` 依賴 `biblatex-apa-swift`）
- **只有 protocols、structs、enums + 語意轉換邏輯**
- **所有 renderer 都依賴它，但它不依賴任何 renderer**

### Layer 3: Converter / Renderer Packages（轉換層）

橋接 Layer 1-2 的 package，實現特定的 source → target 轉換或渲染。

| Package | 依賴 | 轉換 |
|---------|------|------|
| `word-to-md-swift` | `common-converter-swift` + `ooxml-swift` + `markdown-swift` | Word → Markdown |
| `bib-apa-to-md-swift` | `bib-apa-swift` | APAReference → Markdown |
| `bib-apa-to-html-swift` | `bib-apa-swift` | APAReference → HTML |
| *(未來)* `pdf-to-md-swift` | `common-converter-swift` + PDFKit/surya-swift | PDF → Markdown |
| *(未來)* `html-to-md-swift` | `common-converter-swift` + SwiftSoup | HTML → Markdown |

轉換 package 的規則：
- **依賴 Layer 2 協議 package +（可選）Layer 1 format packages**
- **實作對應 protocol**（`DocumentConverter` 或 `APAReferenceRenderer`）
- **遵循 streaming 模式**（見 `philosophy.md`）
- **遵循 target-aware extraction**（見 `functional-correspondence.md`）

### Layer 4: Consumer Applications（消費層）

組合 Layer 1-3 的 package，提供使用者介面。

| Consumer | 組合方式 | 介面 |
|----------|---------|------|
| `macdoc` CLI | `word-to-md-swift` + `marker-swift` + `pdf-to-latex-swift` + ArgumentParser | 命令列 |
| `che-word-mcp` | `ooxml-swift`（讀寫）+ `macdoc` CLI（轉換） | MCP (Claude) |
| *(未來)* `che-pdf-mcp` | PDFKit + `pdf-to-md-swift` | MCP (Claude) |

消費者的規則：
- **是 package 的組裝者，不是邏輯的擁有者**
- **不實作轉換邏輯**（轉換在 Layer 3）
- **不實作格式解析**（解析在 Layer 1）
- **只負責：參數解析、路由、輸出呈現**
- **轉換功能優先委託 CLI**，而非直接嵌入 library（見 [adr-mcp-delegates-to-cli.md](adr-mcp-delegates-to-cli.md)）

---

## 依賴圖

```
Layer 4 (Consumers)          Layer 3 (Converters)       Layer 2 (Protocols)     Layer 1 (Formats)
─────────────────           ──────────────────         ─────────────────       ────────────────

macdoc CLI ──────────────→ word-to-md-swift ──┬──→ common-converter-swift    ooxml-swift
  ├──→ marker-swift                          ├──→ ooxml-swift            markdown-swift
  └──→ pdf-to-latex-swift (PDFToLaTeXCore)   └──→ markdown-swift         marker-swift
       └──→ PDFKit + Vision + AI CLI tools                               pdf-to-latex-swift

che-word-mcp
  ├──→ ooxml-swift (直接讀寫 Word, 145 tools)
  └──→ macdoc CLI (轉換委託, exec binary)

che-pdf-mcp ─────────────→ pdf-to-md-swift ──┬──→ common-converter-swift
                                             └──→ surya-swift / PDFKit

che-biblatex-mcp ────────→ bib-apa-to-md-swift ──→ bib-apa-swift ──→ biblatex-apa-swift
```

依賴永遠是 **Layer 4 → 3 → 2 → 1**，不會反向，不會跨層。

---

## 重組範例

### 場景 A：只需要讀 Word 文件（不轉換）

```swift
dependencies: [
    .package(url: ".../ooxml-swift.git", from: "0.1.0")
]
```

只拿 `ooxml-swift`，不需要 `markdown-swift`、不需要 `word-to-md-swift`。

### 場景 B：MCP Server 需要讀寫 Word + 匯出 Markdown

```swift
// Swift 依賴只需要 ooxml-swift
dependencies: [
    .package(url: ".../ooxml-swift.git", from: "0.3.0")
]
```

`che-word-mcp` 用 `ooxml-swift` 做 Word 操作（145 tools）。
`export_markdown` 改為呼叫 `macdoc` CLI binary，不再嵌入轉換 library。
詳見 [adr-mcp-delegates-to-cli.md](adr-mcp-delegates-to-cli.md)。

### 場景 C：CLI 需要轉換 + Marker 模式

```swift
dependencies: [
    .package(url: ".../word-to-md-swift.git", from: "0.1.0"),
    .package(url: ".../marker-swift.git", from: "0.1.0"),
    .package(path: "packages/surya-swift")
]
```

### 場景 D：第三方只想用 Markdown 生成器

```swift
dependencies: [
    .package(url: ".../markdown-swift.git", from: "0.1.0")
]
```

完全不需要知道 Word、MCP 的存在。

---

## 從現狀到目標的遷移路徑

### 現狀

```
macdoc (monorepo)
├── MacDocCore/      ← protocols, 內嵌在 monorepo
├── WordToMD/        ← 轉換邏輯, 內嵌在 monorepo
└── MacDocCLI/       ← CLI

che-word-mcp
└── OOXMLSwift.toMarkdown()  ← 重複且品質較差的實作
```

問題：
1. `WordToMD` 被鎖在 monorepo 裡，MCP 無法使用
2. `OOXMLSwift` 內建 `toMarkdown()` 混淆了格式層和轉換層的邊界
3. 同一個能力（Word→MD）有兩套實作

### 目標

```
common-converter-swift   (獨立 package, Layer 2)
word-to-md-swift      (獨立 package, Layer 3)

macdoc CLI            (consumer, Layer 4)
├── word-to-md-swift
└── marker-swift

che-word-mcp          (consumer, Layer 4)
├── ooxml-swift
└── word-to-md-swift  ← export_markdown 使用統一實作
```

### 遷移步驟

1. **抽出 `common-converter-swift`**
   - 從 `MacDocCore/` 搬出 protocols 和 models
   - 建立獨立 git repo
   - ~194 行，零依賴

2. **抽出 `word-to-md-swift`**
   - 從 `WordToMD/` 搬出 `WordConverter`
   - 依賴 `common-converter-swift` + `ooxml-swift` + `markdown-swift`
   - `MarkerWordConverter` 可留在 `macdoc` 或作為 optional target

3. **更新 `macdoc` CLI**
   - `MacDocCore` → 改為依賴 `common-converter-swift`
   - `WordToMD` → 改為依賴 `word-to-md-swift`

4. **更新 `che-word-mcp`**
   - 新增依賴 `word-to-md-swift`
   - `export_markdown` 改為呼叫 `WordConverter`
   - 移除 `OOXMLSwift.toMarkdown()`

5. **清理 `ooxml-swift`**
   - 移除 `toMarkdown()` 方法
   - 格式 package 不再包含轉換邏輯

---

## 設計決策記錄

### 為什麼 `common-converter-swift` 要獨立？

如果只有 `word-to-md-swift` 一個轉換器，把 protocols 內嵌在裡面就好。
但規劃中有 `pdf-to-md-swift`、`html-to-md-swift`，它們都需要：

- `DocumentConverter` protocol
- `StreamingOutput` protocol
- `ConversionOptions` / `ConversionError`

共用 protocol 層確保所有轉換器有一致的介面，消費者可以用相同的方式呼叫任何轉換器。

### 為什麼 MCP 只依賴 `ooxml-swift`，轉換功能委託 CLI？

`che-word-mcp` 的核心職責是**讀寫 Word 文件**（插入段落、改格式、存檔），需要 `ooxml-swift` 的記憶體模型。
`export_markdown` 的轉換功能改為呼叫 `macdoc` CLI，原因：

1. **避免 API 鏡像維護**：不需要在 MCP 側重複 `ConversionOptions` 的每個欄位
2. **效能分離**：MCP 記憶體常駐模型無法 streaming，CLI 可以（O(1) 記憶體）
3. **單一真相來源**：macdoc CLI 是轉換功能的唯一入口

```
che-word-mcp
├── ooxml-swift          ← 145 個 tools 直接操作
└── macdoc (exec)        ← export_markdown 委託 CLI
```

詳見 [adr-mcp-delegates-to-cli.md](adr-mcp-delegates-to-cli.md)。

### `pdf-to-latex-swift` 為什麼用 CLI 工具而非 API？

`pdf-to-latex-swift` 的 AI 轉寫步驟透過呼叫外部 **CLI 工具**（如 `codex`、`claude`、`gemini`）來執行，
而非直接呼叫 LLM API。

這個設計選擇的原因：

1. **認證管理由 CLI 負責**：每個 CLI 工具自行管理 API key、OAuth token 等，macdoc 不需要處理認證細節
2. **模型切換零成本**：透過 `--model` 參數選擇模型，不需要改程式碼或重新編譯
3. **與 ADR 一致**：與 [adr-mcp-delegates-to-cli.md](adr-mcp-delegates-to-cli.md) 中 MCP 委託 CLI 的原則相同——CLI 是功能的唯一入口
4. **離線開發友善**：核心 pipeline（PDF 掃描、block 偵測、LaTeX 組裝）完全離線，只有轉寫步驟需要 AI CLI

**使用前提**：使用者必須先安裝並設定好對應的 AI CLI 工具：

| CLI 工具 | 設定方式 |
|----------|---------|
| `codex` | OpenAI Codex CLI，需 `OPENAI_API_KEY` |
| `claude` | Anthropic Claude CLI，需已登入 |
| `gemini` | Google Gemini CLI，需已登入 |

詳見 [pdf-to-latex-swift README](../packages/pdf-to-latex-swift/README.md)。

### 為什麼不把 `MarkerWordConverter` 也放進 `word-to-md-swift`？

`MarkerWordConverter` 額外依賴 `marker-swift`（圖片分類），如果放進去會讓 `word-to-md-swift` 變重。
MCP 做 `export_markdown` 不需要圖片分類。

兩個選擇都合理：
- **作為 optional target**：`word-to-md-swift` 裡有 `WordToMDMarker` target，只在需要時引入
- **留在 `macdoc`**：CLI 專屬功能，不對外暴露

### Style × Format 正交分離

`bib-to-apa-swift` 的 `BibToAPAFormatter` 將「APA 7 引用風格邏輯」和「Markdown 輸出格式」混在一起。
重構為 `bib-apa-swift`（語意模型 + styler）+ `bib-apa-to-{output}-swift`（renderer）：

```
biblatex-apa-swift          (Layer 1: .bib 解析 + APA 驗證)
        ↓
bib-apa-swift               (Layer 2: APAStyler + APAReference 語意模型 + Renderer 協議)
        ↓
bib-apa-to-md-swift         (Layer 3: Markdown renderer)
bib-apa-to-html-swift       (Layer 3: HTML renderer + APA CSS)
```

**設計原則**：
- `APAReference` 是格式無關的語意模型，只描述「什麼內容、什麼語意樣式」（斜體、粗體、連結）
- 已知固定樣式的欄位（journal 一定斜體）存為 `String`，renderer 套用樣式
- 只有混合樣式欄位用 `StyledText`（`[TextSegment]`）
- 每個 renderer 實作 `APAReferenceRenderer` protocol，產生不同輸出格式

---

## 命名原則

### Package 命名

- **Package（內部程式）用副檔名**：`.bib` → `bib`、`.md` → `md`、`.html` → `html`、`.docx` → `ooxml`
- **MCP / 公開工具可用俗稱**：`che-word-mcp`、`che-bib-mcp`
- **文件轉換**：`{input}-to-{output}-swift`（如 `word-to-md-swift`）
- **風格轉換**：`{input}[-{style}]-to-{output}-swift`（如 `bib-apa-to-md-swift`）
  - input 放最前面（bib），style 作為修飾（apa），output 在 to 後面
- **協議層不含 output**：`bib-apa-swift`（類似 `common-converter-swift`）
