# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Repository Overview

**macdoc** 是一個原生 macOS 文件處理工具集，專注於文件格式解析、轉換和 OCR 功能。整個專案使用 Swift 開發，充分利用 Apple 平台的原生能力。

## Project Structure

```
macdoc/                        # Monorepo 根目錄（同時也是 CLI 專案）
├── Package.swift              # CLI 的 Swift Package 定義
├── Sources/
│   └── MacDocCLI/             # CLI 入口點
│       ├── MacDoc.swift       # 主命令 + Word 子命令
│       ├── MacDoc+Convert.swift # Convert 統一轉換入口（textutil-compatible）
│       ├── MacDoc+PDF.swift   # PDF 子命令群（Phase 1 pipeline）
│       ├── MacDoc+PDF+Phase2.swift # PDF Phase 2 consolidation 子命令
│       ├── MacDoc+Bib.swift   # Bib 子命令群（.bib → APA 7 HTML/Markdown/JSON）
│       ├── MacDoc+Config.swift# Config 子命令群（AI 設定管理）
│       └── CLIHelpers.swift   # 共用 helpers（validatedInputURL, writeStringOutput 等）
├── Tests/
├── docs/                      # 開發文檔和對話記錄
│   └── plans/                 # 實作計畫
├── packages/                  # 本地套件（.gitignore 忽略）
│   ├── common-converter-swift/   # Layer 2: 轉換器協議（DocumentConverter, StreamingOutput）
│   ├── word-to-md-swift/      # Layer 3: Word → Markdown
│   ├── html-to-md-swift/      # Layer 3: HTML → Markdown
│   ├── md-to-html-swift/      # Layer 3: Markdown → HTML
│   ├── word-to-html-swift/    # Layer 3: Word → HTML
│   ├── html-to-word-swift/    # Layer 3: HTML → Word
│   ├── md-to-word-swift/      # Layer 3: Markdown → Word
│   ├── pdf-to-md-swift/       # Layer 3: PDF → Markdown
│   ├── pdf-to-docx-swift/     # Layer 3: PDF → DOCX
│   ├── srt-to-html-swift/     # Layer 3: SRT → HTML
│   ├── marker-word-converter-swift/ # Layer 3: Word → Marker 模式
│   ├── bib-apa-to-html-swift/ # Layer 3: BibLaTeX → APA 7 HTML
│   ├── bib-apa-to-md-swift/   # Layer 3: BibLaTeX → APA 7 Markdown
│   ├── bib-apa-to-json-swift/ # Layer 3: BibLaTeX → APA 7 JSON
│   ├── bib-apa-swift/         # APA 7 styling engine
│   ├── ooxml-swift/           # Layer 1: OOXML (Word/Excel) 解析
│   ├── markdown-swift/        # Layer 1: Markdown 生成
│   ├── marker-swift/          # Layer 1: 圖片分類 + Marker 輸出
│   ├── surya-swift/           # Layer 1: OCR 文字辨識
│   └── pdf-to-latex-swift/    # PDF → LaTeX pipeline（Phase 1 + Phase 2）
├── mcp/                       # MCP 工具（各自獨立 git repo，.gitignore 忽略）
│   ├── che-word-mcp/          # Layer 4: Word 文件處理 MCP（145 工具）
│   └── che-pdf-mcp/           # Layer 4: PDF 文件處理 MCP（25 工具）
└── reference/                 # 參考專案（.gitignore 忽略）
```

## Package Dependencies

```
Layer 4 (Consumers)         Layer 3 (Converters)       Layer 2 (Protocols)     Layer 1 (Formats)

macdoc CLI ──────────┐
                     ├──→ word-to-md-swift ──┬──→ common-converter-swift    ooxml-swift
che-word-mcp ────────┘                       ├──→ ooxml-swift            markdown-swift
  └──→ ooxml-swift (直接讀寫)                 └──→ markdown-swift         marker-swift
                                                                        surya-swift
macdoc CLI ──→ pdf-to-latex-swift (PDFToLaTeXCore)                      pdf-to-latex-swift
macdoc CLI ──→ bib-apa-to-html-swift ──→ bib-apa-swift ──→ biblatex-apa-swift
macdoc CLI ──→ bib-apa-to-md-swift  ──→ bib-apa-swift ──→ biblatex-apa-swift

che-pdf-mcp
└──→ Vision.framework / surya-swift
```

詳見 [`docs/modular-architecture.md`](docs/modular-architecture.md)。

## Development Commands

### Build & Run

