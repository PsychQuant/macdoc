# CLI 設計規範：textutil 向下相容

## 原則

macdoc CLI 的轉換指令必須與 macOS 內建 `textutil` 的語法模式相容。
使用者如果會用 `textutil`，應該能直覺地使用 `macdoc`。

## textutil 參考語法

```bash
textutil -convert fmt [options] file...
textutil -info file...
textutil -cat fmt file...
```

核心特徵：
- **動作在前**（`-convert`, `-info`）
- **格式是動作的參數**（`-convert html`）
- **檔案放最後**
- **input format 從副檔名自動偵測**（除非用 `-format` 覆蓋）
- **output 預設同目錄換副檔名**（除非用 `-output` 指定）

## macdoc 對應語法

```bash
# 轉換（對應 textutil -convert）
macdoc convert --to md file.docx
macdoc convert --to html file.md
macdoc convert --to html --style apa file.bib
macdoc convert --to tokens file.md
macdoc convert --to tokens --model gpt-4o file.md

# 資訊（對應 textutil -info）
macdoc info file.docx

# 輸出控制（對應 textutil -output / -stdout）
macdoc convert --to md --output result.md file.docx
macdoc convert --to md --stdout file.docx
```

## 設計規則

1. **檔案永遠放最後** — 跟 textutil、Unix 慣例一致
2. **input format 自動偵測** — 從副檔名推斷，不需要使用者指定
3. **用 `--` long flags** — 遵循 swift-argument-parser 慣例（`--to`, `--output`），不用 textutil 的單 dash（`-convert`）
4. **轉換統一用 `convert` subcommand** — 所有格式轉換走同一個入口
5. **非轉換功能用獨立 subcommand** — `pdf init/status/...`、`config ai detect/...` 維持現狀
6. **`--to` 的值是 target format 短名** — `md`, `html`, `json`, `latex`, `tokens`

## Format 短名對照

| --to 值 | 全名 | 對應 package |
|---------|------|-------------|
| `md` | Markdown | `word-to-md-swift`, `html-to-md-swift` |
| `html` | HTML | `md-to-html-swift`, `srt-to-html-swift`, `bib-apa-to-html-swift` |
| `json` | JSON | `bib-apa-to-json-swift` |
| `latex` | LaTeX | `pdf-to-latex-swift` |
| `tokens` | Token count | `token-counter-swift` |

## 遷移

現有的 `macdoc word to-md`、`macdoc html to-md` 等指令在遷移期間保留為 alias，
新功能一律用 `macdoc convert --to` 格式。最終目標是統一到 `convert` 入口。
