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
| `config` | 設定管理 | AI CLI 工具、OCR host/model 預設值、文件格式 profile |
| `pdf` | PDF→LaTeX | 學術 PDF 處理（較少用） |
| `bib` | BibLaTeX→APA | 參考文獻格式轉換 |
| `word` | docx ⇄ `.mdocx.swift` 腳本；表單整理（`word form`，需要下一版 CLI，尚未發布） | 把文件變成可重播的重建腳本、再放回 docx；填好的官方表單統一字級、置中與方框 |

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
| `--css dark` | SRT 轉 HTML 時用深色主題（SRT／note 不帶 `--css` 時的預設，CLI 0.11.0+；bib 不帶時是 `web`）|
| `--hard-breaks` | 軟換行視為硬換行 |
| `--frontmatter` | 包含 YAML frontmatter |
| `--html-extensions` | MD 中保留 `<u>/<sup>/<sub>/<mark>` |
| `--profile inherit\|official` | 轉 DOCX 時套用的文件格式 profile（CLI 0.9.0+；見下方 `config document`）|
| `--document-config <path>` | 改用指定的文件設定檔（CLI 0.9.0+）|

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

> ⚠️ **以下兩項需要 macdoc CLI 0.7.0 以上**（已發布）。留在 0.6.0 的話：輸出檔已存在時會被無條件覆寫，驗證失敗會在原檔已被破壞之後才回報，且 `--to-docx` 指向既有目錄再加 `--force` 會把整個目錄換成一個檔案。見 PsychQuant/che-word-mcp#180 / #181、PsychQuant/ooxml-swift#109。

**輸出檔已存在時預設拒絕**，要 `--force`。**驗證失敗什麼都不寫出**——輸出路徑保持原狀，也不會印「已寫入」（重建結果先落在同目錄的暫存路徑，驗過才搬進位）。這兩個保證都由 CLI 與 MCP 共用的入口提供，兩面行為一致。

| 選項 | 屬於 | 說明 |
|------|------|------|
| `--coverage` | reverse | 印 per-part 的 DSL/raw 覆蓋率報告 |
| `--slot <name>=<paraId>` | reverse | 指定段落成為腳本的具名參數（strict，不推斷）。文件落在 raw channel 時（含複雜表格的官方表單常見；以 `--coverage` 或腳本裡的 `// @slot-raw` 為準），slot **需要 0.8.0+**：0.7.0 的 render 不報錯，而是輸出沒填值的模板（見 swiftify skill）|
| `--paragraphs-only` | reverse | 退回舊的段落反向（**無** byte-equal 保證）；MCP 對應 `export_script` 的 `paragraphs_only`（che-word-mcp 4.3.0+）|
| `--from-oplog` | reverse | 強制用 oplog sidecar |
| `--verify-against <docx>` | render | 對照參考檔做 byte-equal 驗證；**不給就不驗** |
| `--profile inherit\|official` | render | 驗證與發布前套用文件格式 profile；**不給就不讀設定檔、照腳本重播**（CLI 0.9.0+）|
| `--force` | 兩者 | 先檢查精確目標並取得使用者對該檔案的明確事前同意，才可覆寫；不給就拒絕且不動既有檔案 |

完整的覆寫同意邊界與使用新路徑的工作流見 [`swiftify`](../swiftify/SKILL.md) skill。

### 這條迴路保證什麼、不保證什麼

**保證**：byte-equal 重播。`--verify-against` 通過就代表重建出的每個 XML part 與參考檔逐位元組相同。

**不保證**：產物可讀。腳本有兩條 channel——typed DSL（可讀）與 raw（把整個 XML part 逐字塞進一行 `// @op`）。**DSL 升級是 per-part 全有全無**：canonical minimal table 可用 typed DSL 表示，但仍須整個 part 的其他內容都受支援且試重建 byte-equal 才會升級；不支援的 rich／foreign-form table 可能讓整個 `word/document.xml` 留在 raw。明確選 `--paragraphs-only` 則會省略所有表格。

歷史實測樣本 `REC-O-01` 的結果如下；這是該份文件的量測，不是「含一個表格必為 0%」的規則：

```
--- Aggregate: 0.0% DSL (0 / 190479 XML bytes across 16 parts) ---
```

