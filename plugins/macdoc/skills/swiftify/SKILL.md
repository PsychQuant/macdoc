---
name: swiftify
description: |
  把 .docx 變成可重播的 .mdocx.swift 重建腳本、再放回 .docx 的完整工作流。
  用於需要「可重現、可驗證」的文件變更：以官方範本為 immutable template
  定點填寫、每次產出都能對照原檔做 byte-equal 驗證。
  同時涵蓋 CLI（macdoc word reverse / render）與 MCP
  （export_script / get_script_coverage / execute_script）兩個面。
  觸發詞：「swiftify」「docx 轉 swift 腳本」「.mdocx」「重建腳本」
  「文件變更要可重播」「byte-equal 驗證」
---

# swiftify — 把文件變成可重播的腳本

## 這是什麼

一個封閉迴路：**docx → `.mdocx.swift` 腳本 → docx**，且可以證明繞完一圈之後每個 XML part 與原檔逐位元組相同。

用途是把「對文件做了什麼」變成一個**可版控、可重跑、可驗證**的產物，而不是一串當場拼湊、事後無法重現的編輯動作。

## 先講清楚它保證什麼

| | |
|---|---|
| ✅ **保證** | byte-equal 重播。驗證通過 = 重建出的每個 XML part 與參考檔逐位元組相同 |
| ✅ **保證** | 具名 slot 填寫。指定的段落換成新內容，其餘部分逐字不動 |
| ⚠️ **版本** | 「失敗不破壞」與「預設拒絕覆寫」需要 macdoc CLI **0.7.0+**（MCP 面：che-word-mcp **4.0.0+**）。**raw-channel slot**（第 3 步的 `// @slot-raw`）需要 CLI **0.8.0+**（MCP 面：che-word-mcp **4.0.6+**）；CLI 0.7.0 的 render 實測不會報錯，而是輸出沒填值的模板（更早的 CLI 與 che-word-mcp 4.0.6 以前沒有實測）|
| ✅ **保證** | 失敗不破壞。驗證沒過就什麼都不寫出——輸出路徑上原本有檔就原封不動，原本沒檔就不會憑空出現 |
| ❌ **不保證** | 產物可讀。**任何輸入都不保證**產出人類可讀、可手改的 Swift |

第三點是這個工具最容易被誤解的地方，下面「判讀 coverage」會講為什麼。

## 完整迴路

每一步都列 CLI 與 MCP 兩個入口，任一面都能單獨走完。

### 1. Export — 把文件變成腳本

```bash
macdoc word reverse form.docx --to-mdocx form.mdocx.swift
```

MCP：`export_script(source_path, output_path)`

### 2. Coverage — 判讀落在哪條 channel（**不要跳過這步**）

```bash
macdoc word reverse form.docx --to-mdocx form.mdocx.swift --coverage
```

MCP：`get_script_coverage(source_path)`

上面這種同時提供 `--to-mdocx` 的 coverage 形式可用於正式 CLI v0.7.0；只給 `--coverage`
而不產出腳本的 coverage-only 形式，以及具名根因的新提示，仍屬未發布的本機開發版行為。
v0.7.0 的 channel／百分比輸出不能指出 raw 的確切原因。

輸出長這樣：

```
word/document.xml                 raw  117994 B   DSL 0.0%
...
--- Aggregate: 0.0% DSL (0 / 190479 XML bytes across 16 parts) ---
```

**這一步決定你對產物的期待值。** 判讀方式見下一節。

### 3. Slot — 指定要換內容的位置（選用）

```bash
macdoc word reverse form.docx --to-mdocx form.mdocx.swift \
  --slot applicant=<paraId> --slot title=<paraId>
```

MCP：`export_script(..., slots: [{name, para_id}])`

指定的段落成為腳本的具名參數，其餘部分逐字重建。**strict mode**：paraId 不存在、名稱不合法、重複指定都直接報錯且不寫檔，不會靜默降級。

`paraId` 是段落的 `w14:paraId` 屬性值，可用 che-word-mcp 的讀取工具找出來。

**Raw channel 文件（例如含不支援的 rich／foreign-form 表格之官方表單）的 slot 同樣可用**（raw-channel-slot-support，#171 後；僅 `word/document.xml` 主 part——headers/footers 的 raw slot 不支援）：段落改以 paraId 在 carried XML 內定位，腳本出現 `// @slot-raw <name> <paraId>` directive。

