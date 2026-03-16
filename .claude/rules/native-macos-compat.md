# 原生 macOS 能力優先原則

## 原則

macdoc 必須優先使用 macOS 原生 framework 處理文件，不引入外部 CLI 工具或跨平台函式庫來做系統已經能做的事。
每個 converter 的基礎層應對映到一個原生能力，macdoc 在其上加結構化 heuristics。

## 原生能力對映表

| 功能 | 原生方法 | macdoc 用法 | 加值 |
|------|---------|------------|------|
| PDF 文字提取 | `PDFPage.string` / `PDFSelection.selectionsByLine()` | `pdf-to-md-swift` | heading/list/block heuristics |
| PDF metadata | `PDFDocument.documentAttributes` | `pdf detect-source` | 來源格式推斷 |
| PDF 頁面渲染 | `CGContext` + `PDFPage.draw()` | `pdf-to-latex-swift` Phase 1 | block segmentation |
| OCR | `Vision.framework` (`VNRecognizeTextRequest`) | `che-pdf-mcp`, `surya-swift` | 多語言、表格、數學式 |
| Word 解析 | `ZIPFoundation` + XML parsing | `ooxml-swift` | 語義標註、樣式繼承 |
| 圖片處理 | `CoreGraphics`, `AppKit` (`NSImage`) | `marker-swift` | 分類、格式轉換 |
| HTML 解析 | 第三方 `SwiftSoup`（例外） | `html-to-md-swift` | — |
| Markdown 解析 | `apple/swift-markdown` | `md-to-html-swift`, `md-to-word-swift` | — |

## 設計規則

1. **原生 framework 優先** — 如果 macOS 內建 framework 能做，不引入外部依賴
2. **PDFKit 是 PDF 的基礎層** — 所有 PDF 文字提取必須從 `PDFKit` 開始，不用 poppler/pdftotext
3. **Vision 是 OCR 的唯一後端** — 不引入 Tesseract 或其他 OCR engine
4. **CoreGraphics 處理圖片** — 不引入 ImageMagick 或 libvips
5. **允許的例外** — `SwiftSoup`（HTML parsing，Apple 沒有原生 HTML parser）、`ZIPFoundation`（ZIP 操作）、`swift-markdown`（Apple 官方但非系統內建）
6. **外部 AI CLI 是委派，不是依賴** — `codex`/`claude`/`gemini` 是 transcription 的外部工具，macdoc 不直接呼叫 LLM API

## textutil 能力對照

`textutil` 是 macOS 內建的文件轉換 CLI，macdoc 的轉換指令語法與其相容（見 `cli-design/textutil-compat.md`）。

| textutil 支援 | macdoc 對應 | 差異 |
|--------------|------------|------|
| `.docx` → `.html` | `convert --to html file.docx` | macdoc 多了 APA styling、SRT 等格式 |
| `.docx` → `.txt` | `convert --to md file.docx` | macdoc 輸出結構化 Markdown |
| `.html` → `.docx` | `convert --to docx file.html` | macdoc 透過 OOXML 直接生成 |
| `.pdf` → (不支援) | `convert --to md file.pdf` | macdoc 用 PDFKit 提取 |

## 新增 converter 的檢查清單

新增格式轉換器時，確認：

- [ ] 基礎提取用原生 framework（PDFKit / Vision / CoreGraphics）
- [ ] 不引入可用原生替代的外部依賴
- [ ] 如果需要外部依賴，記錄在上方「允許的例外」
- [ ] CLI 語法遵循 `cli-design/` 規範（unix-conventions + textutil-compat + convert-entry-point）
- [ ] 在 `CONVERSIONS.md` 更新轉換矩陣
