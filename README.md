# macdoc

> 平台聲明
> - Token 計數／離線 GPT-4o 層：macOS 27.0（arm64）、Apple Swift 6.3.3；狀態為 `verified`，compiled executable 已在禁用網路並隔離 HOME／cache 的環境通過 `hello world` exact-byte acceptance；package suite 另以五組官方 Python `tiktoken` vectors 驗證 bundled `o200k_base`。
> - Anthropic token-count transport 層：macOS 27.0（arm64）、Apple Swift 6.3.3；狀態為 `implemented-not-live-verified`，固定 endpoint、錯誤映射與資料遮蔽只以注入 transport 驗證，沒有呼叫 live Anthropic。
> - Windows／Linux token 計數：macdoc CLI 與 `TokenCounter` package；狀態為 `not-supported`，目前 manifests 僅宣告 macOS 14+，不得由離線演算法外推 runtime 支援。
> - 證據：`swift test --filter TokenCountCommandTests`、`swift test`（`packages/token-counter-swift`），以及 `Tests/MacDocCLITests/TokenCountCommandTests.swift`。

原生 macOS 文件處理工具集，專注於文件格式轉換和 OCR。使用 Swift 開發，充分利用 Apple 平台原生能力（PDFKit、Vision.framework）。

## Claude Code Plugin Marketplace

本 repo 同時是 Claude Code plugin marketplace，提供 macdoc 生態系的 4 個 plugins：

| Plugin | 內容 |
|--------|------|
| `che-word-mcp` | Word (.docx) MCP server（OOXML 讀寫，242 工具） |
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
- **Swift 6.2+**（`swift-tiktoken` 的 package tools requirement）
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

### Token 計數（UTF-8 measurement route）

GPT-4o 使用隨 binary bundled 的 `o200k_base.tiktoken`，先驗證 SHA-256
`446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d`，再於本機計數；
不會下載 vocabulary、連線、寫 tokenizer cache 或寫入 HOME。假設 `sample.txt` 的內容是
`hello world`：

```bash
macdoc convert --to tokens --model gpt-4o sample.txt
```

stdout 的精確 bytes 是一個十進位整數與換行：

```text
2
```

也可寫入檔案；成功時 stdout 保持空白，`tokens.txt` 的內容仍是精確的 `2\n`：

```bash
macdoc convert --to tokens --model gpt-4o --output tokens.txt sample.txt
```

Claude 計數會把**完整、已驗證的輸入文字**送到 Anthropic。每次執行都必須同時提供非空的
`ANTHROPIC_API_KEY` 與明示的 `--allow-network`；API key 只放在 `x-api-key` header：

```bash
export ANTHROPIC_API_KEY='your-key'
macdoc convert --to tokens --model claude-sonnet-4-6 --allow-network sample.txt
```

省略 `--model` 會依固定順序要求 GPT-4o、Claude Sonnet 4.6，因此也需要同一個網路同意與
credential。兩個 provider 都成功後才會一次輸出下列 tab-separated 形狀（數字依檔案與
provider 回應而異）：

```text
Model	Tokens
gpt-4o	1234
claude-sonnet-4-6	1198
```

限制與語意：

- `--model` 僅接受 `gpt-4o`、`claude-sonnet-4-6`，大小寫必須相符。
- 輸入必須是一般檔案、嚴格 UTF-8、最多 1,000,000 bytes；空檔合法，副檔名不參與判斷。
- Anthropic 數值是該 provider 回報的 input-token estimate，可能隨 provider 行為改變；不是本機可重現的離線精確值。
- 任一 provider 失敗時，stdout 不會出現部分表格，既有 `--output` 檔案也不會被改寫。

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
| `--model gpt-4o\|claude-sonnet-4-6` | token 計數模型（只適用 `--to tokens`） |
| `--allow-network` | 每次允許把完整輸入送到 Anthropic（只適用含 Claude 的 token 計數） |

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
| UTF-8 text → Token count | `convert --to tokens` |

## MCP Servers

macdoc 附帶兩個 MCP server，讓 AI 助手直接操作文件：

| Server | Binary | 工具數 | 用途 |
|--------|--------|--------|------|
| che-word-mcp | `mcp/che-word-mcp/.build/release/CheWordMCP` | 145 | Word 文件讀寫 |
| che-pdf-mcp | `mcp/che-pdf-mcp/.build/release/ChePDFMCP` | 25 | PDF 解析與 OCR |

Build MCP servers：

```bash
cd mcp/che-word-mcp && swift build -c release
cd mcp/che-pdf-mcp && swift build -c release
```

## License

Private repository. All rights reserved.
