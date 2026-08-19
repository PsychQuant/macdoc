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
| ⚠️ **版本** | 「失敗不破壞」與「預設拒絕覆寫」需要 macdoc CLI **0.7.0+**（**尚未發布**，最新 release 為 0.6.0）。MCP 面的對應行為已隨 che-word-mcp **4.0.0** 出貨 |
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

### 4. Render — 把腳本放回 docx

```bash
macdoc word render form.mdocx.swift --to-docx rebuilt.docx [--force]
```

MCP：`execute_script(script_path, output_path, overwrite?)`

**輸出路徑已有檔案時預設拒絕。** CLI 要 `--force`，MCP 要 `overwrite: true`。重跑同一個輸出路徑（改完 slot 值再 render 一次就是）一定會遇到——不是錯誤，是要你確認。

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

兩個最常見的落 raw 原因：

| 情況 | 結果 |
|------|------|
| 文件含**任一表格** | 整個 `word/document.xml` 落 raw |
| 段落沒有 `w14:paraId`（legacy 文件、部分工具產出）| 不具升級資格，落 raw |

實測兩個對照：

```
REC-O-01 官方表單（115 個 paraId，但有 1 個表格）
  → Aggregate: 0.0% DSL (0 / 190479 bytes across 16 parts)
  → 產出 24 行 / 212 KB，document.xml 那一行約 118 KB

macdoc convert 產的 2 段落簡單文件（0 個 paraId）
  → Aggregate: 0.0% DSL (0 / 8572 bytes across 9 parts)
```

**兩個最直覺的輸入都是 0.0%。** 所以：

- 表格密集的官方表單 → **一定**是 raw。拿到的是「穿著 Swift 語法的 byte-equal 封存檔」
- 它能完美重播、能填 slot、能驗證——**但不能讀、不能手改**
- **版控 diff 對 raw 腳本沒有意義**：改一個字會讓那條 118 KB 的單行整條重新 escape，diff 顯示「一行變了」

如果你的目的是「產生人類可讀的 Swift 文件原始碼」，raw channel 的文件**達不到**，而且這不是設定問題——需要 ooxml-swift 支援 rich table 的 typed 表示與 sub-part 局部降級，兩者目前都不存在。

## 典型情境：以官方範本定點填寫

```bash
# 1. 先看落在哪條 channel（決定期待值，不決定可不可用）
macdoc word reverse 範本.docx --to-mdocx 範本.mdocx.swift --coverage

# 2. 指定要填的位置
macdoc word reverse 範本.docx --to-mdocx 範本.mdocx.swift \
  --slot 申請人=<paraId> --force

# 3. 改腳本裡的 slot 參數值，然後重建
#    （改一次 slot 值就重跑一次，第二次起輸出檔已存在 → 要 --force）
macdoc word render 範本.mdocx.swift --to-docx 已填.docx --force

# 4. 驗證「除了填的地方，其餘與範本逐位元組相同」
macdoc word render 範本.mdocx.swift --to-docx 重建.docx --verify-against 範本.docx --force
```

第 4 步是這個工作流的核心價值：**證明**你只動了該動的地方。即使腳本本身不可讀（raw channel），這個保證依然成立。

## 相關

- [`macdoc`](../macdoc/SKILL.md) skill — `word reverse` / `word render` 的命令與選項參考
- che-word-mcp skill — 三個 MCP 工具的參數與回傳格式參考

本 skill 管**工作流**（照什麼順序做、怎麼判讀、能期待什麼）；那兩份管各自面的**命令/工具參考**。要查某個選項怎麼寫，去那兩份。
