# pdf-to-latex

用 Swift 建立的 macOS CLI，目標是把數學課本 PDF 拆成可驗證的工作流，而不是一次賭整本自動轉寫。

目前這一版先提供：

- `init-project`: 建立專案資料夾與 `manifest.json`
- `segment`: 掃描來源 PDF 的頁數、尺寸、旋轉資訊
- `render-pages`: 把每頁渲染成 PNG，作為後續視覺驗證基礎
- `segment-blocks`: 偵測文字區塊並裁出 block PNG
- `transcribe-blocks`: 直接把 block 圖丟給 Codex CLI 轉成 LaTeX
- `resume`: 從既有專案的 checkpoint 狀態續跑轉寫
- `detect-chapters`: 自動產生章節設定檔
- `assemble-tex`: 合併 snippets 與頁面背景，輸出可編譯的 `main.tex`
- `status`: 檢查目前專案狀態

## 專案結構

初始化後會建立這些資料夾：

```text
input/
pages/
blocks/
snippets/
lossless/
semantic/
reports/
tmp/
manifest.json
```

## 使用方式

建立專案：

```bash
swift run pdf-to-latex init-project \
  --pdf /absolute/path/to/book.pdf
```

若不提供 `--output`，預設會在來源 PDF 同一個資料夾建立一個同名專案資料夾，例如 `/path/book.pdf` 會建立到 `/path/book/`。

若要覆寫輸出位置：

```bash
swift run pdf-to-latex init-project \
  --pdf /absolute/path/to/book.pdf \
  --output /absolute/path/to/project
```

掃描 PDF：

```bash
swift run pdf-to-latex segment --project /absolute/path/to/project
```

渲染頁面：

```bash
swift run pdf-to-latex render-pages \
  --project /absolute/path/to/project \
  --first-page 1 \
  --last-page 5 \
  --dpi 144
```

切出 blocks：

```bash
swift run pdf-to-latex segment-blocks --pdf /absolute/path/to/book.pdf
```

這也會預設把專案建立在來源 PDF 同資料夾下的同名資料夾。

也可以指定既有專案：

```bash
swift run pdf-to-latex segment-blocks \
  --project /absolute/path/to/project \
  --first-page 1 \
  --last-page 3
```

直接從 PDF 轉寫 blocks：

```bash
swift run pdf-to-latex transcribe-blocks \
  --pdf /absolute/path/to/book.pdf \
  --model gpt-5.4 \
  --concurrency 2 \
  --throttle-seconds 1 \
  --timeout-seconds 90
```

同樣地，若沒給 `--output`，預設專案位置就是來源 PDF 同資料夾下的同名資料夾。
另外，這個工具會固定用 `model_reasoning_effort="low"` 呼叫 `codex exec`，避免吃到全域較高的 reasoning 設定。

只測單一 block：

```bash
swift run pdf-to-latex transcribe-blocks \
  --project /absolute/path/to/project \
  --block-id p0001-b0003 \
  --model gpt-5.4 \
  --timeout-seconds 30
```

中斷後續跑：

```bash
swift run pdf-to-latex resume \
  --project /absolute/path/to/project \
  --model gpt-5.4 \
  --concurrency 8 \
  --throttle-seconds 0.5 \
  --timeout-seconds 90
```

`resume` 和 `transcribe-blocks --project ...` 都會自動回收停在 `transcribing` 的 blocks，改回可續跑狀態後繼續處理。

組成可編譯的 TeX 並直接編 PDF：

```bash
swift run pdf-to-latex assemble-tex \
  --project /absolute/path/to/project
```

指定章節切法：

```bash
swift run pdf-to-latex assemble-tex \
  --project /absolute/path/to/project \
  --chapter-strategy pages \
  --page-ranges 1-24,25-60,61-103
```

使用自訂章節設定：

```bash
swift run pdf-to-latex assemble-tex \
  --project /absolute/path/to/project \
  --chapter-strategy custom \
  --chapter-config /absolute/path/to/chapters.json
```

自動偵測章節並輸出設定檔：

```bash
swift run pdf-to-latex detect-chapters \
  --project /absolute/path/to/project \
  --chapter-strategy auto
```

查看狀態：

```bash
swift run pdf-to-latex status --project /absolute/path/to/project
```

## 下一步

接下來預計補上：

1. 更穩定的版面分欄與圖表偵測
2. block 級別像素驗證
3. lossless 組版與全書比對

## Chapter Strategy

- `auto`: 先試 PDF outline，再試 heading 偵測，最後退回 `pages` 或 `single`
- `outline`: 用 PDF bookmarks / outline 切章
- `headings`: 用頁面上方 block 的標題樣式做粗略切章
- `pages`: 用 `--page-ranges` 明確指定頁碼區間
- `single`: 整個頁碼範圍只輸出成一個 chapter
- `custom`: 讀取 `--chapter-config` JSON

`detect-chapters` 與 `assemble-tex` 都會把實際使用的章節設定自動寫到：

```text
reports/chapters/<strategy>.json
```

`custom` 設定檔格式：

```json
{
  "chapters": [
    { "id": "ch01", "title": "Introduction", "startPage": 1, "endPage": 24 },
    { "id": "ch02", "title": "Probability", "startPage": 25, "endPage": 60 }
  ]
}
```
