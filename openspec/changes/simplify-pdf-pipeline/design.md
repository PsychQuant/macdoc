## Context

macdoc 的 pdf-to-latex pipeline 目前有 Phase 1（OCR + transcription）和 Phase 2/3（assembly + consolidation）。Phase 1 使用 block segmentation（Vision OCR 切 block）+ per-block AI transcription（codex/claude/gemini CLI）的兩階段架構。

2026-04-04 的 benchmark 測試證明 GLM-OCR（0.9B, Zhipu AI, MLX 推論）在四種場景上整頁 OCR 已足夠忠實：
- 英文學術論文純文字：6,314 chars，引用全正確
- 中文數學公式：$z = x + yi$, $\bar{z}$, $\sqrt{(x_2-x_1)^2}$ 等全正確
- 統計考題掃描件：迴歸公式 + 表格 + 矩陣全正確
- 中英混合：無問題

現有 Phase 1 的 block segmentation + per-block transcribe 是為了應對「單一 OCR 不夠好」而設計的。既然 GLM-OCR 整頁就夠好，這個中間層可以移除。

## Goals / Non-Goals

**Goals:**

- 將 Phase 1 從 5+ 步驟簡化為 1-2 步驟
- 移除對外部 AI CLI API 的依賴（codex/claude/gemini）用於文字轉錄
- 保持向量 PDF 的 PDFKit + GLM-OCR 兩路比對能力
- 保留現有 Phase 2/3 不動
- CLI 介面向後相容（舊子命令標記 deprecated，新子命令 `pdf ocr` 取代）

**Non-Goals:**

- 不處理 Figure 內嵌圖片的 OCR（仍交給 Claude skill）
- 不改 Phase 2/3（assemble, consolidate）
- 不移除 Ollama 支援
- 不移除 surya-swift package

## Decisions

### D1: Phase 1 改為 page-level OCR

**現有架構**:
```
render → blocks (Vision) → transcribe (AI per block) → chapters → assemble
```

**新架構**:
```
render → OCR (GLM-OCR per page) → chapters → assemble
```

每頁產出一個 `.md` 或 `.tex` 文字檔，取代現有的 per-block snippet。manifest 的 `blocks` 欄位改為 `pages[].ocrText` 或 per-page 檔案路徑。

**理由**: GLM-OCR 整頁處理已證明足夠，block segmentation 是不必要的中間層。

### D2: 向量 PDF 保留 PDFKit 作為第二來源

**策略**:
```
if detect-source == vector:
    result_p = PDFKit.extractText(page)
    result_a = GLM-OCR.processImage(page)
    if result_p ≈ result_a:
        use result_a (GLM-OCR 的 typography 更準確)
    else:
        mark conflicts for Claude
else:  # scanned
    result_a = GLM-OCR.processImage(page)
    use result_a directly
```

PDFKit 零成本，向量 PDF 上多一路比對不虧。但不再需要第二個 VLM。

**理由**: 測試顯示 PDFKit 在 body text 上和 GLM-OCR 高度一致（98.5%），差異都是 PDFKit 的 glyph 問題。一致的部分互相確認信度，不一致的部分大概率是 PDFKit 錯。

### D3: OCRPipeline 升級為 pipeline 的核心

`packages/ocr-swift/Sources/OCRCore/Pipeline/OCRPipeline.swift` 已有 `processImage()` 和 `processFile()` 方法。需要新增：
- `processPage(image: CGImage) -> String` — 回傳整頁文字（已有，就是 `processImage`）
- 讓 `MacDoc+PDF.swift` 的新 `OCR` 子命令呼叫它

不需要新建 package。`ocr-swift` 已經是正確的位置。

### D4: CLI 子命令遷移

| 舊子命令 | 處置 |
|---------|------|
| `pdf blocks` | 標記 deprecated，保留但不在新 pipeline 中使用 |
| `pdf transcribe` | 標記 deprecated |
| `pdf transcribe-pages` | 標記 deprecated |
| `pdf resume` | 標記 deprecated |
| `pdf ocr`（新） | 整頁 OCR，取代上述所有 |

`pdf ocr` 的 flags：
- `--project` — 專案目錄（和其他 pdf 子命令一致）
- `--mode local|ollama` — 執行管道（預設 local）
- `--with-pdfkit` — 向量 PDF 時加 PDFKit 比對（自動偵測時可省略）
- `--first-page` / `--last-page` — 頁碼範圍

### D5: Manifest schema 更新

現有 manifest 有 `blocks: [BlockRecord]`。新增 `ocrResults: [PageOCRResult]`：

```swift
struct PageOCRResult: Codable {
    let pageNumber: Int
    let ocrText: String           // GLM-OCR 輸出
    let pdfkitText: String?       // PDFKit 輸出（向量 PDF only）
    let ocrTextPath: String?      // 文字檔路徑
    let agreement: Double?        // 兩路一致度（0-1）
    let hasConflicts: Bool        // 是否有歧異
}
```

`blocks` 欄位保留（向後相容）但新 pipeline 不寫入。

## Risks / Trade-offs

### R1: GLM-OCR 在未測場景的表現

已測：英文論文、中文數學、統計掃描件、中英混合。
未測：多欄排版、非拉丁文字（日文、韓文、阿拉伯文）、低解析度影印件、大量 inline figure 的頁面。

**緩解**: 舊的 block-based pipeline 標記 deprecated 但不刪除。如果特定文件類型 GLM-OCR 不行，可以 fallback。

### R2: MLX 依賴增強

簡化後 GLM-OCR 變成 pipeline 的唯一 OCR 引擎。如果 mlx-swift-lm 有 breaking change 或 GLM-OCR 模型下架，pipeline 會完全斷。

**緩解**: Ollama 作為替代執行管道保留。模型權重可本地快取。

### R3: 砍掉 per-block transcribe 後失去細粒度重試

現有 pipeline 可以針對單一失敗的 block 重跑。新 pipeline 是整頁為單位，失敗只能重跑整頁。

**緩解**: 整頁 OCR 在本機跑（~20s/page），重跑成本低。不像外部 API 有費用和 rate limit。