產出是 24 行 / 212 KB，其中 `word/document.xml` 那一行就佔約 118 KB。**它能完美重播，但不能讀、不能手改、也無法有意義地做版控 diff**（改一個字會讓整條 118 KB 的行重新 escape）。

所以**先跑 `--coverage` 再決定期待值**——不要因為文件看起來簡單就假設會拿到可讀的 Swift。

> 完整工作流（含 slot 填寫與 MCP 對應工具）見 [`swiftify`](../swiftify/SKILL.md) skill；本節只是命令參考。

### word form — 表單整理（需要下一版 CLI，尚未發布）

render 填好值之後，範本本身的不一致（欄位字級 9／11／12 pt 混用、註解文字樣式、首行縮排、分散對齊、儲存格沒垂直置中、多餘空段落、方框跟 Latin 字同 run 而變小）會原樣留在輸出。`word form` 在 render **之後**整理這些，只改 `word/document.xml` 裡被點名的元素，其他 part 的內容逐位元組不變（zip 容器本身重新寫出）；不經 typed 模型，所以落在 raw channel 的表單也不會被改寫正文（PsychQuant/macdoc#249）。

```bash
# 列出每個帶 w14:paraId 的段落與類型（stdout：paraId<TAB>類型<TAB>前 30 字）
macdoc word form classify filled.docx

# 整理（輸出已存在時預設拒絕，要 --force）
macdoc word form apply filled.docx --to-docx final.docx \
  --field <paraId> --field <paraId> [--field-size 12] \
  --checkbox-font 標楷體 --tick-list <paraId> \
  --insert-after <paraId>=<文字> --remove <paraId> --truncate-from <paraId>
```

`classify` 的前 30 字裡，tab、換行與其他控制字元都換成空白。`word/numbering.xml` 不是合法 XML（以 XML parser 判定）時，只停用 `list-checkbox` 判定，其餘照常列出，stderr 會說明；`word reverse --slot` 遇到同樣情況也會印同一行說明。

類型是封閉列舉，依結構判定（依序取第一個符合的）：`list-checkbox`（段落自己的 `w:numPr` 指到的清單層級文字是方框）、`checkbox-line`（段落文字含 □ ■ ☐ ☑ ☒）、`table-field`（最近的容器是表格儲存格；穿過內容控制項計算，儲存格裡文字方塊內的段落不算）、`body`（其餘）。**提示行不是類型**——「說明：」這類段落結構上和內文一樣，只能用 `--remove` 明確點名。

| 選項 | 做什麼 | 什麼情況拒絕 |
|------|--------|-------------|
| `--field <paraId>` | 去掉段落樣式與縮排、靠左、段落標記與每個 run 同一字級、所在儲存格垂直置中、刪同格的空段落（只有空 run 與 `w:proofErr` 才算空；書籤、修訂、欄位、圖等都算內容；被其他選項點名的段落不刪；格內有巢狀表格或內容控制項時不刪）。字級與字型插在 `w14:` 等擴充元素之前 | 段落不在儲存格內（文字方塊裡的段落即使方塊在儲存格中也拒絕） |
| `--field-size <pt>` | 填寫欄字級，0.5 為單位；省略時取指定欄位字級的眾數、同票取大，選定值印在 stderr | 不是 1–1638 之間 0.5 的倍數；省略時指定欄位都沒有明確字級；沒有搭配 `--field`（用法錯誤） |
| `--checkbox-font <字型>` | 全文只含一個 `w:t` 的 run 裡的方框拆成獨立 run，四種 script 都用該字型，其他格式（含字級，所以各方框仍是原本的大小）保留；另含其他內容、需要拆開卻帶有格式修訂（`w:rPrChange`）、或在原生核取方塊內容控制項（`w14:checkbox`）裡的 run 不動並在 stderr 計數 | 字型名稱空白 |
| `--tick-list <paraId>` | 方框是清單符號時（文字 slot 換不到）：拿掉清單編號，前面加 ■，格式取第一個有文字的 run；清單層級帶來的縮排與符號後的間隔不保留 | 段落沒有自己的 `w:numPr`，或 `w:numId` 是 0 |
| `--insert-after <paraId>=<文字>` | 在錨點後插入一段，沿用錨點的段落格式（去掉清單編號、分節符、段前分頁、修訂標記）與第一個有文字的 run 的格式；同一錨點多次依序接續；文字裡的換行與 tab 照字面寫入 | 文字含 XML 1.0 不允許的字元 |
| `--remove <paraId>` | 刪除段落 | 儲存格（或文字方塊）唯一的段落；刪掉後儲存格會以表格結尾；帶分節符的段落。儲存格的段落數穿過內容控制項（`w:sdt`）與 `w:customXml` 計算 |
| `--truncate-from <paraId>` | 從本文這一段刪到結尾，被刪範圍裡第一個有效的分節設定（不含修訂歷史裡的舊設定）成為本文最後的分節設定；保留內容最後一段自己帶分節符時（從某一節的第一段截斷），改用那個分節設定，不留下空白的最後一節 | 不是 `w:body` 的直屬段落；是本文第一個元素 |

