---
name: macdoc
description: |
  macOS 原生文件處理 CLI 工具的使用指南。
  當需要做格式轉換（SRT→HTML、MD→HTML、DOCX→MD）、
  VLM OCR（PDF/圖片→文字）、或 SRT 逐字稿處理時使用。
  觸發詞：「macdoc」「轉換格式」「OCR」「逐字稿轉HTML」
  「手寫筆記辨識」「PDF轉文字」
---

# macdoc — macOS 原生文件處理 CLI

安裝位置：`~/bin/macdoc`（或 `/usr/local/bin/macdoc`）
原始碼：`/Users/che/Developer/macdoc`

## 子命令總覽

| 子命令 | 用途 | 常用場景 |
|--------|------|---------|
| `convert` | 格式轉換 | SRT→HTML、MD→HTML、DOCX→MD |
| `ocr` | VLM OCR | PDF/圖片→文字（手寫筆記辨識） |
| `config` | 設定管理 | AI CLI 工具、OCR host/model 預設值 |
| `pdf` | PDF→LaTeX | 學術 PDF 處理（較少用） |
| `bib` | BibLaTeX→APA | 參考文獻格式轉換 |

---

## convert — 格式轉換

```bash
macdoc convert --to <format> [options] <input>
```

### 支援格式

| --to | 說明 | 範例 | Backend |
|------|------|------|---------|
| `html` | 轉 HTML | SRT→逐字稿網頁、MD→講義網頁 | swift-markdown |
| `md` | 轉 Markdown | DOCX→MD | ooxml-swift |
| `docx` | 轉 Word | MD→DOCX | word-builder-swift |
| `pdf` | 轉 PDF — MD 來源 | MD→PDF（純文字） | textutil |
| `pdf` | 轉 PDF — HTML 來源 | HTML（含 CSS / `@page` / page-break / grid）→ PDF，**完整保留排版** | **playwright Chromium** |
| `json` | 轉 JSON | SRT→結構化 JSON | bib-apa-to-json-swift |

**HTML→PDF 路徑前置需求**:

```bash
pip install playwright && playwright install chromium
```

完整 CSS / `@page` rule / `page-break-*` / CSS Grid 都正常保留 — **不要**為了避開「textutil 洗 CSS」而繞道用 `chrome --headless` 或 `wkhtmltopdf`,macdoc 已內建 playwright 路徑（#69 實作）。

### 常用選項

| 選項 | 說明 |
|------|------|
| `--output <path>` | 輸出檔案路徑 |
| `--full` | 輸出完整 HTML 文件（含 `<head>`），不只是 fragment |
| `--css light` | SRT 轉 HTML 時用淺色主題 |
| `--css dark` | SRT 轉 HTML 時用深色主題 |
| `--hard-breaks` | 軟換行視為硬換行 |
| `--frontmatter` | 包含 YAML frontmatter |
| `--html-extensions` | MD 中保留 `<u>/<sup>/<sub>/<mark>` |

### 常用工作流

#### HTML（含完整 CSS / 排版）→ PDF

```bash
# HTML（含 @page / page-break / grid / 自訂 fonts）→ PDF，CSS 完整保留
macdoc convert --to pdf styled-quote.html --output quote.pdf
```

前置需求:`pip install playwright && playwright install chromium`。

**不要繞道**用 `chrome --headless` / `wkhtmltopdf` — macdoc 已內建 playwright 路徑（#69 實作）。

#### SRT → 可搜尋的逐字稿 HTML

```bash
# 1. 轉換
macdoc convert --to html --css light --full --output transcript.html input.srt

# 2. 注入搜尋和說話者篩選功能（需要 inject-search.py）
python3 inject-search.py transcript.html --speakers "鄭老師:鄭老師,學生名:學生名"
```

`inject-search.py` 位於每個 handout 目錄下。

#### MD → 講義 HTML

```bash
macdoc convert --to html --full --output lecture.html notes.md
```

產出的是裸 HTML，需要手動替換 `<head>` 加入 CSS 連結和 lecture-header。

#### DOCX → Markdown

```bash
macdoc convert --to md --output output.md input.docx
```

---

## ocr — VLM OCR

```bash
macdoc ocr <input> [options]
```

用 Vision Language Model 做 OCR，支援手寫筆記、印刷文件、截圖。

### Backend 選擇