```bash
# 建構主專案（在 repo 根目錄）
swift build

# 執行 CLI — 統一轉換入口（textutil-compatible）
swift run macdoc convert --to md file.docx
swift run macdoc convert --to html file.md [--full]
swift run macdoc convert --to html file.srt
swift run macdoc convert --to html file.bib [--full] [--css minimal|web]
swift run macdoc convert --to md file.bib
swift run macdoc convert --to json file.bib
swift run macdoc convert --to md file.html

# 執行 CLI — Word
swift run macdoc word input.docx -o output.md

# 使用 Marker 模式（輸出 metadata + images）
swift run macdoc word input.docx --marker -o output/

# 執行 CLI — PDF to LaTeX（Phase 2 consolidation）
swift run macdoc pdf normalize --project /path/to/project
swift run macdoc pdf fix-envs --project /path/to/project [--fix]
swift run macdoc pdf compile-check --project /path/to/project
swift run macdoc pdf consolidate --project /path/to/project [--dry-run] [--agent codex|claude|gemini]

# 執行 CLI — Bib（APA 7 格式轉換）
swift run macdoc bib list paper.bib [--show-type]
swift run macdoc bib to-html paper.bib -o refs.html [--full] [--css minimal|web]
swift run macdoc bib to-md paper.bib -o refs.md [--heading]
swift run macdoc bib to-html paper.bib --key cheng2025 --key yang2024

# AI 設定管理
swift run macdoc config ai detect
swift run macdoc config ai list
swift run macdoc config ai set agent claude

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

### Layer 1: Format Packages

#### ooxml-swift
- **用途**：解析 Office Open XML 格式（.docx）
- **功能**：段落、表格、清單解析、圖片提取、語義標註、樣式解析
- **依賴**：ZIPFoundation

#### markdown-swift
- **用途**：生成 Markdown 文本
- **功能**：Streaming 輸出、行內格式、特殊字元跳脫
- **依賴**：無

#### marker-swift
- **用途**：圖片分類和 Marker 格式輸出
- **依賴**：markdown-swift

#### surya-swift
- **用途**：OCR 文字辨識（Detection、Recognition、Table、ReadingOrder、LaTeX）
- **依賴**：swift-async-algorithms
- **平台**：macOS 14+, iOS 17+

### Layer 2: Protocol Package

#### common-converter-swift
- **用途**：轉換器共用協議和模型
- **內容**：`DocumentConverter` protocol, `StreamingOutput` protocol, `ConversionOptions`, `ConversionError`
- **依賴**：無

### Layer 3: Converter Packages

#### word-to-md-swift
- **用途**：Word → Markdown 轉換
- **功能**：streaming 轉換、標題/清單/表格偵測、行內格式、YAML frontmatter
- **依賴**：common-converter-swift + ooxml-swift + markdown-swift
- **API**：`WordConverter.convert(input:)` / `WordConverter.convert(document:)` / `convertToString()`

### Layer 4: Consumers

#### pdf-to-latex-swift
- **用途**：PDF → LaTeX 轉換 pipeline
- **Phase 1**：PDF 掃描、頁面渲染、block 偵測、AI 轉寫、章節偵測、TeX 組裝
- **Phase 2（consolidation）**：
  - `AIConfig` — AI CLI 工具設定（codex/claude/gemini 自動偵測，`~/.config/macdoc/config.json`）
  - `LaTeXNormalizer` — document class 修正、符號正規化、跨頁去重
  - `LaTeXEnvChecker` — `\begin`/`\end` 配對檢查與修復
  - `TexCompileChecker` — pdflatex log 解析（支援 `!` 和 file-line-error 格式）
  - `Consolidator` — 機械步驟 + agent 迭代修復 orchestrator
- **依賴**：swift-argument-parser
- **平台**：macOS 14+

#### macdoc (CLI)
- **用途**：CLI 工具，整合各套件功能
- **Convert**：統一轉換入口（`macdoc convert --to <format> <file>`），textutil-compatible 語法
- **Word**：標準模式（`.md`）、Marker 模式（`.md` + `_meta.json` + `images/`）
- **PDF**：Phase 1（init → segment → render → blocks → transcribe → chapters → assemble）+ Phase 2（normalize → fix-envs → compile-check → consolidate）
- **Bib**：BibLaTeX → APA 7 HTML/Markdown（to-html, to-md, list）
- **Config**：AI 後端設定管理
- **依賴**：word-to-md-swift + marker-swift + pdf-to-latex-swift + html-to-md-swift + md-to-html-swift + srt-to-html-swift + bib-apa-to-html-swift + bib-apa-to-json-swift + bib-apa-to-md-swift + ArgumentParser

#### che-word-mcp（145 工具）
- **用途**：Word 文件處理 MCP，讓 Claude 能讀取和分析 Word 文件
- **功能**：OOXML 讀寫（段落、表格、清單、圖片、樣式）+ Markdown 匯出
- **依賴**：ooxml-swift + word-to-md-swift
- **架構**：單一 Server.swift（~9100 行）
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

## Package Update Workflow

所有套件皆使用 `url:` 遠端依賴。

```bash
# 1. 在套件目錄提交、推送、打 tag
cd packages/ooxml-swift
git add . && git commit -m "feat: 描述"
git push origin main
git tag v0.3.0 && git push --tags

