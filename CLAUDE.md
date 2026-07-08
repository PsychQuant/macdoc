<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Repository Overview

**macdoc** 是一個原生 macOS 文件處理工具集，專注於文件格式解析、轉換和 OCR 功能。整個專案使用 Swift 開發，充分利用 Apple 平台的原生能力。

本 repo 同時是 **Claude Code plugin marketplace**（`.claude-plugin/marketplace.json` + `plugins/`，2026-07 起，#112）：發布 `che-word-mcp`、`che-pdf-mcp`、`che-pptx-mcp`、`macdoc` 四個 plugins，使用者以 `claude plugin marketplace add PsychQuant/macdoc` 安裝。注意 `plugins/`（plugin shells，正常入版控）與 `packages/`（gitignored 本地套件）的差異；MCP shells 的 wrapper 從各 binary repo 的 GitHub Releases 自動下載 binary，安裝前強制驗證 sha256 + Developer ID 簽章鏈（requirement-based codesign，Team `6W377FS7BS`）。發布新版時同步 bump `plugins/<name>/.claude-plugin/plugin.json` 與 `.claude-plugin/marketplace.json` 兩處版本；**binary-backed plugin 的 `binary_version` 只在 binary repo 發新 release 後才改**（shell-only 變更 bump `version` 即可，#116 解耦契約）。

## Project Structure

```
macdoc/                        # Monorepo 根目錄（同時也是 CLI 專案）
├── Package.swift              # CLI 的 Swift Package 定義
├── Sources/
│   └── MacDocCLI/             # CLI 入口點
│       ├── MacDoc.swift       # 主命令（Convert + PDF + Bib + Config + OCR + Docx + Word 子命令群）
│       ├── MacDoc+Convert.swift # Convert 統一轉換入口（16 路由，textutil-compatible）
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
│   └── pdf-to-latex-swift/    # PDF → LaTeX pipeline（簡化: GLM-OCR + Phase 2）
├── mcp/                       # MCP 工具（各自獨立 git repo，.gitignore 忽略）
│   ├── che-word-mcp/          # Layer 4: Word 文件處理 MCP（145 工具）
│   └── che-pdf-mcp/           # Layer 4: PDF 文件處理 MCP（25 工具）
├── cli/                       # CLI 實驗專案（預設 .gitignore；FastOCR 為 submodule）
│   └── FastOCR/               # GLM-OCR PDF→Markdown CLI + 實驗 harness（submodule）
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
macdoc CLI ──→ word-builder-swift ──→ ooxml-swift (fluent Swift API for .docx, 1:1 mirror of docx.js)

che-pdf-mcp
└──→ Vision.framework / surya-swift
```

詳見 [`docs/modular-architecture.md`](docs/modular-architecture.md)。

## Development Commands

### Build, Install & Run

```bash
# 建構主專案（debug，快速迭代）
swift build

# 建構 release（推薦，效能差 10-50x）
swift build -c release

# 安裝到 PATH（~/bin 需在 $PATH 中）
cp .build/release/macdoc ~/bin/macdoc

# 驗證
macdoc --version
```

