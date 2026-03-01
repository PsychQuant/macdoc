---
description: 規劃新文件格式加入 macdoc 生態系（轉換路徑、package 建立、架構遵循）
argument-hint: <format-name>
allowed-tools: Read, Glob, Grep, Bash(ls:*), Bash(cat:*), Bash(swift:*), AskUserQuestion, Agent, EnterPlanMode, Write, Edit
---

# Add Format — 新增文件格式到 macdoc

將新的文件格式整合進 macdoc 4 層架構，包括：轉換路徑分析、package 建立、依賴設定、CLI/MCP 整合。

## 參數

- `$ARGUMENTS` = 格式名稱（如 `html`、`pdf`、`epub`、`latex`）

---

## Phase 0: 現況盤點

### Step 1: 讀取現有架構

```
讀取以下檔案以了解當前狀態：
- /Users/che/Developer/macdoc/Package.swift（頂層依賴）
- /Users/che/Developer/macdoc/docs/modular-architecture.md（架構文檔）
- /Users/che/Developer/macdoc/docs/functional-correspondence.md（元素對應表）
- /Users/che/Developer/macdoc/docs/lossless-conversion.md（FidelityTier 設計）
```

### Step 2: 盤點現有格式和轉換路徑

列出當前支援的格式和已實作的轉換路徑：

| 層級 | Package | 格式 | 方向 |
|------|---------|------|------|
| Layer 1 (Format) | `ooxml-swift` | Word (.docx) | 讀+寫 |
| Layer 1 (Format) | `markdown-swift` | Markdown (.md) | 寫 |
| Layer 1 (Format) | `marker-swift` | Marker (MD+figures+meta) | 寫 |
| Layer 1 (Format) | `surya-swift` | PDF (OCR) | 讀 |
| Layer 2 (Protocol) | `doc-converter-swift` | — | 共用介面 |
| Layer 3 (Converter) | `word-to-md-swift` | Word→MD | 單向 |
| Layer 3 (Converter) | `md-to-word-swift` | MD→Word | 單向 |

### Step 3: 確認新格式資訊

用 AskUserQuestion 釐清：

1. **格式名稱**：`$ARGUMENTS`（如 `html`）
2. **副檔名**：`.html`、`.htm` 等
3. **需要的方向**：
   - 只讀（解析該格式 → 轉出 MD/Word）
   - 只寫（從 MD/Word → 產出該格式）
   - 雙向（讀+寫，支援 round-trip）
4. **優先轉換對象**：先做 `{format}↔MD` 還是 `{format}↔Word`？
5. **已知的 Swift 函式庫**：例如 HTML 用 SwiftSoup、PDF 用 surya-swift

---

## Phase 1: 轉換路徑規劃

### 直接轉換 vs 間接轉換

macdoc 的核心原則：**Markdown 是 hub format**。新格式不需要和每個既有格式建立直接轉換，而是透過 MD 做 hub：

```
           ┌──→ Word (.docx)
           │
 新格式 ←──→ Markdown (hub) ←──→ 其他格式
           │
           └──→ Marker (MD+meta)
```

### 轉換路徑決策矩陣

對每組格式對，決定是否需要直接轉換路徑：

| 轉換路徑 | 直接 | 經 MD hub | 不需要 | 理由 |
|----------|:----:|:---------:|:------:|------|
| `{format}` → MD | ? | — | ? | 基本路徑，幾乎一定需要 |
| MD → `{format}` | ? | — | ? | 反向路徑，round-trip 需要 |
| `{format}` → Word | ? | ? | ? | 可經 MD hub 間接完成 |
| Word → `{format}` | ? | ? | ? | 可經 MD hub 間接完成 |
| `{format}` → Marker | ? | ? | ? | 通常經 MD hub |
| `{format}` → PDF | ? | ? | ? | 通常經 MD hub |

**判斷原則**：
- 直接轉換：當 hub 會損失重要資訊時（如 Word→Word 的 round-trip 不能經 MD）
- 經 MD hub：大多數情況，足夠且簡單
- 不需要：低優先或無意義的路徑

### 輸出：轉換路徑清單

列出需要建立的 converter packages，標注優先順序：

```
P1 (必要)：{format}-to-md-swift
P2 (round-trip)：md-to-{format}-swift
P3 (直接路徑，如需要)：{format}-to-word-swift / word-to-{format}-swift
```

---

## Phase 2: Package 架構設計

### 命名規則

嚴格遵循現有慣例：

| 類型 | 命名 | 範例 |
|------|------|------|
| Format (Layer 1) | `{format}-swift` | `html-swift` |
| Converter (Layer 3) | `{source}-to-{target}-swift` | `html-to-md-swift` |
| Swift Module | CamelCase | `HTMLSwift`, `HTMLToMDSwift` |

### 依賴規則（不可違反）

```
Layer 4 (CLI/MCP) → Layer 3 (Converter) → Layer 2 (Protocol) → Layer 1 (Format)
                                                    ↓
                                          doc-converter-swift
```