> ⚠️ **raw-channel slot 需要 macdoc CLI 0.8.0+，或 che-word-mcp 4.0.6+。** CLI 0.7.0 的 export 與 render 表現不一樣（以 0.7.0 與 0.8.0 兩個官方 release binary 實測，見 PsychQuant/macdoc#198）：export（`reverse --slot`）會直接報錯，說找不到段落；**render 不會報錯**，它把 `// @slot-raw` 當成一般註解略過，照樣印「已寫入」、exit 0，但輸出的是**沒填值的模板**（PsychQuant/macdoc#198）。che-word-mcp 4.0.6 以前的 `execute_script` **沒有實測過**；它和 CLI 用的是同一個 ooxml-swift importer，推測也一樣沉默，但未經驗證。腳本和 render 用的 binary 不一定是同一版，所以填官方表單之前先確認 `macdoc --version`；render 完成後用下面最後一點的方式核對填入的值確實在文件裡。

四個行為細節：

- **替換語意是「坍縮為主 run」**：段落的 pPr（對齊、縮排等段落格式）保留，段內**所有其餘子內容**——多個 run、書籤錨點、超連結、內容控制項、修訂範圍標記——坍縮成一個 run，格式取文字最長那個 run 的 rPr（含藏在 hyperlink 等 inline 包裝內的 run）。段內局部格式（例如只有一個字有底線）不會保留。表單填寫場景這正是要的行為；要保留 run 級混排格式或段內錨點的文件不適用 slot。
- **Default 重播恆 byte-equal**：slot 值等於原文字時完全不動該 part（identity shortcut），所以第 5 步的 `--verify-against` 驗證照常成立，不需要任何新驗證模式。
- **三個 refuse 情境**：paraId 在 DSL log 與 raw part 都找不到（錯誤訊息指出兩個查找域）；paraId 由超過一個 `<w:p>` 承載（直接拒絕、不猜第一個）；paraId 存在但不在段落上（Word 也會把 `w14:paraId` 寫在表格列 `<w:tr>` 上——錯誤訊息會指出實際承載元素）。填錯官方表單欄位比失敗更糟。
- **填值後輸出的保證邊界**：`--verify-against` 驗的是「腳本本身」（all-default 重播 byte-equal）；填了新值的輸出**不可能**過全包 byte-equal（值變了）。填值輸出的保證來自 render 本身：替換後會做 XML well-formedness 檢查，失敗直接報錯、不寫檔——render 成功即保證輸出是 well-formed 的 OOXML。要人工核對填了什麼，用 che-word-mcp 的 `compare_documents` 對照原檔。

### 4. Render — 把腳本放回 docx

```bash
macdoc word render form.mdocx.swift --to-docx rebuilt.docx [--force]
```

MCP：`execute_script(script_path, output_path, overwrite?)`

**輸出路徑已有檔案時預設拒絕。** 只有先檢查精確輸出路徑，並取得使用者對覆寫該檔案的明確事前同意，才可在 CLI 加 `--force` 或在 MCP 傳 `overwrite: true`；否則改用新的輸出路徑。不得自動加上覆寫選項。

> **命名注意**：同一個操作在兩個面的名字不同——CLI 是 **`render`**，MCP 是 **`execute_script`**。MCP 那個名字是已發布 tool schema 的一部分，CLI 的名字由 `mdocx-grammar` spec 固定，所以兩邊都不動。底層是同一個實作。

### 5. Verify — 對照參考檔驗證（**預設不驗**）

```bash
macdoc word render form.mdocx.swift --to-docx rebuilt.docx --verify-against form.docx
```

MCP：`execute_script(..., verify_byte_equal_against: "form.docx")`

驗證通過 → CLI exit 0 並印 `byte-equal 驗證通過`；不符 → exit 非零並列出不符的 part。

**驗證失敗什麼都不寫出。** 重建結果先寫到輸出檔同目錄的暫存路徑，驗過才搬進位——所以不符時輸出路徑保持原狀，CLI 也不會印「已寫入」。驗證不是對一份已經發布的文件做的事後檢查。

**MCP 這邊，驗證失敗是 tool error，不是回應欄位。** `verified: false` 不會出現在成功回應裡；不符時整個 tool call 失敗，錯誤文字列出不符的 part。所以不要去 inspect 回應裡的 verdict 來判斷失敗——失敗根本不會給你回應。

**沒給參考檔就不會驗，也不會有任何驗證輸出。** MCP 這邊對應的是：回應**不會有** `verified` / `broken_parts` 欄位。只檢查 `broken_parts` 是否為空的 client 會把「沒驗」讀成「驗過且乾淨」——要判斷驗證結果，先確認 `verified` 欄位存在。

