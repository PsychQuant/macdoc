# Ensemble OCR Pipeline — Design Document

## Problem

Single-pass OCR（無論 Vision、Surya 或 GLM-OCR）在學術論文上達到約 98% 準確率，但剩餘 2% 的錯誤集中在數學公式符號（`ξ` vs `ε`、下標 `n` vs `u`）、重音字母（Cramér）、和模糊區域。這些錯誤在學術文獻中代價最高。

## Solution

Ensemble OCR：多來源比對，自動 diff 找出歧異，僅將有歧異的片段交給 Claude 看原圖判斷，最終由 Claude 排版成完整 LaTeX。

來源數量取決於 PDF 類型：
- **向量 PDF**（LaTeX/Word 產生）：2 個來源（PDFKit + GLM-OCR）
- **掃描 PDF**（影印/拍照）：1 個來源（GLM-OCR only）

透過 `macdoc pdf detect-source` 自動判斷走哪條路。不再使用第二個 VLM（Qwen2.5-VL），GLM-OCR 單獨表現已足夠好，ensemble 的價值在於 PDFKit + GLM-OCR 的互補，而非兩個 VLM 的投票。

## Architecture

### 向量 PDF（2 來源）

```
PDF (vector)
 │
 ├─ detect-source → LaTeX / Word / Typst（已有）
 │
 ├─ Source 1: PDFKit 文字提取 ──→ Result P（免費、即時）
 │    (PDFPage.string / selectionsByLine)
 │
 ├─ render pages (PageRenderer, 已有)
 │
 ├─ Source 2: GLM-OCR ──→ Result G
 │
 ├─ 兩方 diff ──→ conflicts.md + clean.txt
 │    ├─ P = G → 高信度，直接用
 │    ├─ P ≠ G（公式區段）→ 採用 GLM-OCR 版本（PDFKit glyph 亂碼）
 │    └─ P ≠ G（其他）→ 交給 Claude
 │
 └─ Claude (skill 觸發)
      ├─ 消歧異：只看 conflicts + 原圖裁切
      └─ 排版：clean.txt → 完整 .tex
```

### 掃描 PDF（1 來源）

```
PDF (scanned)
 │
 ├─ detect-source → scanned（已有）
 │
 ├─ render pages (PageRenderer, 已有)
 │
 ├─ Source 1: GLM-OCR ──→ Result G
 │
 └─ Claude (skill 觸發)
      ├─ 直接使用 GLM-OCR 結果
      └─ 排版：Result G → 完整 .tex
```

### 來源特性比較

| Source | 普通文字 | 數學公式 | 成本 | 適用 |
|--------|---------|---------|------|------|
| PDFKit | 極強（嵌入文字直接讀） | 弱（glyph 亂碼） | 零 | 僅向量 PDF |
| GLM-OCR (VLM) | 強 | 強 | MLX 推論 | 全部 |

## Integration into macdoc

### Current State

macdoc 已有的 OCR 相關能力：

| Engine | Package | 執行方式 | 特性 |
|--------|---------|---------|------|
| Vision | `pdf-to-latex-swift` (BlockSegmenter) | 本機 native | 快，macOS 內建，數學弱 |
| Surya | `surya-swift` | 本機 CoreML | Layout analysis + formula recognition |
| GLM-OCR (MLX) | `ocr-swift` | 本機 MLX | 輕量 VLM，數學公式強 |

### OCR 引擎

簡化後只使用 **GLM-OCR** 作為唯一 VLM，搭配 PDFKit（向量 PDF）形成互補：

| Source | 模型 | HuggingFace repo | 參數量 | 記憶體 |
|--------|------|-----------------|--------|--------|
| PDFKit | （macOS 原生） | — | — | 零 |
| GLM-OCR | GLM-OCR 8-bit | EZCon/GLM-OCR-8bit-mlx | ~8B | ~5 GB |

單一 VLM 只需 ~5 GB，8 GB RAM 的 Mac 即可處理。