**全有全無**：所有 paraId 先對照原檔驗過（恰好一個 `w:p` 帶它）；被 `--remove` 的段落又被其他選項點名、被點名的段落位在要刪的段落裡（例如文字方塊）、或落在 `--truncate-from` 會截掉的範圍內，都整次拒絕。輸出已存在時預設拒絕；不支援排他 rename 的磁碟（exFAT、FAT）改用「存在檢查 + rename」，指向不存在目標的 symlink 也算已存在；暫存檔寫在輸出目錄旁權限 0700 的暫存資料夾裡，輸出檔沿用輸入檔的權限。之後依固定順序執行 field → tick-list → insert → checkbox-font → remove → truncate；任何一步失敗（包括前一步讓後一步的條件不再成立）都整次不寫檔，輸出路徑維持原狀。`word reverse --slot` 在 full-fidelity 模式下會為 `table-field`、`checkbox-line`、`list-checkbox` 的 slot 各印一行 note，指出對應的選項。MCP（che-word-mcp）目前沒有這些操作（PsychQuant/che-word-mcp#300）。已知限制：只認 □ ■ ☐ ☑ ☒ 五個方框字元，符號字型（如 Wingdings）私用區的方框不算；沒有 `w14:paraId` 的段落無法點名；整張表的預設套用與刪除中間的整張表尚未支援，`--remove` 刪掉兩張表之間唯一的段落會讓 Word 把兩張表併成一張（PsychQuant/macdoc#250）；同格有內容控制項時空段落清理會略過、帶編號的空段落仍會被當成空段落、截斷可能留下不成對的書籤或註解範圍（PsychQuant/macdoc#253）。

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

`detect` 只覆寫偵測到的三個欄位（`available`／`transcription`／`agent`），不會動 `config ocr` 的設定（CLI 0.12.0+；更早的版本會把 OCR host／model 打回預設值）。三個子命令都支援 `--config <path>` 指向別的設定檔。

### config ocr — OCR host/model 設定（v1.1+）

| 子命令 | 用途 |
|--------|------|
| `list` | 顯示目前 OCR 設定（含 profile 列表） |
| `add-host <name> <addr>` | 新增/更新 host profile |
| `remove-host <name>` | 移除 profile |
| `set-default <name>` | 設定預設 host |
| `set-model <model>` | 設定預設模型（如 glm-ocr） |
| `set-backend <ollama\|mlx>` | 設定預設後端 |

**誰會讀這些設定**：`pdf ocr`，優先序一律是「明確的 flag > `config ocr` > 內建預設」。

- `--mode`（CLI 0.12.0+）：沒給時用 `set-backend` 設定的值（`mlx` 即 `local`），都沒設時用 `local`。只認經由 `set-backend` 設定的值；`list` 在未設定時顯示「未設定」。設定檔讀不到或值無法辨識時退回 `local` 並在 stderr 警告；不合法的 `--mode` 值會報錯。
- `--host`／`--model`（CLI 0.11.0+）：只在 `--mode ollama` 時讀這裡的預設 host 與 model。明確給 `--mode local` 時完全不讀設定檔。

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

### config document — 文件格式 profile（CLI 0.9.0+）

與 che-word-mcp 4.1.0+ 共用 `~/.config/macdoc/config.json` 的 `document` 區段。