# 2. 回到主專案更新依賴
cd ../..
swift package update
swift build
```

若需要本地開發迭代，可暫時將 `Package.swift` 中的 `url:` 改為 `path:` 指向本地路徑，完成後再改回。

## Sub-Repositories

主 repo 透過 `.gitignore` 忽略以下目錄，各自獨立管理。重建環境時在對應目錄 `git clone` 即可。

| 目錄 | Git Remote | 說明 |
|------|-----------|------|
| `.` (root) | https://github.com/PsychQuant/macdoc.git | 主專案 CLI |
| `packages/common-converter-swift` | https://github.com/PsychQuant/doc-converter-swift.git | 轉換器協議（remote 名 doc-converter-swift） |
| `packages/word-to-md-swift` | https://github.com/PsychQuant/word-to-md-swift.git | Word → MD 轉換 |
| `packages/ooxml-swift` | https://github.com/PsychQuant/ooxml-swift.git | OOXML 解析 |
| `packages/markdown-swift` | https://github.com/PsychQuant/markdown-swift.git | Markdown 生成 |
| `packages/marker-swift` | https://github.com/PsychQuant/marker-swift.git | 圖片分類 |
| `packages/surya-swift` | (local only) | OCR 文字辨識 |
| `packages/pdf-to-latex-swift` | (local, in macdoc repo) | PDF → LaTeX pipeline |
| `mcp/che-word-mcp` | https://github.com/PsychQuant/che-word-mcp.git | Word MCP |
| `mcp/che-pdf-mcp` | https://github.com/PsychQuant/che-pdf-mcp.git | PDF MCP |
| `reference/pandoc` | https://github.com/jgm/pandoc.git | 參考用 |

## Key Files

### macdoc
- `Sources/MacDocCLI/MacDoc.swift` - CLI 入口點（Convert + Word + PDF + Bib + Config 子命令群）
- `Sources/MacDocCLI/MacDoc+Convert.swift` - Convert 統一轉換入口（textutil-compatible）
- `Sources/MacDocCLI/MacDoc+PDF.swift` - PDF 子命令（Phase 1 pipeline + Phase 2 consolidation）
- `Sources/MacDocCLI/MacDoc+Bib.swift` - Bib 子命令（.bib → APA 7 HTML/Markdown）
- `Sources/MacDocCLI/MacDoc+Config.swift` - Config 子命令（AI 設定管理）
- `Sources/MarkerWordConverter/MarkerWordConverter.swift` - Marker 模式轉換器

### pdf-to-latex-swift
- `Sources/PDFToLaTeXCore/AIConfig.swift` - AI CLI 工具設定
- `Sources/PDFToLaTeXCore/LaTeXNormalizer.swift` - 機械式 LaTeX 清理
- `Sources/PDFToLaTeXCore/LaTeXEnvChecker.swift` - 環境配對檢查
- `Sources/PDFToLaTeXCore/TexCompileChecker.swift` - 編譯錯誤解析
- `Sources/PDFToLaTeXCore/Consolidator.swift` - consolidation orchestrator

### common-converter-swift
- `Sources/CommonConverterSwift/Protocols/DocumentConverter.swift` - 轉換器 protocol
- `Sources/CommonConverterSwift/Protocols/StreamingOutput.swift` - 串流輸出 protocol

### word-to-md-swift
- `Sources/WordToMDSwift/WordConverter.swift` - Word → Markdown 轉換器

### ooxml-swift
- `Sources/OOXMLSwift/IO/DocxReader.swift` - Word 文件讀取
- `Sources/OOXMLSwift/Models/SemanticAnnotation.swift` - 語義標註定義

### che-word-mcp
- `Sources/CheWordMCP/Server.swift` - MCP 伺服器主體（145 工具）
- `Package.swift` - 依賴 ooxml-swift + word-to-md-swift

### che-pdf-mcp
- `Sources/ChePDFMCP/Server.swift` - MCP 伺服器主體（25 工具）
- `Sources/ChePDFMCP/VisionOCR.swift` - Vision OCR 實作

## Testing Files

測試時可使用任意 `.docx` 文件：
```bash
swift run macdoc word /path/to/test.docx --marker -o /tmp/test_output/
```

## Platform Requirements

- macOS 14+ (macdoc, pdf-to-latex-swift)
- macOS 13+ (ooxml-swift, markdown-swift, marker-swift)
- macOS 14+ / iOS 17+ (surya-swift)
- Swift 5.9+
