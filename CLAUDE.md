# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Repository Overview

**macdoc** 是一個原生 macOS 文件處理工具集，專注於文件格式解析、轉換和 OCR 功能。整個專案使用 Swift 開發，充分利用 Apple 平台的原生能力。

## Project Structure

```
macdoc/                        # Monorepo 根目錄（同時也是 CLI 專案）
├── Package.swift              # CLI 的 Swift Package 定義
├── Sources/
│   ├── MacDocCLI/             # CLI 入口點
│   ├── MacDocCore/            # 核心協議和模型
│   └── WordToMD/              # Word 轉 Markdown 實作
├── Tests/
├── docs/                      # 開發文檔和對話記錄
├── packages/                  # 本地套件（各自獨立 git repo，.gitignore 忽略）
│   ├── ooxml-swift/           # OOXML (Word/Excel) 解析
│   ├── markdown-swift/        # Markdown 生成
│   ├── marker-swift/          # 圖片分類 + Marker 輸出
│   └── surya-swift/           # OCR 文字辨識
├── mcp/                       # MCP 工具（各自獨立 git repo，.gitignore 忽略）
│   ├── che-word-mcp/          # Word 文件處理 MCP（84 工具）
│   └── che-pdf-mcp/           # PDF 文件處理 MCP（25 工具）
└── reference/                 # 參考專案（.gitignore 忽略）
```

## Package Dependencies

```
macdoc (CLI)
├── ooxml-swift          # Word 文件解析
├── markdown-swift       # Markdown 輸出
└── marker-swift         # 圖片處理 + metadata
    └── markdown-swift   # (共用依賴)

che-word-mcp (MCP)
└── ooxml-swift          # ← 共用本地套件！

che-pdf-mcp (MCP)
└── Vision.framework     # 原生 OCR（可選整合 surya-swift）

surya-swift              # 獨立套件，進階 OCR 功能
```

## Development Commands

### Build & Run

```bash
# 建構主專案（在 repo 根目錄）
swift build

# 執行 CLI
swift run macdoc word input.docx -o output.md

# 使用 Marker 模式（輸出 metadata + images）
swift run macdoc word input.docx --marker -o output/

# 建構個別套件
cd packages/ooxml-swift && swift build
cd packages/markdown-swift && swift build
cd packages/marker-swift && swift build
cd packages/surya-swift && swift build

# 建構 MCP 工具（release 模式）
cd mcp/che-word-mcp && swift build -c release
cd mcp/che-pdf-mcp && swift build -c release
```

### Testing

```bash
# 測試主專案（在 repo 根目錄）
swift test

# 測試個別套件
cd packages/ooxml-swift && swift test
cd packages/marker-swift && swift test
```

### Clean Build

```bash
# 清除快取（更新本地套件後建議執行）
swift package clean && swift build
```

## Package Details

### macdoc (主專案)
- **用途**：CLI 工具，整合各套件功能
- **主要功能**：Word 轉 Markdown
- **輸出模式**：
  - 標準模式：單一 `.md` 文件
  - Marker 模式：`.md` + `_meta.json` + `images/`

### ooxml-swift
- **用途**：解析 Office Open XML 格式（.docx）
- **功能**：
  - 段落、表格、清單解析
  - 圖片提取（嵌入式 + 連結）
  - 語義標註（標題層級、公式、圖片類型）
  - 樣式解析
- **依賴**：ZIPFoundation

### markdown-swift
- **用途**：生成 Markdown 文本
- **功能**：
  - Streaming 輸出（低記憶體佔用）
  - 行內格式（粗體、斜體、連結）
  - 特殊字元跳脫
- **依賴**：無

### marker-swift
- **用途**：圖片分類和 Marker 格式輸出
- **功能**：
  - 圖片分類協議（可擴展 ML 分類器）
  - Metadata JSON 生成
  - 圖片管理和輸出
- **依賴**：markdown-swift

### surya-swift
- **用途**：OCR 文字辨識
- **功能**：
  - 文字偵測（Detection）
  - 文字辨識（Recognition）
  - 表格偵測（Table）
  - 閱讀順序分析（ReadingOrder）
  - LaTeX 公式辨識
- **依賴**：swift-async-algorithms
- **平台**：macOS 14+, iOS 17+

## MCP Tools

### che-word-mcp（84 工具）
- **用途**：Word 文件處理 MCP，讓 Claude 能讀取和分析 Word 文件
- **功能**：
  - OOXML 解析（段落、表格、清單、圖片）
  - 樣式和格式資訊提取
  - 文件結構分析
  - 圖片提取
- **依賴**：ooxml-swift（本地 path 依賴）
- **架構**：單一 Server.swift（~4500 行）
- **Binary**：`.build/release/CheWordMCP`