```bash
# 執行 CLI — 統一轉換入口（textutil-compatible，16 路由）
swift run macdoc convert --to md file.docx          # Word → Markdown
swift run macdoc convert --to md file.docx --frontmatter  # Word → Markdown（含 YAML frontmatter）
swift run macdoc convert --to html file.docx         # Word → HTML
swift run macdoc convert --to marker file.docx       # Word → Marker 目錄（.md + _meta.json + images/）
swift run macdoc convert --to html file.md [--full]  # Markdown → HTML
swift run macdoc convert --to html file.md --html-extensions  # Markdown → HTML（啟用擴充語法）
swift run macdoc convert --to docx file.md           # Markdown → Word
swift run macdoc convert --to md file.html           # HTML → Markdown
swift run macdoc convert --to docx file.html         # HTML → Word
swift run macdoc convert --to pdf file.html          # HTML → PDF（需要 playwright CLI）
swift run macdoc convert --to html file.srt [--full] [--css dark|light]  # SRT → HTML（支援 speaker 偵測）
swift run macdoc convert --to md file.pdf            # PDF → Markdown
swift run macdoc convert --to docx file.pdf          # PDF → Word
swift run macdoc convert --to docx file.tex          # TeX → Word
swift run macdoc convert --to html file.bib [--full] [--css minimal|web]  # Bib → HTML
swift run macdoc convert --to md file.bib            # Bib → Markdown
swift run macdoc convert --to json file.bib          # Bib → JSON

# 執行 CLI — PDF pipeline（OCR + Phase 2 consolidation）
swift run macdoc pdf ocr --project /path/to/project              # 整頁 GLM-OCR（預設 local MLX）
swift run macdoc pdf ocr --project /path/to/project --mode ollama # 透過 Ollama HTTP API
swift run macdoc pdf normalize --project /path/to/project
swift run macdoc pdf fix-envs --project /path/to/project [--fix]
swift run macdoc pdf compile-check --project /path/to/project
swift run macdoc pdf consolidate --project /path/to/project [--dry-run] [--agent codex|claude|gemini]
# （deprecated）舊的 block-level 轉寫命令，已被 pdf ocr 取代：
# swift run macdoc pdf transcribe --project /path/to/project --backend codex|claude|gemini
# swift run macdoc pdf transcribe-pages --project /path/to/project

# 執行 CLI — Bib（APA 7 格式轉換）
swift run macdoc bib list paper.bib [--show-type]
swift run macdoc bib to-html paper.bib -o refs.html [--full] [--css minimal|web]
swift run macdoc bib to-md paper.bib -o refs.md [--heading]
swift run macdoc bib to-html paper.bib --key cheng2025 --key yang2024

# AI 設定管理
swift run macdoc config ai detect
swift run macdoc config ai list
swift run macdoc config ai set agent claude

# OCR 設定管理（v1.1+：具名 host profile）
swift run macdoc config ocr list
swift run macdoc config ocr add-host kyle localhost:11435  # 例：SSH tunnel 到遠端 Ollama
swift run macdoc config ocr add-host local localhost:11434
swift run macdoc config ocr set-default kyle              # 之後 ocr 命令不傳 --host 就用這個
swift run macdoc config ocr set-model glm-ocr
# 之後 `macdoc ocr file.pdf` 自動用 kyle profile，--host 也接受 profile 名

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
- **Phase 1**：PDF 掃描、頁面渲染、GLM-OCR 整頁轉錄、章節偵測、TeX 組裝（舊的 block-level AI 轉寫已 deprecated）
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
- **Convert**：統一轉換入口（`macdoc convert --to <format> <file>`），textutil-compatible 語法，16 路由
- **PDF**：簡化 pipeline（init → render → ocr → chapters → assemble）+ Phase 2（normalize → fix-envs → compile-check → consolidate）。舊的 block-level transcribe 已 deprecated，改用整頁 GLM-OCR。
- **Bib**：BibLaTeX → APA 7 HTML/Markdown（to-html, to-md, list，支援 --key 過濾）
- **Config**：AI 後端設定管理
- **依賴**：word-to-md-swift + marker-word-converter-swift + word-to-html-swift + html-to-word-swift + md-to-word-swift + pdf-to-md-swift + pdf-to-docx-swift + marker-swift + pdf-to-latex-swift + html-to-md-swift + md-to-html-swift + srt-to-html-swift + bib-apa-to-html-swift + bib-apa-to-json-swift + bib-apa-to-md-swift + ArgumentParser

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

主 repo 以兩種方式追蹤外部 repo：

- **Submodule**（`.gitmodules`）：`mcp/` 下三個 MCP server + `cli/FastOCR`。Clone 主 repo 時加 `--recurse-submodules` 會自動拉齊，或事後 `git submodule update --init --recursive`
- **Gitignore 忽略**（各自獨立管理）：`packages/` 下的 Swift 套件、`reference/`。重建環境時在對應目錄 `git clone` 即可

| 目錄 | Git Remote | 說明 |
|------|-----------|------|
| `.` (root) | https://github.com/PsychQuant/macdoc.git | 主專案 CLI |
| `packages/common-converter-swift` | https://github.com/PsychQuant/doc-converter-swift.git | 轉換器協議（remote 名 doc-converter-swift） |
| `packages/word-to-md-swift` | https://github.com/PsychQuant/word-to-md-swift.git | Word → MD 轉換 |
| `packages/word-builder-swift` | https://github.com/PsychQuant/word-builder-swift.git | Lens-model authoring surface for .docx (v1.0.0+) — wraps OOXMLSwift.WordDocument |
| `packages/docx-workflow-swift` | (local only — not yet published) | Layer 3 manifest-driven docx-edit library on top of word-builder-swift v1.0.0 |
| `packages/ooxml-swift` | https://github.com/PsychQuant/ooxml-swift.git | OOXML 解析 |
| `packages/markdown-swift` | https://github.com/PsychQuant/markdown-swift.git | Markdown 生成 |
| `packages/marker-swift` | https://github.com/PsychQuant/marker-swift.git | 圖片分類 |
| `packages/surya-swift` | (local only) | OCR 文字辨識 |
| `packages/pptx-swift` | https://github.com/PsychQuant/pptx-swift.git | PresentationML (.pptx) 解析與生成（v0.1.0+） |
| `packages/pdf-to-latex-swift` | https://github.com/PsychQuant/pdf-to-latex-swift.git | PDF → LaTeX pipeline (consumed via remote url dep since #79) |
| `packages/ocr-swift` | https://github.com/PsychQuant/ocr-swift.git | OCR pipeline (MLX + Ollama backends, PDFKit extractor; consumed via remote url dep since #79) |
| `mcp/che-word-mcp` | https://github.com/PsychQuant/che-word-mcp.git | Word MCP（submodule） |
| `mcp/che-pdf-mcp` | https://github.com/PsychQuant/che-pdf-mcp.git | PDF MCP（submodule） |
| `mcp/che-pptx-mcp` | https://github.com/PsychQuant/che-pptx-mcp.git | PPTX MCP（submodule） |
| `cli/FastOCR` | https://github.com/PsychQuant/FastOCR.git | GLM-OCR PDF→Markdown CLI + 實驗 harness（submodule） |
| `reference/*` | 見 [`reference/README.md`](reference/README.md) | 外部參考 repo（docx-js、pandoc、mlx-swift-lm、swift-argument-parser）— clone-on-demand，只有 README 進版控 |

## Key Files

### macdoc
- `Sources/MacDocCLI/MacDoc.swift` - CLI 入口點（Convert + PDF + Bib + Config + OCR + Docx + Word 子命令群）
- `Sources/MacDocCLI/MacDoc+Docx.swift` - `macdoc docx ...` 子命令（apply / plan / verify / diff —— manifest-driven .docx edit workflows，per openspec change `macdoc-docx-workflow-cli`，library 在 `packages/docx-workflow-swift`）
- `Sources/MacDocCLI/MacDoc+Word.swift` - `macdoc word reverse <docx> --to-mdocx <out> [--from-oplog] [--force] [--coverage] [--paragraphs-only] [--slot name=paraId]…`（docx → `.mdocx.swift` 腳本反向轉換；transcoder 本體在 ooxml-swift 的 `ScriptExporter`/`ScriptImporter`）。**預設 full-fidelity**（format-alignment-engine Phase C #130）：全 parts 騎在腳本上（raw channel byte-equal floor）+ typed DSL 升級（`ReverseExtractor` 的 trial-rebuild byte-equal gate 通過才升級，涵蓋 run rPr / paragraph pPr / sections / canonical tables 五層）；執行腳本重建出 Stage B byte-equal 的 docx。`--paragraphs-only` 退回舊的段落 text+styleId 反向（無 byte-equal 保證）；有 oplog sidecar 時仍優先匯出現況 log。`--coverage` 印出 dual-track 覆蓋率報告：每個 part 的 DSL/raw split + aggregate %（DSL 份額 = byte-equal 證明過的 typed 重建；raw = 逐字搬運；基線數字見 [docs/format-alignment-baselines.md](docs/format-alignment-baselines.md)）。`--slot name=paraId`（可重複，Phase D）：指定段落的文字成為腳本的 Swift 函式參數（strict mode 明確指定、不推斷；無 slot 時腳本逐字重建 byte-equal）
- `Sources/MacDocCLI/MacDoc+Convert.swift` - Convert 統一轉換入口（16 路由，textutil-compatible）
- `Sources/MacDocCLI/MacDoc+PDF.swift` - PDF 子命令（簡化 pipeline: ocr + Phase 2 consolidation）
- `Sources/MacDocCLI/MacDoc+OCR.swift` - OCR 子命令（top-level `macdoc ocr`，單檔 GLM-OCR）
- `Sources/MacDocCLI/MacDoc+Bib.swift` - Bib 子命令（.bib → APA 7 HTML/Markdown，支援 --key 過濾）
- `Sources/MacDocCLI/MacDoc+Config.swift` - Config 子命令（AI 設定管理）

### pdf-to-latex-swift
- `Sources/PDFToLaTeXCore/AIConfig.swift` - AI CLI 工具設定
- `Sources/PDFToLaTeXCore/LaTeXNormalizer.swift` - 機械式 LaTeX 清理
- `Sources/PDFToLaTeXCore/LaTeXEnvChecker.swift` - 環境配對檢查
- `Sources/PDFToLaTeXCore/TexCompileChecker.swift` - 編譯錯誤解析
- `Sources/PDFToLaTeXCore/Consolidator.swift` - consolidation orchestrator

### srt-to-html-swift
- `Sources/SRTToHTML/SRTConverter.swift` - SRT → HTML 轉換器
- **Speaker 偵測**：自動辨識兩種格式，產出 `<span class="speaker">` badge + `data-speaker="N"` 屬性
  - 冒號格式：`Speaker 1: text`（Otter.ai、Google Meet、部分 Plaud）
  - 方括號格式：`[Speaker 1] text`（Whisper、Assembly AI、部分 Plaud）
- **CSS 主題**：`--css dark`（深色卡片）或 `--css light`（淺色列表，適合列印）
- **輸出模式**：`--full` 輸出完整 HTML 文件，否則只輸出 `<main>` fragment

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
swift run macdoc convert --to md /path/to/test.docx
swift run macdoc convert --to marker /path/to/test.docx -o /tmp/test_output/
```

### `.note` smoke tests (MacDocCLITests)

`Tests/MacDocCLITests/NotePDFConvertTests.swift` 和 `NoteHTMLConvertTests.swift` 跑 `.note` → pdf/html 的端到端 smoke coverage（#81）。兩個 test 透過 `CLITestHelper.noteFixture()` 找 `test-files/*.note` 樣本，找不到就 `XCTSkip` — CI / clean-clone 不會 fail，只會跳過。

若要在本機實際跑 coverage，把任一 `.note` 檔放到 `test-files/`（該目錄被 `.gitignore` 忽略，檔案不會入版控）。committable 小 fixture 是 follow-up（見 #79 討論 serial）。

## Platform Requirements

- macOS 14+ (macdoc, pdf-to-latex-swift)
- macOS 13+ (ooxml-swift, markdown-swift, marker-swift)
- macOS 14+ / iOS 17+ (surya-swift)
- Swift 5.9+