| Backend | 選項 | 說明 |
|---------|------|------|
| **Ollama**（預設） | `--backend ollama` | 透過 Ollama HTTP API，需要先啟動 Ollama |
| **MLX**（本地） | `--backend mlx` | 用 mlx-swift-lm 本地推理（⚠️ 目前有 upstream bug） |

### Ollama host 設定（v1.1+）

**推薦流程**：用 `config ocr` 設定好 host profile，之後就不用每次傳 `--host`。

```bash
# 一次性設定（本機或遠端 Kyle）
macdoc config ocr add-host kyle localhost:11435   # 先建 SSH tunnel 到 kyle
macdoc config ocr add-host local localhost:11434  # 本機 Ollama
macdoc config ocr set-default kyle                # 設為預設

# 之後直接 OCR，不用 --host
macdoc ocr handwritten.pdf
```

**`--host` 解析規則**：先當 profile 名查 config，找不到才當原始地址。

```bash
macdoc ocr file.pdf                       # 用 default profile
macdoc ocr file.pdf --host local          # 切換到 local profile
macdoc ocr file.pdf --host 192.168.1.50:11434  # 不是 profile,當原始地址
```

### SSH tunnel 到 Kyle

Kyle 的 Mac Studio（M4 Max/128GB）上有 Ollama + glm-ocr：

```bash
# 建 SSH tunnel（Kyle's Ollama 預設只聽 localhost）
ssh -fN -L 11435:localhost:11434 kyle

# 確認連線
curl -s http://localhost:11435/api/tags | python3 -m json.tool

# OCR（如果已設 default=kyle）
macdoc ocr notes.pdf --output notes.md

# 長時間 OCR 記得用 caffeinate 防電腦睡眠（SSH tunnel 會斷）
caffeinate -i -- macdoc ocr large.pdf --output large.md
```

### 可用模型

| 模型 | 用途 | --model 值 |
|------|------|-----------|
| **glm-ocr**（預設） | 中文手寫/印刷 OCR | `glm-ocr` |
| qwen3-vl | 多語言 VLM | `qwen3-vl` |
| minicpm-v | 輕量 VLM | `minicpm-v` |

### 常用範例

```bash
# 手寫筆記 PDF（指定頁碼）
macdoc ocr notes.pdf --pages 1-3 --output notes.md

# 大型 PDF 分段 OCR(避免長時間 tunnel 斷線)
macdoc ocr big.pdf --pages 1-60  --output part1.md
macdoc ocr big.pdf --pages 61-120 --output part2.md
cat part1.md part2.md > full.md

# 單張圖片
macdoc ocr screenshot.png

# 指定模型(覆寫 config default)
macdoc ocr document.pdf --model qwen3-vl
```

### 已知問題

