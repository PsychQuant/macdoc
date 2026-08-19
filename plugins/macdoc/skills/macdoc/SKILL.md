---
name: macdoc
description: |
  macOS 原生文件處理 CLI 工具的使用指南。
  當需要做格式轉換（SRT→HTML、MD→HTML、DOCX→MD）、
  或 SRT 逐字稿處理時使用。文字辨識（OCR）已移交 bestOCR（macdoc#145），
  提到 OCR 時請改用 bestocr 相關 skill。
  觸發詞：「macdoc」「轉換格式」「逐字稿轉HTML」
---

# macdoc — macOS 原生文件處理 CLI

安裝位置：`~/bin/macdoc` — **plugin 自動安裝**（session-start hook 下載 signed release 並驗證 sha256 + Developer ID；arm64。Intel 從原始碼建置）
原始碼：https://github.com/PsychQuant/macdoc

## 子命令總覽

| 子命令 | 用途 | 常用場景 |
|--------|------|---------|
| `convert` | 格式轉換 | SRT→HTML、MD→HTML、DOCX→MD |
| `ocr` | （已移除 #145）| 文字辨識改用 bestocr |
| `config` | 設定管理 | AI CLI 工具、OCR host/model 預設值 |
| `pdf` | PDF→LaTeX | 學術 PDF 處理（較少用） |
| `bib` | BibLaTeX→APA | 參考文獻格式轉換 |
| `word` | docx ⇄ `.mdocx.swift` 腳本 | 把文件變成可重播的重建腳本、再放回 docx |

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

## word — docx ⇄ `.mdocx.swift` 腳本

兩個子命令構成一個封閉迴路：`reverse` 把 docx 變成重建腳本，`render` 把腳本放回 docx。

```bash
# docx → 腳本
macdoc word reverse form.docx --to-mdocx form.mdocx.swift [--coverage] [--force]

# 腳本 → docx（--verify-against 才會驗證，預設不驗）
macdoc word render form.mdocx.swift --to-docx rebuilt.docx [--verify-against form.docx] [--force]
```

**輸出檔已存在時預設拒絕**，要 `--force`。**驗證失敗什麼都不寫出**——輸出路徑保持原狀，也不會印「已寫入」（重建結果先落在同目錄的暫存路徑，驗過才搬進位）。這兩個保證都由 CLI 與 MCP 共用的入口提供，兩面行為一致。

| 選項 | 屬於 | 說明 |
|------|------|------|
| `--coverage` | reverse | 印 per-part 的 DSL/raw 覆蓋率報告 |
| `--slot <name>=<paraId>` | reverse | 指定段落成為腳本的具名參數（strict，不推斷）|
| `--paragraphs-only` | reverse | 退回舊的段落反向（**無** byte-equal 保證）|
| `--from-oplog` | reverse | 強制用 oplog sidecar |
| `--verify-against <docx>` | render | 對照參考檔做 byte-equal 驗證；**不給就不驗** |
| `--force` | 兩者 | 覆寫既有輸出（不給就拒絕，且不動既有檔案）|

### 這條迴路保證什麼、不保證什麼

**保證**：byte-equal 重播。`--verify-against` 通過就代表重建出的每個 XML part 與參考檔逐位元組相同。

**不保證**：產物可讀。腳本有兩條 channel——typed DSL（可讀）與 raw（把整個 XML part 逐字塞進一行 `// @op`）。**DSL 升級是 per-part 全有全無**：文件裡只要含一個表格，整個 `word/document.xml` 就整份掉到 raw channel。

實測 `REC-O-01` 這類真實官方表單：

```
--- Aggregate: 0.0% DSL (0 / 190479 XML bytes across 16 parts) ---
```

產出是 24 行 / 212 KB，其中 `word/document.xml` 那一行就佔約 118 KB。**它能完美重播，但不能讀、不能手改、也無法有意義地做版控 diff**（改一個字會讓整條 118 KB 的行重新 escape）。

所以**先跑 `--coverage` 再決定期待值**——不要因為文件看起來簡單就假設會拿到可讀的 Swift。

> 完整工作流（含 slot 填寫與 MCP 對應工具）見 [`swiftify`](../swiftify/SKILL.md) skill；本節只是命令參考。

---

## ocr —（已移除，改用 bestOCR）

`macdoc ocr` 已於 2026-08-07 移除（macdoc#145）：通用文字辨識的所有權歸
bestOCR（PsychQuant/bestOCR）單點——引擎選擇、版本紀錄、evidence 慣例都在
那邊維護。現在執行 `macdoc ocr` 會印遷移訊息並以 exit 2 結束。

```bash
bestocr ocr <input>            # 單檔 OCR
bestocr recommend              # 不確定用哪個引擎時
bestocr consensus <input>      # 高價值文件的多引擎互核
```

pdf-to-latex 管線內部的頁級 OCR 不受影響（那是管線零件，不是通用辨識入口）。

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
| 手寫筆記 → TikZ 圖 | `bestocr ocr` → 辨識內容 → 寫 TikZ → `xelatex` 編譯 |
| SRT → handout 網頁 | `macdoc convert --to html` → `inject-search.py` |
| PDF 筆記 → PNG | `pdftoppm -png -r 200`（不是 macdoc，是 poppler） |
| 學生作業 .docx → 閱讀 | 用 che-word-mcp 的 `get_document_text`（不需要 macdoc） |

---

## 版本紀錄

- **1.1.0**：新增 `config ocr` 子命令組,支援具名 host profile(`--host kyle` 等),預設 host/model 可存 config
- **1.0.0**：初版