- Converter packages **不可** import 其他 converter packages
- Format packages **不可** import converter packages
- 只有 Layer 4 (CLI/MCP) 可以組合多個 converters

### 需要建立的 Packages

對每個需要的 package，列出：

#### {format}-swift (Layer 1, 如需要)

```
packages/{format}-swift/
├── Package.swift
├── Sources/{Format}Swift/
│   ├── Models/          # 格式特有的資料模型
│   ├── IO/              # Reader / Writer
│   └── {Format}Reader.swift / {Format}Writer.swift
└── Tests/
```

**Package.swift 模板**：
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "{Format}Swift",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "{Format}Swift", targets: ["{Format}Swift"])
    ],
    dependencies: [
        // Layer 1: 只依賴外部格式庫，不依賴 macdoc 內部套件
    ],
    targets: [
        .target(name: "{Format}Swift", dependencies: [...]),
        .testTarget(name: "{Format}SwiftTests", dependencies: ["{Format}Swift"])
    ]
)
```

#### {format}-to-md-swift (Layer 3)

```
packages/{format}-to-md-swift/
├── Package.swift
├── Sources/{Format}ToMDSwift/
│   ├── {Format}Converter.swift    # 實作 DocumentConverter
│   └── ...（轉換邏輯）
└── Tests/
```

**依賴**：
```swift
dependencies: [
    .package(path: "../doc-converter-swift"),   // Layer 2 Protocol
    .package(path: "../{format}-swift"),         // Layer 1 Source
    .package(path: "../markdown-swift"),         // Layer 1 Target
]
```

#### md-to-{format}-swift (Layer 3, 如需要)

同上結構，依賴反轉 source/target。

### ConversionOptions 擴展

如果新格式需要特殊選項，在 `doc-converter-swift/Models/ConversionOptions.swift` 中新增欄位。

**重要**：新欄位必須有合理的預設值，不影響既有轉換行為。

---

## Phase 3: FidelityTier 考量

### 新格式在三個 Tier 的表現

| Tier | 純 MD | MD + Figures | Marker (Full) |
|------|-------|-------------|---------------|
| 新格式保留多少資訊？ | ? | ? | ? |
| 哪些元素會丟失？ | ? | ? | ? |

### 元素對應表

建立新格式的 OOXML ↔ 新格式元素對應（參考 `docs/functional-correspondence.md`）：

| OOXML 元素 | Markdown 對應 | 新格式對應 | 損失？ |
|-----------|--------------|-----------|--------|
| Bold | `**text**` | ? | |
| Heading | `# text` | ? | |
| Table | GFM table | ? | |
| Image | `![](path)` | ? | |
| Footnote | `[^n]` | ? | |

---

## Phase 4: 實作順序

### 建議的實作順序（使用 EnterPlanMode 輸出完整計畫）

```
1. Layer 1: {format}-swift（格式讀取/寫入）
   - 資料模型
   - Reader（如需讀取）
   - Writer（如需寫入）
   - 單元測試

2. Layer 3: {format}-to-md-swift（主要轉換方向）
   - 實作 DocumentConverter protocol
   - 處理 FidelityTier
   - 處理 Practical Mode（headingHeuristic, preserveOriginalFormat）
   - 單元測試 + round-trip 測試

3. Layer 3: md-to-{format}-swift（反向，如需要）
   - 使用 swift-markdown 解析 MD AST
   - 建構目標格式
   - 單元測試

4. Layer 4: CLI 整合
   - MacDoc.swift 新增 subcommand
   - 頂層 Package.swift 加入依賴

5. Layer 4: MCP 整合（如需要）
   - che-word-mcp 或新建 MCP server
   - 新增 export/import tools
```

### 測試策略

- 每個 package 獨立測試（`swift test`）
- Round-trip 測試：`{format}` → MD → `{format}`，驗證資訊保留
- 整合測試：用真實文件測試完整轉換流程

---

## Phase 5: 文檔更新

完成實作後，更新以下文件：

1. **`docs/modular-architecture.md`** — 新增 package 到架構圖
2. **`docs/functional-correspondence.md`** — 新增元素對應表
3. **`/Users/che/Developer/mcp/CLAUDE.md`** — 如有新 MCP，更新專案總覽
4. **各 package 的 README.md**

---

## 快速參考：已有格式的 Swift 函式庫

| 格式 | 推薦函式庫 | 備註 |
|------|-----------|------|
| HTML | [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML 解析，類似 JSoup |
| PDF | surya-swift（已有） | OCR + layout；寫入可考慮 TPPDF |
| EPUB | [EPUBKit](https://github.com/nicklama/EPUBKit) 或自製 | EPUB 本質是 ZIP + XHTML |
| LaTeX | 自製 parser 或 regex | 結構化文本，可直接解析 |
| RTF | Apple NSAttributedString | macOS 原生 API |
| CSV/TSV | Swift 標準庫 | 主要對應 Table 元素 |