不再使用第二個 VLM（Qwen2.5-VL）。GLM-OCR 的忠實轉錄能力已足夠好，向量 PDF 透過 PDFKit 互補即可找出歧異。掃描 PDF 則直接信賴 GLM-OCR 結果，由 Claude 做最終排版。

Gemma 4 已實測排除（見 Design Decisions）。
詳見 [local-llm-on-mac.md](local-llm-on-mac.md) 的預設模型清單。

### New Components

#### 1. `OllamaOCR` — 遠端 Ollama backend

位置：`packages/ocr-swift/Sources/OCRCore/OllamaOCR.swift`

職責：
- 透過 SSH 或 Ollama HTTP API (`http://<host>:11434/api/generate`) 呼叫遠端 glm-ocr
- 支援多台主機平行分頁
- 傳送 base64 encoded image，接收 text response

Host 設定：
```json
// ~/.config/macdoc/config.json
{
  "ollama_hosts": [
    { "name": "local", "url": "http://localhost:11434" },
    { "name": "kyle", "url": "http://172.22.18.70:11434" }
  ]
}
```

#### 2. `EnsembleOCR` — diff + conflict detection

位置：`packages/ocr-swift/Sources/OCRCore/EnsembleOCR.swift`

職責：
- 接收 1 或 2 份結果（向量 PDF: PDFKit + GLM-OCR，掃描 PDF: GLM-OCR only）
- 自動偵測 PDF 類型（透過 `PDFSourceDetector`，已有）
- Line-by-line diff（僅向量 PDF 需要）
- 產出 `CleanText`（一致）+ `Conflicts`（歧異，含頁碼、行號、各版本）
- 每個 conflict 附上原圖裁切區域的路徑，方便 Claude 查看

Diff 策略：
- 先做 character-level normalization（空白、Unicode 正規化）
- 再做 line-level diff
- 數學公式區段（`$...$` 或 `$$...$$`）整段比對，不拆字元

兩方 diff 決策邏輯（向量 PDF: PDFKit vs GLM-OCR）：
- `P = G` → 高信度，直接採用
- `P ≠ G`（公式區段）→ 採用 GLM-OCR 版本（PDFKit glyph 亂碼）
- `P ≠ G`（其他）→ 標記為 conflict，交給 Claude

掃描 PDF：
- 只有 GLM-OCR 一個來源，不做 diff，直接交給 Claude 排版

#### 3. CLI 入口

整頁 GLM-OCR 透過 `macdoc pdf ocr` 子命令。兩種 mode：`local`（預設）和 `ollama`。

```bash
# 預設 local mode — GLM-OCR 跑本機 MLX
macdoc pdf ocr --project ./

# 明確指定 local
macdoc pdf ocr --project ./ --mode local

# Ollama mode — GLM-OCR 走 Ollama HTTP API
macdoc pdf ocr --project ./ --mode ollama

# Ollama mode + 指定 host（預設 localhost:11434）
macdoc pdf ocr --project ./ --mode ollama --host kyle

# 指定頁範圍
macdoc pdf ocr --project ./ --pages 1-10

# 單檔 OCR（top-level 命令，非 pipeline）
macdoc ocr paper.pdf --output result.md
```

| Mode | 執行方式 | 適用場景 |
|------|---------|---------|
| `local`（預設） | GLM-OCR 用 MLX 直接跑 | Apple Silicon Mac，RAM ≥ 8GB |
| `ollama` | GLM-OCR 走 Ollama HTTP API | RAM 不夠、想用遠端機器、或非 Apple Silicon |

#### 4. Output Format

```
result/
├── pages/
│   ├── page-001.png          # 原始頁面圖片
│   ├── page-001-pdfkit.txt   # PDFKit 文字提取（僅向量 PDF）
│   ├── page-001-glm.txt      # GLM-OCR 結果
│   └── ...
├── clean.txt                 # 一致的完整文字（向量 PDF: diff 後；掃描 PDF: GLM-OCR 原文）
├── conflicts.md              # 歧異報告（僅向量 PDF 有）
└── crops/                    # 歧異區域裁切圖
    ├── page-003-line-42.png
    └── ...
```

