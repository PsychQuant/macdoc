## Why

GLM-OCR (0.9B, Zhipu AI) 的實測結果遠超預期。在四種場景（英文學術論文、中文數學公式、統計考題掃描件、中英混合表格）上，單一模型的整頁 OCR 已經能忠實轉錄文字、公式、表格結構。

這代表現有 pdf-to-latex pipeline 的多個步驟不再必要：
- **Block segmentation**（Vision OCR 偵測文字區塊）→ 不需要，GLM-OCR 整頁處理
- **Per-block AI transcribe**（逐 block 送 codex/claude/gemini）→ 不需要，GLM-OCR 本機完成
- **Ensemble 雙 VLM**（GLM-OCR + Qwen2.5-VL 交叉比對）→ 不需要，GLM-OCR 單獨已夠好
- **CLITranscriber**（外部 AI CLI 工具）→ 不需要用於文字/公式轉錄

簡化後的 pipeline 從 5+ 步驟降為 2 步驟：render → GLM-OCR 整頁 → Claude 排版。

## What Changes

### 簡化 PDF → TeX pipeline

現有流程：
```
init → segment → render → blocks → transcribe (per block, AI API) → chapters → assemble → consolidate
```

新流程：
```
向量 PDF:  render → PDFKit 文字提取 + GLM-OCR 整頁 → diff → Claude 排版 .tex
掃描 PDF:  render → GLM-OCR 整頁 → Claude 排版 .tex
```

### 砍掉的元件

| 元件 | 原因 |
|------|------|
| `BlockSegmentationPipeline` | GLM-OCR 整頁處理，不需要切 block |
| `CLITranscriber` / `TranscriptionWorker` | 不再需要外部 AI API 轉錄文字 |
| Per-block transcribe loop（含 concurrency、throttle、retry） | 整頁 OCR 不需要 block 管理 |
| Ensemble 雙 VLM diff（EnsembleOCR 設計中的 Source B） | GLM-OCR 單獨夠好 |

### 保留的元件

| 元件 | 用途 |
|------|------|
| `PageRenderer` | 渲染 PDF 頁面為 PNG（GLM-OCR 需要圖片輸入） |
| `PDFSourceDetector` | 判斷向量/掃描 PDF，決定是否加 PDFKit 文字提取 |
| PDFKit 文字提取 | 向量 PDF 的免費第二來源，與 GLM-OCR 做兩路比對 |
| `ChapterPlanner` / `TexAssembler` | Phase 2 組裝不變 |
| Phase 3 consolidation（normalize, fix-envs, compile-check） | 不變 |
| `OCRPipeline`（ocr-swift） | GLM-OCR 的 MLX 推論核心，保留並升級為主角 |

### 新增的元件

| 元件 | 用途 |
|------|------|
| `PDFKitExtractor` | 向量 PDF 的文字提取，回傳 per-page String |
| `SimpleOCRPipeline` | 新的簡化 pipeline：render → OCR → diff（如向量 PDF） |
| `macdoc pdf ocr` 子命令 | 取代現有 `transcribe` / `transcribe-pages`，直接整頁 OCR |

### CLI 變化

```bash
# 舊（砍掉）
macdoc pdf blocks --project ./
macdoc pdf transcribe --project ./ --model gpt-5.4
macdoc pdf transcribe-pages --project ./ --backend claude
macdoc pdf resume --project ./

# 新（簡化）
macdoc pdf ocr --project ./                    # 整頁 GLM-OCR（預設 local）
macdoc pdf ocr --project ./ --mode ollama      # 透過 Ollama
macdoc pdf ocr --project ./ --with-pdfkit      # 向量 PDF 加 PDFKit 比對

# 不變
macdoc pdf init / segment / render / chapters / assemble / normalize / fix-envs / compile-check / consolidate
```

## Non-Goals

- **不砍 `macdoc ocr` 獨立子命令** — 獨立 OCR 功能保留（不綁 pdf-to-latex pipeline）
- **不移除 Ollama 支援** — 作為 local MLX 的替代執行管道保留
- **不重寫 Phase 2/3** — assemble 和 consolidation 不在此次範圍
- **不處理 Figure 內嵌圖片的 OCR** — 這仍需要 Claude 看圖，不是 GLM-OCR 能解的
- **不砍 surya-swift** — 它有 layout analysis 能力，未來可能用於其他用途

## Capabilities

### New Capabilities

- `simplified-pdf-ocr`: 簡化的 PDF OCR pipeline，用 GLM-OCR 整頁取代 block segmentation + per-block AI transcribe

### Modified Capabilities

- `pdf-to-latex-pipeline`: Phase 1 從 block-based 改為 page-based OCR

## Impact

- Affected specs: `simplified-pdf-ocr`（新）, `mlx-model-management`（相關）
- Affected code:
  - `Sources/MacDocCLI/MacDoc+PDF.swift` — 砍 Blocks/Transcribe/TranscribePages/Resume 子命令，加 OCR 子命令
  - `packages/pdf-to-latex-swift/` — 砍 BlockSegmentationPipeline, CLITranscriber, TranscriptionWorker
  - `packages/ocr-swift/` — OCRPipeline 升級，加 PDFKitExtractor
  - `docs/ensemble-ocr-design.md` — 更新架構（已部分完成）