```bash
macdoc config document show                                   # defaultProfile 與已匯入的快照
macdoc config document import-official --template 範本.dotx    # 匯入安全格式快照；不改預設值
macdoc config document set-default official                    # 之後新建的文件預設套用 official
macdoc config document gc                                     # 列出未被引用的舊快照（只預覽，CLI 0.10.0+）
macdoc config document gc --force                             # 實際刪除；被引用的快照永遠不碰
```

| profile | 意思 |
|---------|------|
| `inherit` | 沿用文件自己的格式（新文件只去掉程式產生的預設字型）|
| `official` | 套用匯入的範本快照：styles、section、theme、fonts；**不帶正文、不改原範本** |

**何時會讀設定檔**：新文件（`convert --to docx`）未給 `--profile` 時才退回 `defaultProfile`；
既有文件與腳本重播（`word render`）只有明確給 `--profile` 才套用。省略 `--template` 時讀目前
帳號 Word 的 Normal.dotm。快照缺失或損毀會直接報錯，不會靜默退回 inherit。

每次 `import-official` 都會寫一份新的不可變快照；舊的不再被引用，但會一直留在 `profiles/`。
`gc` 預設只列出這些快照，加 `--force` 才刪除；設定檔損毀、無法判定引用時，會在刪除任何東西之前失敗。

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

- **1.10.0**：`word reverse --paragraphs-only` 改用 ooxml-swift 的共用實作（與 che-word-mcp 一致）；讀寫 Word 文件時保留未建模的段落屬性（`w:kinsoku`、`w:snapToGrid` 等）、非 UTF-8 宣告的 part 正確轉碼、依 relationship 找格式 part（需要 CLI 0.13.0）
- **1.10.1**：typed 編輯後段落框線與網底不再消失、段落屬性依 schema 順序寫出；CLI 與 che-word-mcp 4.4.0 用同一版 ooxml-swift（需要 CLI 0.13.1）
- **1.13.0**：安全修正——讀入 .docx 時的圖片路徑穿越，惡意文件不能再經 marker 轉換寫出本機檔案；同時帶進解壓大小上限與多項 typed 重寫修正（需要 CLI 0.16.0）
- **1.12.0**：`docx apply` 的 `set_bold` 依 `substring` 只加粗該段文字（過去一律失敗）；同時帶進表格格式保留與 typed 重寫的多項修正（需要 CLI 0.15.1）
- **1.11.0**：`docx apply` 改為認證式交易：通過 Layer 1 關卡與 `verify` 才寫出輸出，失敗時輸出路徑不動（**BREAKING**）；新增 `--certificate` 寫出證書 JSON（需要 CLI 0.14.0）
- **1.10.2**：`docx apply` 不再刪除或重寫未觸及的 part（主題、註腳、尾註等），修正會讓真實文件遺失格式的問題（需要 CLI 0.13.2）
- **1.9.0**：`convert` 的輸出接 pipe 時不再 exit 1；`pdf ocr` 沒給 `--mode` 時採用 `config ocr set-backend` 的值；`config ai detect` 不再洗掉 OCR 設定；新增 `pdf migrate-figures`（0.4.0 前的舊專案重新裁切成帶頁碼的圖檔名，不呼叫 AI）；旋轉頁的渲染修正（需要 CLI 0.12.0）
- **1.8.0**：`pdf ocr --mode ollama` 會讀 `config ocr` 的 host／model；SRT／note 轉 HTML 不帶 `--css` 時預設 `dark`；`pdf normalize` 會依 PDF 的 page labels 還原頁碼、為偶數頁起始的章節加 `openany`、圖寬改為原書絕對尺寸（需要 CLI 0.11.0）
- **1.7.0**：新增 `config document gc`（清理未被引用的格式快照）；`pdf normalize` 會還原原書頁碼與圖片比例並印出摘要（需要 CLI 0.10.0）
- **1.6.0**：新增 `config document`（文件格式 profile）與 `convert` / `word render` 的 `--profile`（需要 CLI 0.9.0）
- **1.1.0**：新增 `config ocr` 子命令組,支援具名 host profile(`--host kyle` 等),預設 host/model 可存 config
- **1.0.0**：初版