### che-pdf-mcp（25 工具）
- **用途**：PDF 文件處理 MCP，讓 Claude 能讀取和分析 PDF 文件
- **功能**：
  - PDF 解析和文字提取
  - Vision OCR（原生 macOS）
  - 圖片提取
  - 頁面資訊
- **依賴**：Vision.framework, PDFKit
- **架構**：模組化（分離 OCR、解析邏輯）
- **Binary**：`.build/release/ChePDFMCP`

### MCP 配置範例
```json
{
  "mcpServers": {
    "che-word-mcp": {
      "command": "/path/to/macdoc/mcp/che-word-mcp/.build/release/CheWordMCP"
    },
    "che-pdf-mcp": {
      "command": "/path/to/macdoc/mcp/che-pdf-mcp/.build/release/ChePDFMCP"
    }
  }
}
```

## Architecture Principles

### Streaming Architecture
所有轉換器採用 streaming 設計，避免將整份文件載入記憶體：
```swift
protocol StreamingOutput {
    func write(_ text: String) throws
    func writeLine(_ text: String) throws
}
```

### Semantic Annotation
ooxml-swift 在解析階段產生語義標註，讓轉換器直接使用：
```swift
// 解析時標註
paragraph.semantic = .heading(level: 1)
paragraph.semantic = .bulletListItem(level: 0)
run.semantic = .formula(.omml)

// 轉換時直接使用
switch paragraph.semantic?.type {
case .heading(let level): // ...
case .paragraph: // ...
}
```

### Protocol-Based Extensibility
- `DocumentConverter` - 文件轉換協議
- `ImageClassifier` - 圖片分類協議
- `StreamingOutput` - 輸出協議

## Local Package Update Workflow

由於使用 `path:` 本地依賴，更新套件後：

```bash
# 1. 在套件目錄提交變更
cd packages/ooxml-swift
git add . && git commit -m "feat: 描述"
git push origin main

# 2. 回到主專案根目錄清除快取
cd ../..
swift package clean
swift build
```

## Sub-Repositories

主 repo 透過 `.gitignore` 忽略以下目錄，各自獨立管理。重建環境時在對應目錄 `git clone` 即可。

| 目錄 | Git Remote | 說明 |
|------|-----------|------|
| `.` (root) | https://github.com/kiki830621/macdoc.git | 主專案 CLI |
| `packages/ooxml-swift` | https://github.com/kiki830621/ooxml-swift.git | OOXML 解析 |
| `packages/markdown-swift` | https://github.com/kiki830621/markdown-swift.git | Markdown 生成 |
| `packages/marker-swift` | (local only) | 圖片分類 |
| `packages/surya-swift` | (local only) | OCR 文字辨識 |
| `mcp/che-word-mcp` | https://github.com/kiki830621/che-word-mcp.git | Word MCP |
| `mcp/che-pdf-mcp` | https://github.com/kiki830621/che-pdf-mcp.git | PDF MCP |
| `reference/pandoc` | https://github.com/jgm/pandoc.git | 參考用 |

## Key Files

### macdoc
- `Sources/MacDocCLI/MacDoc.swift` - CLI 入口點
- `Sources/WordToMD/WordConverter.swift` - 標準轉換器
- `Sources/WordToMD/MarkerWordConverter.swift` - Marker 模式轉換器

### ooxml-swift
- `Sources/OOXMLSwift/IO/DocxReader.swift` - Word 文件讀取
- `Sources/OOXMLSwift/Models/SemanticAnnotation.swift` - 語義標註定義
- `Sources/OOXMLSwift/Models/Paragraph.swift` - 段落模型

### marker-swift
- `Sources/MarkerSwift/MarkerWriter.swift` - Marker 輸出
- `Sources/MarkerSwift/Protocols/ImageClassifier.swift` - 分類協議

### che-word-mcp
- `Sources/CheWordMCP/Server.swift` - MCP 伺服器主體（84 工具定義）
- `Package.swift` - 依賴宣告（使用本地 ooxml-swift）

### che-pdf-mcp
- `Sources/ChePDFMCP/Server.swift` - MCP 伺服器主體（25 工具定義）
- `Sources/ChePDFMCP/VisionOCR.swift` - Vision OCR 實作

## Testing Files

測試時可使用任意 `.docx` 文件：
```bash
swift run macdoc word /path/to/test.docx --marker -o /tmp/test_output/
```

## Platform Requirements

- macOS 13+ (macdoc, ooxml-swift, markdown-swift, marker-swift)
- macOS 14+ / iOS 17+ (surya-swift)
- Swift 5.9+