`conflicts.md` 格式（僅向量 PDF，PDFKit vs GLM-OCR）：
```markdown
## Page 3, Line 42

**PDFKit:** $? - ?$
**GLM-OCR:** $\xi - \sigma$

![crop](crops/page-003-line-42.png)

---

## Page 7, Line 15

**PDFKit:** Cramér (1946)
**GLM-OCR:** Cramer (1946)

![crop](crops/page-007-line-15.png)
```

#### 5. Claude Code Skill

位置：macdoc 的 Claude Code plugin（或獨立 skill）

Skill name: `/ocr`

```markdown
Trigger: 使用者要求 OCR 學術論文或 PDF

Steps:
1. 執行 `macdoc pdf ocr --project <dir>` （或 `--mode ollama --host kyle`）
2. 等待完成
3. 向量 PDF：讀取 conflicts.md
   - 若無歧異 → 直接進入排版步驟
   - 若有歧異 → 逐一讀取 crop 圖片，判斷正確版本（PDFKit vs GLM-OCR）
   掃描 PDF：直接使用 GLM-OCR 結果
4. 合併 clean.txt + 消歧異結果
5. 排版成完整 .tex 文件（加上 \documentclass, preamble, 公式編號, \section 結構等）
6. 輸出到使用者指定路徑
```

## Design Decisions

### Q: 為什麼不把 Claude 消歧異也做進 CLI？
A: 消歧異需要看圖 + 語意理解，這是 LLM 的強項。放在 skill 層讓 Claude 在對話中處理，使用者可以即時互動、確認、修改。CLI 應該只做機械活。

### Q: 為什麼簡化成只用 GLM-OCR 一個 VLM？
A: 實測發現 GLM-OCR 的忠實轉錄能力已經非常好（6313 chars 完整轉錄，引用完全正確），不需要第二個 VLM 來做 ensemble。向量 PDF 透過 PDFKit + GLM-OCR 的互補（不同技術棧：嵌入字型讀取 vs 圖像辨識）已經能找出歧異。掃描 PDF 則直接信賴 GLM-OCR，由 Claude 做最終排版。這樣省了一半的推論時間和記憶體。

### Q: 為什麼向量 PDF 仍然用 PDFKit？
A: 向量 PDF 裡文字已經嵌入了，PDFKit 提取零成本、即時、幾乎不會錯（普通文字）。它和 GLM-OCR 的錯誤模式完全不重疊——PDFKit 讀嵌入字型，GLM-OCR 看圖。PDFKit 弱項（數學公式 glyph 亂碼）剛好是 GLM-OCR 強項。兩方比對時大部分文字 PDFKit 就能確認，GLM-OCR 只需要在 PDFKit 失敗的公式區段出力。

### Q: 為什麼不用兩個 VLM 做 ensemble？
A: 簡化前的設計用 GLM-OCR + Qwen2.5-VL 兩個 VLM，但實測後發現：
1. **GLM-OCR 單獨已夠好** — 忠實轉錄能力強，不需要第二個 VLM 來「投票」
2. **PDFKit 互補更有效** — 向量 PDF 的 PDFKit 和 GLM-OCR 是完全不同技術棧（文字提取 vs 圖像辨識），比兩個 VLM 之間的差異更大
3. **資源減半** — 只需 ~5 GB（GLM-OCR），不再需要 ~8 GB（GLM-OCR + Qwen2.5-VL）
4. **掃描 PDF 本就沒有 PDFKit** — 只剩一個 VLM 時，不如直接信賴 GLM-OCR，歧異交給 Claude 在排版時處理

