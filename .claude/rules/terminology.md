# 術語定義

## Format（格式）

檔案的結構與編碼方式。決定 `--to` 的值。

`--to` 的值 = 輸出的副檔名。不另起名稱，直接用副檔名辨識。

| `--to` | 副檔名 / 結構 | 特性 |
|--------|--------------|------|
| `md` | `.md` | 純文字，單一檔案 |
| `html` | `.html` | 標記語言，單一檔案 |
| `docx` | `.docx` | 二進位 OOXML，單一檔案，不支援 stdout |
| `json` | `.json` | 結構化資料，單一檔案 |
| `tex` | `.tex` | 純文字標記，單一檔案（目前僅作為輸入格式，PDF→TeX 走 pipeline） |
| `marker` | 目錄（`.md` + `_meta.json` + `images/`） | 唯一例外：複合輸出，無副檔名，`--output` 指定目錄 |

判斷標準：如果輸出的結構不同，它就是不同的 format。
`marker` 是唯一沒有對應副檔名的 format，因為它的輸出是目錄結構而非單一檔案。

## Style（樣式）

同一個 format 內的視覺呈現差異。透過 `--css` 指定。

| Style | 適用 format | 用途 |
|-------|------------|------|
| `dark` | `html`（SRT 來源） | 深色主題 |
| `light` | `html`（SRT 來源） | 淺色 / 列印 |
| `minimal` | `html`（bib 來源） | 學術風格，Times New Roman |
| `web` | `html`（bib 來源） | 現代風格，系統字體 |

Style 不改變 format，只改變 CSS。同一個 `--to html` 可以搭配不同 `--css`。

## Option（轉換選項）

控制轉換行為的旗標，不屬於 format 也不屬於 style。

| Option | 說明 |
|--------|------|
| `--full` | 輸出完整 HTML 文件（DOCTYPE + head + body）vs fragment |
| `--hard-breaks` | 保留源格式換行為目標格式的硬換行 |
| `--frontmatter` | 加入 YAML frontmatter metadata |
| `--output` | 輸出路徑（檔案或目錄，依 format 而定） |
| `--stdout` | 強制輸出到 stdout（覆蓋 `--output`） |

## 區分原則

```
format  → 輸出的是什麼東西（結構、編碼）  → --to
style   → 輸出長什麼樣子（視覺呈現）      → --css
option  → 怎麼轉換（行為控制）            → --full, --hard-breaks, etc.
```

新增功能時，先問：「這改變的是輸出結構、視覺呈現、還是轉換行為？」