## 判讀 coverage：為什麼你的腳本可能不可讀

腳本有兩條 channel：

- **typed DSL** — 可讀的 Swift（`Paragraph(id:) { "文字" }` 這種）
- **raw** — 整個 XML part 被 JSON-escape 塞進**一行** `// @op`

**DSL 升級是 per-part 全有全無，不是逐段降級。** 一個 part 裡只要有任何一處無法用 typed 形式 byte-equal 地重建，**整個 part** 就落到 raw。

以下是**非窮舉**的常見情況與處置表，不是 CLI 會逐項列出的 raw 根因目錄。目前未發布的
CLI 新提示只會具名指出 `word/document.xml = paragraph-no-paraId`；`table`、`byte-mismatch`、
`parse-error` 是用來說明內部判定與處置差異的分類，不會各自印在 CLI 報告中。只看到
`Aggregate: 0.0% DSL` 也無法反推出是哪一類原因。

| 根因／模式 | 可讀 DSL／slot | 保真與限制 |
|---|---|---|
| 預設 full-fidelity，缺 paraId | `document.xml` 走 raw；缺真 paraId 的位置不能直接 raw-slot 定位 | 保留全部內容，維持 byte-equal 目標 |
| 缺 paraId，明確選 `--paragraphs-only` | 產生段落 DSL，合成 `p1`、`p2`…，可指定 slot | 省略非段落內容；不保證 byte-equal，版面與格式也不保證完整 |
| 明確選 `--paragraphs-only`，且文件含**任一表格** | 只產生段落 DSL，表格一律省略，不能當成完整文件的替代方案 | 僅在接受捨棄全部表格與其他非段落內容時使用 |
| full-fidelity 遇到 canonical minimal table | 可用 `appendTable` 表示，具備 typed DSL 升級資格 | 仍須整個 part 的其他內容都受支援，且試重建通過 byte-equal；不能只因表格簡單就保證整個 part 走 DSL |
| full-fidelity 遇到不支援的 rich／foreign-form table | 該表格無法轉成 typed DSL，可能以 `table` 原因讓整個 `document.xml` 落 raw | raw 仍保留完整內容與 byte-equal 目標 |
| byte-mismatch／parse-error | 不能由根因名稱推定 `--paragraphs-only` 適用 | 保留 full-fidelity，依實際重建或解析失敗另行調查 |

歷史樣本與本次可重現合成案例必須分開判讀：

```
歷史樣本：REC-O-01 官方表單（115 個 paraId，但有 1 個表格）
  → Aggregate: 0.0% DSL (0 / 190479 bytes across 16 parts)
  → 產出 24 行 / 212 KB，document.xml 那一行約 118 KB

本次可重現合成案例：直接建立一份不帶 paraId 的純段落 docx
  → 預設 full-fidelity 回報 paragraph-no-paraId
  → --paragraphs-only 產生 Paragraph(id: "p1")，可再指定 --slot body=p1
```

歷史樣本的百分比只描述該份檔案，不能套用到同一工具產生的其他 docx。處理方式取決於實際根因：

- `--paragraphs-only` 遇到**任何表格都會省略**，所以不能作為含表格文件的完整替代方案。
- full-fidelity 能將 canonical minimal table 表成 `appendTable`；但整個 `document.xml` 是否升級為 DSL，仍取決於所有內容都可表示且試重建 byte-equal。rich／foreign-form table 不受支援時，才可能以 `table` 原因讓整個 part 落 raw。
- 對確實落 raw 的文件，腳本仍能完美重播、能填 slot（`// @slot-raw`，paraId 定位；替換採「坍縮為主 run」語意，見上面 Slot 一節）、能驗證——**但除了 call-site 的 slot 參數值外不能讀、不能手改**（改 slot 值正是設計內的唯一手改點）。
- **版控 diff 對 raw 腳本沒有意義**：改一個字會讓那條大型單行重新 escape，diff 顯示「一行變了」。

只有在檢視文件來源與實際內容、確認唯一根因是 `word/document.xml = paragraph-no-paraId`，而且接受只保留段落時，才可明確改走 paragraphs-only。不能只由 CLI 的 raw／0% 摘要推定；即使開發版具名提示該原因，也要確認非段落內容可捨棄。無法確認時保留 full-fidelity，不把其他原因類推成 lossy 模式。診斷與相容路徑依 CLI 版本不同：

