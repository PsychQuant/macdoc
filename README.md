# macdoc

原生 macOS 文件處理工具集，使用 Swift 開發，專注於**直接、格式感知（format-aware）的文件轉換**、PDF 工作流與文件自動化，並充分利用 Apple 平台原生能力（PDFKit、Vision.framework）。通用 OCR CLI 已移交 [`PsychQuant/bestOCR`](https://github.com/PsychQuant/bestOCR)；macdoc 仍在特定 PDF 管線內使用 Vision OCR 作為流程元件。

## Why macdoc?

macdoc 並不是要取代 [Pandoc](https://pandoc.org/)。兩者解決的問題層級不同，也採取不同的轉換取捨。

Pandoc 的核心架構是 **reader → Pandoc AST → writer**：各種輸入格式先被解析為共同的中介表示，再由 writer 輸出成目標格式。這讓 Pandoc 能以少量 readers / writers 支援廣泛的 M × N 格式轉換。macdoc 則依照本專案的 [conversion rules](CONVERSIONS.md) 優先採用 **direct source → target converter**；例如 Word → HTML 與 Word → Markdown 可以直接理解 OOXML 的來源語意，而不要求所有格式先正規化成同一個通用 AST。

這不是單純的優劣差異，而是不同 trade-off：Pandoc 強在**格式廣度、跨平台與統一轉換生態**；macdoc 則把範圍集中在**格式感知的直接轉換、macOS 原生文件能力、PDF 工作流與 agent/MCP 文件操作**。

| 面向 | macdoc | Pandoc |
|------|--------|--------|
| 主要目標 | Native macOS document-processing stack | Universal document converter |
| 轉換架構 | 優先 direct source → target | reader → Pandoc AST → writer |
| 格式策略 | 選擇性支援需要深入處理的路徑 | 以共享 AST 支援廣泛 M × N 轉換 |
| PDF / OCR | PDFKit、Vision OCR、PDF → LaTeX 重建工作流 | 不是以 OCR / PDF 文件重建為核心定位 |
| 平台整合 | Swift + Apple frameworks | 跨平台 CLI / library |
| Agent 整合 | Word / PDF / PowerPoint MCP、AI pipeline | CLI、library、Lua / JSON filters 生態 |

兩者也可以組合使用，例如：

```text
PDF ──macdoc──> Markdown ──Pandoc──> EPUB / JATS / Typst / ...
```

Pandoc 架構可參考官方的 [Using the pandoc API](https://pandoc.org/using-the-pandoc-api.html)。

## Claude Code Plugin Marketplace

本 repo 同時是 Claude Code plugin marketplace，提供 macdoc 生態系的 4 個 plugins：

| Plugin | 內容 |
|--------|------|
| `che-word-mcp` | Word (.docx) MCP server（OOXML 讀寫） |
| `che-pdf-mcp` | PDF MCP server（PDFKit 解析、Vision OCR） |
| `che-pptx-mcp` | PowerPoint (.pptx) MCP server（PresentationML 解析與生成） |
| `macdoc` | macdoc CLI 使用指南 skill |

```bash
claude plugin marketplace add PsychQuant/macdoc
claude plugin install che-word-mcp@macdoc   # 或 che-pdf-mcp / che-pptx-mcp / macdoc
```

MCP plugins 的 wrapper 會自動從各 repo 的 GitHub Releases 下載 universal binary，並在安裝前**強制驗證** sha256 與 Developer ID 簽章鏈（Team `6W377FS7BS`）；驗證不過即拒裝。

> 遷移註記：`che-word-mcp` 與 `macdoc` 兩個 plugins 原先發布於 `psychquant-claude-plugins` marketplace，自 2026-07 起以本 marketplace 為準。

## Prerequisites

- **macOS 14+**（Sonoma 或更新）
- **Swift 5.9+**
- **Xcode Command Line Tools**

```bash
xcode-select --install
```

## Build

```bash
git clone https://github.com/PsychQuant/macdoc.git
cd macdoc

# Release build（推薦，效能差 10-50x）
swift build -c release

# Debug build（快速迭代用）
swift build
```

## Install

```bash
# 確保 ~/bin 存在且在 PATH 中
mkdir -p ~/bin

# 複製 binary
cp .build/release/macdoc ~/bin/macdoc

# 驗證
macdoc --version
```

如果 `~/bin` 不在 PATH，在 `~/.zshrc` 加入：

```bash
export PATH="$HOME/bin:$PATH"
```

## Update

```bash
cd /path/to/macdoc
git pull
swift build -c release
cp .build/release/macdoc ~/bin/macdoc
```

## Quick Usage

### 格式轉換（`convert`）

統一入口，textutil-compatible 語法：

```bash
# Word ↔ Markdown
macdoc convert --to md file.docx
macdoc convert --to docx file.md

# Word ↔ HTML
macdoc convert --to html file.docx
macdoc convert --to docx file.html

# HTML ↔ Markdown
macdoc convert --to md file.html
macdoc convert --to html file.md

# PDF → Markdown / Word
macdoc convert --to md file.pdf
macdoc convert --to docx file.pdf

# SRT → HTML（字幕轉網頁，支援 speaker 偵測）
macdoc convert --to html file.srt --css dark --full

# BibLaTeX → APA 7（HTML / Markdown / JSON）
macdoc convert --to html refs.bib --full
macdoc convert --to md refs.bib
macdoc convert --to json refs.bib

# Note → HTML（Notability 筆記互動播放器）
macdoc convert --to html notes.note --full
macdoc convert --to html notes.note --full --css dark
```

常用選項：

| 選項 | 說明 |
|------|------|
| `--output <path>` | 指定輸出路徑 |
| `--stdout` | 輸出到 stdout |
| `--frontmatter` | 含 YAML frontmatter（Word → MD） |
| `--html-extensions` | 保留 `<u>/<sup>/<sub>/<mark>`（→ MD） |
| `--full` | 輸出完整 HTML 文件 |
| `--css dark\|light` | SRT 主題 |
| `--css minimal\|web` | Bib 樣式 |

### BibLaTeX 工具（`bib`）

```bash
# 列出所有 entries
macdoc bib list refs.bib --show-type

# 產生 APA 7 HTML（可篩選 key）
macdoc bib to-html refs.bib -o refs.html --full
macdoc bib to-html refs.bib --key cheng2025 --key yang2024

# 產生 APA 7 Markdown
macdoc bib to-md refs.bib -o refs.md
```

### PDF → LaTeX Pipeline（`pdf`）

將 PDF 教科書轉為可編譯的 LaTeX 原始碼。分兩階段：

#### Phase 1：提取與轉寫

```bash
# 1. 初始化專案
macdoc pdf init --pdf textbook.pdf --output textbook-latex

# 2. 掃描頁面資訊
macdoc pdf segment --project textbook-latex

# 3. 渲染每頁為 PNG
macdoc pdf render --project textbook-latex

# 4. Vision OCR 偵測文字區塊
macdoc pdf blocks --project textbook-latex

# 5. AI 轉寫為 LaTeX（最耗時）
macdoc pdf transcribe-pages --project textbook-latex

# 可選參數：
#   --backend codex|claude|gemini    AI 後端
#   --model <model-name>             指定模型
#   --first-page 50 --last-page 100  只轉部分頁面
#   --pages-per-request 2            每次送幾頁

# 6. 偵測章節切分
macdoc pdf chapters --project textbook-latex

# 7. 組裝成 .tex 檔案
macdoc pdf assemble --project textbook-latex
```

#### Phase 2：修復與編譯

```bash
# 8. 機械式清理（document class、符號、去重）
macdoc pdf normalize --project textbook-latex

# 9. 修復 \begin/\end 配對問題
macdoc pdf fix-envs --project textbook-latex --fix

# 10. 編譯檢查
macdoc pdf compile-check --project textbook-latex

# 11. 自動修復剩餘錯誤（機械清理 + AI agent 迭代）
macdoc pdf consolidate --project textbook-latex
```

#### 其他 PDF 工具

```bash
# 查看專案狀態
macdoc pdf status --project textbook-latex

# 偵測 PDF 來源格式（LaTeX / Word / 掃描件）
macdoc pdf detect-source --project textbook-latex

# 比較原始 PDF 與重製 PDF 的相似度
macdoc pdf compare --project textbook-latex
```

### AI 設定（`config`）

```bash
# 偵測可用的 AI CLI 工具
macdoc config ai detect

# 查看當前設定
macdoc config ai list

# 設定 agent 後端
macdoc config ai set agent claude
macdoc config ai set transcription codex
```

設定檔位置：`~/.config/macdoc/config.json`

## Supported Conversions

| Source → Target | 指令 |
|-----------------|------|
| Word → Markdown | `convert --to md` |
| Word → HTML | `convert --to html` |
| HTML → Markdown | `convert --to md` |
| HTML → Word | `convert --to docx` |
| Markdown → HTML | `convert --to html` |
| Markdown → Word | `convert --to docx` |
| PDF → Markdown | `convert --to md` |
| PDF → Word | `convert --to docx` |
| PDF → LaTeX | `pdf init` → pipeline |
| TeX → Word | `convert --to docx` |
| SRT → HTML | `convert --to html` |
| BibLaTeX → HTML | `convert --to html` |
| BibLaTeX → Markdown | `convert --to md` |
| BibLaTeX → JSON | `convert --to json` |
| Note → HTML | `convert --to html` |

## MCP Servers

macdoc marketplace 提供三個 MCP server，讓 AI 助手直接操作不同文件格式。各 server 的 binary 由 plugin wrapper 從對應 GitHub Releases 下載，不需要在 macdoc repo 內另外編譯：

| Server | 上游 repo | 用途 |
|--------|-----------|------|
| `che-word-mcp` | [`PsychQuant/che-word-mcp`](https://github.com/PsychQuant/che-word-mcp) | Word / OOXML 文件讀寫 |
| `che-pdf-mcp` | [`PsychQuant/che-pdf-mcp`](https://github.com/PsychQuant/che-pdf-mcp) | PDF 解析與 OCR |
| `che-pptx-mcp` | [`PsychQuant/che-pptx-mcp`](https://github.com/PsychQuant/che-pptx-mcp) | PowerPoint / PresentationML 解析與生成 |

安裝範例：

```bash
claude plugin install che-word-mcp@macdoc
claude plugin install che-pdf-mcp@macdoc
claude plugin install che-pptx-mcp@macdoc
```

## License

目前此 repository 未附 `LICENSE` 檔案。GitHub 上的 public visibility 本身不等同於授權重製、修改或散布。