- **MLX backend crash**:mlx-swift-lm 有 upstream bug(ml-explore/mlx-swift-lm#191),所有 VLM 模型都會 crash。暫時只能用 Ollama。
- **SSH tunnel 長時間會斷**:連線超過 2-3 小時會 timeout。解法是分段 OCR(`--pages`)或用 `caffeinate -i`。
- **大頁面**:超過 8000px 的頁面會被自動縮小。

### 批次與並行(77 PDF 轉學考實戰累積)

當要 OCR 數十張 PDF 或數百頁時,單檔順序跑會花太久。下面是實戰整理出來的 pattern。

#### 為什麼先拆 PNG 再 OCR

直接 `macdoc ocr file.pdf` 在某些 PDF 上會漏頁首 — 模型內部的 PDF→image 路徑可能用低解析度。改成預先用 `pdftoppm` 拆 PNG 再逐頁 OCR,單頁可控、可平行、漏頁可重跑。

```bash
# Step 1: 拆 PNG (200 DPI 對手寫/印刷都夠)
mkdir -p out
pdftoppm -r 200 -png file.pdf out/page

# Step 2: 逐 PNG OCR (見下面 xargs -P pattern)

# Step 3: 合併
cat out/page-*.md > full.md
```

#### Ollama 並發環境變數

跑遠端 Ollama(SSH tunnel 連 Kyle 等)時這幾個變數顯著影響吞吐:

| 變數 | 建議 | 說明 |
|------|------|------|
| `OLLAMA_NUM_PARALLEL` | 4~8 | 同 model 並發請求數;太高會 OOM |
| `OLLAMA_MAX_LOADED_MODELS` | 1 | 單 model 任務維持 1,避免 thrash |
| `OLLAMA_FLASH_ATTENTION` | 1 | Apple Silicon Metal 後端免費加速 |

設定方式:在 Ollama server 端的 `~/Library/LaunchAgents/com.ollama.server.plist` 加 `EnvironmentVariables`,或啟動前 `export`,然後 `ollama serve`。

#### `xargs -P` 並行 pattern

```bash
# N=4 並行 (對應 OLLAMA_NUM_PARALLEL=4)
find out -name "page-*.png" | xargs -P 4 -I{} \
  macdoc ocr {} --output "{}.md" --host kyle --model glm-ocr

# 失敗重試 (找出無 .md 的 png 重跑)
find out -name "page-*.png" | while read png; do
  [ -f "${png}.md" ] || echo "$png"
done | xargs -P 2 -I{} macdoc ocr {} --output "{}.md" --host kyle
```

#### SSH tunnel 維持

長時間批次 OCR(>2 小時)tunnel 會斷。三種策略:

```bash
# (a) 簡易 — 跑前重建 tunnel,搭配 caffeinate 防 mac sleep
ssh -fN -L 11435:localhost:11434 kyle
caffeinate -i -- xargs -P 4 ... < pages.txt

# (b) autossh — 自動重連
brew install autossh
autossh -fN -M 0 -L 11435:localhost:11434 kyle

# (c) Health check loop — 中途斷 tunnel 自動重建
while true; do
  curl -s --max-time 5 http://localhost:11435/api/tags >/dev/null \
    || ssh -fN -L 11435:localhost:11434 kyle
  sleep 60
done &
```

實戰建議:走 (b) autossh + `caffeinate -i`,踩坑成本最低。

#### 與 CLI `--parallel` 的整合(roadmap)

`PsychQuant/macdoc#73` 追蹤把 `--parallel N` 整合進 macdoc CLI(內建 `xargs -P` 邏輯 + 失敗重試 + tunnel health check)。CLI 落地後上面那段 pattern 會被取代成:

```bash
macdoc ocr-batch out/*.png --parallel 4 --host kyle  # roadmap, 尚未實作
```

在那之前,沿用 `xargs -P` 即可。另一個正在被討論的方向是新建 `batch-ocr` plugin 把 PDF→PNG→OCR→merge 整個 pipeline 包成 single command,見 PsychQuant/psychquant-claude-plugins#6。

---

## config — 設定管理

設定檔存在 `~/.config/macdoc/config.json`。

### config ai — AI CLI 工具設定

```bash
macdoc config ai detect                  # 偵測本機已安裝的 codex/claude/gemini
macdoc config ai list                    # 顯示目前設定
macdoc config ai set transcription codex # 設定 one-shot 轉寫預設後端
macdoc config ai set agent claude        # 設定 agentic 後端
```

### config ocr — OCR host/model 設定（v1.1+）

| 子命令 | 用途 |
|--------|------|
| `list` | 顯示目前 OCR 設定（含 profile 列表） |
| `add-host <name> <addr>` | 新增/更新 host profile |
| `remove-host <name>` | 移除 profile |
| `set-default <name>` | 設定預設 host |
| `set-model <model>` | 設定預設模型（如 glm-ocr） |
| `set-backend <ollama\|mlx>` | 設定預設後端 |

```bash
# 完整範例：設定 kyle 遠端 + local 兩個 profile
ssh -fN -L 11435:localhost:11434 kyle  # 建 tunnel
macdoc config ocr add-host kyle localhost:11435
macdoc config ocr add-host local localhost:11434
macdoc config ocr set-default kyle
macdoc config ocr set-model glm-ocr

# 查看
macdoc config ocr list
# === OCR 設定 ===
# backend: ollama
# model:   glm-ocr
# default host: kyle → localhost:11435
#
# === Host Profiles ===
#   kyle → localhost:11435 ★
#   local → localhost:11434
```

---

## 與其他工具的搭配

| 場景 | 工具組合 |
|------|---------|
| 手寫筆記 → TikZ 圖 | `macdoc ocr` → 辨識內容 → 寫 TikZ → `xelatex` 編譯 |
| SRT → handout 網頁 | `macdoc convert --to html` → `inject-search.py` |
| PDF 筆記 → PNG | `pdftoppm -png -r 200`（不是 macdoc，是 poppler） |
| 學生作業 .docx → 閱讀 | 用 che-word-mcp 的 `get_document_text`（不需要 macdoc） |

---

## 版本紀錄

- **1.1.0**：新增 `config ocr` 子命令組,支援具名 host profile(`--host kyle` 等),預設 host/model 可存 config
- **1.0.0**：初版
