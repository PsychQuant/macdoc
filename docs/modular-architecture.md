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

格式 package 的規則：
- **只處理一種格式**
- **不依賴其他格式 package**（`ooxml-swift` 不知道 Markdown 的存在）
- **可獨立發布、獨立使用**

### Layer 2: Protocol Package（協議層）

定義轉換器的共用介面，不包含實作。

| Package | 內容 |
|---------|------|
| `doc-converter-swift` | `DocumentConverter` protocol, `StreamingOutput` protocol, `ConversionOptions`, `ConversionError` |

協議 package 的規則：
- **零外部依賴**
- **只有 protocols、structs、enums**
- **所有轉換器都依賴它，但它不依賴任何轉換器**

### Layer 3: Converter Packages（轉換層）

橋接 Layer 1 的格式 package，實現特定的 source → target 轉換。

| Package | 依賴 | 轉換 |
|---------|------|------|
| `word-to-md-swift` | `doc-converter-swift` + `ooxml-swift` + `markdown-swift` | Word → Markdown |
| *(未來)* `pdf-to-md-swift` | `doc-converter-swift` + PDFKit/surya-swift | PDF → Markdown |
| *(未來)* `html-to-md-swift` | `doc-converter-swift` + SwiftSoup | HTML → Markdown |

轉換 package 的規則：
- **依賴一個 source format package + 一個 target format package + 協議 package**
- **實作 `DocumentConverter` protocol**
- **遵循 streaming 模式**（見 `philosophy.md`）
- **遵循 target-aware extraction**（見 `functional-correspondence.md`）

### Layer 4: Consumer Applications（消費層）

組合 Layer 1-3 的 package，提供使用者介面。

| Consumer | 組合方式 | 介面 |
|----------|---------|------|
| `macdoc` CLI | `word-to-md-swift` + `marker-swift` + ArgumentParser | 命令列 |
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

macdoc CLI ──────────────→ word-to-md-swift ──┬──→ doc-converter-swift    ooxml-swift
  └──→ marker-swift                          ├──→ ooxml-swift            markdown-swift
                                             └──→ markdown-swift         marker-swift

che-word-mcp
  ├──→ ooxml-swift (直接讀寫 Word, 145 tools)
  └──→ macdoc CLI (轉換委託, exec binary)

che-pdf-mcp ─────────────→ pdf-to-md-swift ──┬──→ doc-converter-swift
                                             └──→ surya-swift / PDFKit
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
doc-converter-swift   (獨立 package, Layer 2)
word-to-md-swift      (獨立 package, Layer 3)

macdoc CLI            (consumer, Layer 4)
├── word-to-md-swift
└── marker-swift

che-word-mcp          (consumer, Layer 4)
├── ooxml-swift
└── word-to-md-swift  ← export_markdown 使用統一實作
```

### 遷移步驟

1. **抽出 `doc-converter-swift`**
   - 從 `MacDocCore/` 搬出 protocols 和 models
   - 建立獨立 git repo
   - ~194 行，零依賴

2. **抽出 `word-to-md-swift`**
   - 從 `WordToMD/` 搬出 `WordConverter`
   - 依賴 `doc-converter-swift` + `ooxml-swift` + `markdown-swift`
   - `MarkerWordConverter` 可留在 `macdoc` 或作為 optional target

3. **更新 `macdoc` CLI**
   - `MacDocCore` → 改為依賴 `doc-converter-swift`
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

### 為什麼 `doc-converter-swift` 要獨立？

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

### 為什麼不把 `MarkerWordConverter` 也放進 `word-to-md-swift`？

`MarkerWordConverter` 額外依賴 `marker-swift`（圖片分類），如果放進去會讓 `word-to-md-swift` 變重。
MCP 做 `export_markdown` 不需要圖片分類。

兩個選擇都合理：
- **作為 optional target**：`word-to-md-swift` 裡有 `WordToMDMarker` target，只在需要時引入
- **留在 `macdoc`**：CLI 專屬功能，不對外暴露
