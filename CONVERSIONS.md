# macdoc Conversion Matrix

> 平台聲明
> - Token 計數／離線 GPT-4o 層：macOS 27.0（arm64）、Apple Swift 6.3.3；狀態為 `verified`，compiled route 已在 `sandbox-exec` 禁網路與隔離 HOME／cache 下通過 `hello world` exact-byte acceptance；package suite 另通過五組官方 Python `tiktoken` reference vectors。
> - Anthropic token-count transport 層：macOS 27.0（arm64）、Apple Swift 6.3.3；狀態為 `implemented-not-live-verified`，只以注入 transport 驗證 fixed request、response limits、錯誤映射與資料遮蔽，沒有 live provider call。
> - Windows／Linux token 計數：macdoc CLI 與 `TokenCounter` package；狀態為 `not-supported`，目前 manifests 僅宣告 macOS 14+。
> - 證據：`swift test --filter TokenCountCommandTests`、`swift test`（`packages/token-counter-swift`），以及 bundled resource SHA-256 regression。

## Status Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | **implemented** — merged and available |
| · | not planned |

## Token Counting（measurement route，非格式轉換）

`tokens` 接受任何副檔名的一般檔案，但內容必須是完整、嚴格 UTF-8，大小不得超過
1,000,000 bytes。它不透過 matrix 中的中繼格式，也不截斷輸入。

| Model | Invocation | Boundary |
|---|---|---|
| `gpt-4o` | `macdoc convert --to tokens --model gpt-4o sample.txt` | bundled `o200k_base.tiktoken`；固定 SHA-256；完全離線，不下載或寫 cache／HOME |
| `claude-sonnet-4-6` | `macdoc convert --to tokens --model claude-sonnet-4-6 --allow-network sample.txt` | 需要非空 `ANTHROPIC_API_KEY`；把完整檔案文字送到 Anthropic；結果是 provider-reported estimate |
| default（兩者） | `macdoc convert --to tokens --allow-network sample.txt` | 固定 GPT-4o → Claude 順序；兩者都成功才輸出，否則沒有部分 stdout／檔案 |

若 `sample.txt` 精確包含 `hello world`，GPT-4o compiled acceptance 的 stdout bytes 為：

```text
2
```

單模型成功固定輸出 `<ASCII integer>\n`。雙模型成功固定輸出 tab-separated bytes：

```text
Model	Tokens
gpt-4o	1234
claude-sonnet-4-6	1198
```

`--output tokens.txt` 只在所有 requested providers 成功後原子寫入；失敗時不存在的目的檔
維持不存在，既有目的檔維持原 bytes。`--allow-network` 是逐次 disclosure consent：環境中有
API key 本身不代表允許送出當次檔案。Anthropic 的 estimate 不應與 bundled GPT-4o 的離線
reference-vector 精確值混為一談。

## Cross Matrix (Source → Target)

|  → Target | Markdown | HTML | Word (.docx) | LaTeX | JSON | PDF | SRT |
|----------:|:--------:|:----:|:------------:|:-----:|:----:|:---:|:---:|
| **Markdown** | — | ✅ `md-to-html` | ✅ `md-to-word` (OMath opt-in) | · | · | · | · |
| **HTML** | ✅ `html-to-md` | — | ✅ `html-to-word` | · | · | · | · |
| **Word (.docx)** | ✅ `word-to-md` | ✅ `word-to-html` | — | · | · | · | · |
| **PDF** | ✅ `pdf-to-md` | · | ✅ `pdf-to-docx` | ✅ `pdf-to-latex` | · | — | · |
| **BibLaTeX (.bib)** | ✅ `bib-apa-to-md` | ✅ `bib-apa-to-html` | · | · | ✅ `bib-apa-to-json` | · | · |
| **SRT** | · | ✅ `srt-to-html` | · | · | · | · | — |
| **舊版 Note (.note)** | · | ✅ `note-to-html` | · | · | · | ✅ `note-to-pdf` | · |

Notability 轉換目前支援舊版 plist-based `.note`（`Session.plist`）。現代 `.ntb`（FlatBuffers `noteBundle`）會被辨識，但尚不支援轉換；尚未實作 FlatBuffers 的手寫／時間軸重播，也不會抽取錄音、縮圖或其他資產作為替代輸出。

## Converter Details

| Source → Target | Package | Status | Notes |
|-----------------|---------|--------|-------|
| Word → Markdown | `word-to-md-swift` | ✅ implemented | Layer 3 converter |
| HTML → Markdown | `html-to-md-swift` | ✅ implemented | SwiftSoup-based streaming emitter |
| Markdown → HTML | `md-to-html-swift` | ✅ implemented | swift-markdown AST renderer |
| SRT → HTML | `srt-to-html-swift` | ✅ implemented | structured HTML with timestamp + speaker detection |
| PDF → LaTeX | `pdf-to-latex-swift` | ✅ implemented | Phase 1 + Phase 2 pipeline |
| BibLaTeX → APA HTML | `bib-apa-to-html-swift` | ✅ implemented | style-aware renderer |
| BibLaTeX → APA Markdown | `bib-apa-to-md-swift` | ✅ implemented | style-aware renderer |
| BibLaTeX → APA JSON | `bib-apa-to-json-swift` | ✅ implemented | pre-rendered HTML + anchors |
| PDF → Markdown | `pdf-to-md-swift` | ✅ implemented | direct path via PDFKit, heading/list heuristics |
| Word → HTML | `word-to-html-swift` | ✅ implemented | direct path preserves Word semantics |
| HTML → Word | `html-to-word-swift` | ✅ implemented | SwiftSoup → OOXML writer |
| Markdown → Word | `md-to-word-swift` | ✅ implemented | swift-markdown AST → OOXML writer; native OMath is opt-in with `macdoc convert input.md --to docx --math omath --output output.docx` (`literal` is the default) |
| PDF → DOCX | `pdf-to-docx-swift` | ✅ implemented | PDFKit text extraction → OOXML writer |
| 舊版 Note → HTML | `note-to-html-swift` | ✅ implemented | plist-based `.note` → interactive HTML player with audio-synced stroke replay |
| 舊版 Note → PDF | `note-to-pdf-swift` | ✅ implemented | plist-based `.note` → rendered PDF |
| UTF-8 text → Token count | `token-counter-swift` | ✅ implemented | measurement route；GPT-4o offline，Claude 僅在逐次同意後連線 |

### Markdown → Word native math boundary

Native Word OMath applies only to the Markdown → Word (`.docx`) route and must be enabled with `--math omath`. Without `--math`, or with `--math literal`, dollar-delimited formulas remain literal Markdown text.

OMath mode supports the [versioned `latex-math-swift` macro subset](https://github.com/PsychQuant/latex-math-swift#supported-macros): fractions and radicals, subscript and superscript, accents, delimiters, n-ary operators, functions, limits, text, Greek symbols, and common operators. Full TeX support and Pandoc texmath parity are outside this capability. Every other conversion route rejects `--math omath`.

## Rules

- Open **one issue per converter** before writing code.
- New forward converter implies the reverse path is reconsidered immediately.
- Prefer direct source→target converters over hub-based routing.
- Keep Layer 3 packages independent: source format + target format + `common-converter-swift`, no converter-to-converter imports.