### Q: 為什麼不用 Gemma 4？
A: 實測排除。2026-04-04 用 "Beyond Pleasure and Pain" (Higgins, 1997) 在 Kyle (M4 Max) 的 Ollama 上測試 Gemma4 8B vs GLM-OCR，結果：

**Gemma4 不適合 OCR，有以下致命問題：**

1. **幻覺/捏造** — 把 "law of effect" 改成 "law of fit"，"what exactly does this entail?" 改成 "what exactly does suit?"
2. **引用錯誤** — Gollwitzer→Golliver、Bargh→Bergh、Pribram→Pribran、Pervin→Ferris、von Bertalanffy→Verlan、1960→1966
3. **重複輸出** — 最後兩段幾乎一模一樣
4. **摘要式改寫** — 不是逐字轉錄，而是「理解後改寫」，丟失 27% 內容（6313→4636 chars）

**根本原因：** Gemma4 是通用 VLM，傾向「理解→生成」而非「忠實轉錄」。Ensemble OCR 需要的是忠實轉錄，不是改寫。

**選擇標準更新：** 通用 VLM 會幻覺、改寫、丟細節，不適合 OCR 任務。這也是簡化 pipeline 後不再使用第二個 VLM 的原因之一——找到一個好的 OCR-specialized VLM（GLM-OCR）就夠了。

同場測試中 GLM-OCR 表現極佳——6313 chars 完整轉錄，引用完全正確，連 Unicode 引號和 en-dash 都比 PDFKit 準確。這個結果促成了從「2 VLM ensemble」簡化為「GLM-OCR only」的決策。

### Q: OCREngine protocol 回傳什麼？
A: 回傳 `String`（整頁文字）。不回傳 bbox 或結構化 block。理由：
- Ollama HTTP API 只回傳純文字，沒有 bbox
- 結構化排版交給 AI agent 做，不是 OCR 引擎的職責
- Line diff 對純文字就能運作

### Q: Ollama 的定位是什麼？
A: Ollama 是**執行管道的選項**，不是 pipeline 的核心。它讓沒有 Apple Silicon 或 RAM 不夠的人也能透過 HTTP API 跑 GLM-OCR（local 或 remote）。和 diff/排版邏輯正交。

### Q: 為什麼用 Ollama HTTP API 而不是 SSH？
A: HTTP API 更穩定（不依賴 shell 環境）、延遲更低（不需建立 SSH session）、支援 streaming、且 Ollama 原生支援。SSH 只在初始安裝和啟動 `ollama serve` 時使用。

### Q: 如何處理 Ollama 未安裝的情況？
A: Graceful fallback — 若無遠端 host 可用，退回本機 MLX 推論，GLM-OCR 仍然可以正常運作。

## Integration with Existing pdf-to-latex Pipeline

簡化後的 pipeline 使用 `macdoc pdf ocr` 取代舊的 `macdoc pdf transcribe`（CLITranscriber）。GLM-OCR 直接做整頁轉錄，不再需要 block-level segmentation + per-block transcription 的複雜流程。

```
簡化後的 pipeline：
  macdoc pdf ocr --project ./    # GLM-OCR 整頁轉錄
  macdoc pdf consolidate ...     # Phase 2 consolidation（不變）
```

舊的 `macdoc pdf transcribe`（CLITranscriber, claude/codex/gemini）已 deprecated。

## Milestones

1. **GLM-OCR local backend** — MLX 推論，整頁轉錄（已完成：`macdoc ocr`）
2. **OllamaOCR backend** — HTTP API client，支援 base64 image input
3. **`macdoc pdf ocr` 子命令** — 整合進 pdf-to-latex pipeline，取代 `transcribe`
4. **PDFKit + GLM-OCR diff**（僅向量 PDF）— line diff + math-aware comparison
5. **Conflict output format** — clean.txt + conflicts.md + crops/
6. **Claude Code skill** — `/ocr` skill for disambiguation + LaTeX formatting
7. **Config integration** — `~/.config/macdoc/config.json` 加入 ollama_hosts