```bash
# 本機開發版：須確認同時包含 #176 的 paragraph-no-paraId 提示與 #177 的 coverage-only 支援
macdoc word reverse legacy.docx --coverage

# 正式 v0.7.0：不支援上面的 coverage-only，也不會顯示新版根因資訊。
# 若已從文件來源或檢查結果確認它是可捨棄非段落內容的 legacy 純段落文件，
# 可直接走 v0.7.0 已支援的明確替代路徑。
macdoc word reverse legacy.docx --paragraphs-only --to-mdocx legacy.mdocx.swift

# 讀過 legacy.mdocx.swift、確認實際段落 ID 是 p1 後才指定 slot；不可猜 ID
macdoc word reverse legacy.docx --paragraphs-only \
  --slot body=p1 --to-mdocx slot.mdocx.swift
```

paragraphs-only 產物省略其他內容，不應承諾對原檔通過 `--verify-against`，也不保證版面或格式完整。以上兩個輸出路徑不同，只能避免兩條範例彼此撞檔；重跑其中任一條仍會被預設拒絕，必須換新輸出路徑，或先取得使用者同意才加 `--force` 覆寫。

> **發布狀態**：`--paragraphs-only` 與帶 `--to-mdocx` 的 coverage 是 CLI 0.7.0 已有功能；coverage-only、coverage 中具名的 `paragraph-no-paraId` 說明，以及預設 reverse 偵測到同一原因時寫入 stderr 的提示，尚未隨正式 CLI 發布。這些新提示不代表 CLI 會逐項印出其他內部分類。完整診斷流程需使用包含 #176、#177 與 #181 相應變更的本機開發版。plugin 的 `binary_version` 仍固定為已發布的 0.7.0。

若經核心分析確認內部分類是 `table`，表示表格超出目前可轉成 `appendTable` 的 canonical minimal shape；保留完整內容時該 part 走 raw，而 `--paragraphs-only` 會直接省略表格。即使表格符合 canonical minimal shape，也必須等整個 part 通過試重建，才能確認走 DSL。若分析確認是 byte-mismatch 或 parse-error，則須依實際重建差異或解析錯誤調查；不能把它們一概歸因於表格，也不能只靠 CLI 的 0.0% 判定。

## 典型情境：以官方範本定點填寫

下列範例全部使用新的輸出路徑，所以不需要 `--force`。若其中任何精確路徑已存在，先改用
另一個新路徑；只有在檢查該路徑並取得使用者對覆寫該檔案的明確事前同意後，才可為那一條
命令加上 `--force`，不得自動覆寫。

```bash
# 0. 確認版本：文件落在 raw channel 時（含複雜表格的官方表單常見；以第 1 步的 coverage
#    或腳本裡是否出現 `// @slot-raw` 為準），slot 需要 0.8.0+。
#    0.7.0 的 render 不會報錯，而是輸出沒填值的模板（見第 3 步 Slot 一節的警告框）
macdoc --version

# 1. 先看落在哪條 channel（決定期待值，不決定可不可用）
macdoc word reverse 範本.docx --to-mdocx 範本-coverage.mdocx.swift --coverage

# 2. 指定要填的位置
macdoc word reverse 範本.docx --to-mdocx 範本-slot.mdocx.swift \
  --slot applicant=<paraId>

# 3. 先驗腳本：default 值重播必須與範本逐位元組相同
#    （這一步在「改值之前」做——它證明的是腳本本身）
macdoc word render 範本-slot.mdocx.swift --to-docx 重建-驗證.docx --verify-against 範本.docx

# 4. 改腳本裡的 slot 參數值，然後重建出已填表單
#    （每次重建先選新的輸出路徑；覆寫必須另行取得精確同意）
#    「已寫入」只代表寫出了檔案，不代表值有填進去——一定要做下面的核對
macdoc word render 範本-slot.mdocx.swift --to-docx 已填-1.docx
```

第 3 步是這個工作流的核心保證：default 重播 byte-equal **證明**腳本除了 slot 之外逐位元組重建範本。第 4 步（填了新值）的輸出**不會**過 `--verify-against`——值變了，全包 byte-equal 必然不同；它的保證來自 render 本身：raw channel 的替換做完會驗 XML well-formedness，指定段落以外的 bytes 由第 3 步已證的腳本結構背書。要人工核對填了什麼，用 che-word-mcp 的 `compare_documents` 對照範本。

## 相關

- [`macdoc`](../macdoc/SKILL.md) skill — `word reverse` / `word render` 的命令與選項參考
- che-word-mcp skill — 三個 MCP 工具的參數與回傳格式參考

本 skill 管**工作流**（照什麼順序做、怎麼判讀、能期待什麼）；那兩份管各自面的**命令/工具參考**。要查某個選項怎麼寫，去那兩份。
