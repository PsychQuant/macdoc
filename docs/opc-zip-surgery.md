# OPC ZIP 手術：VBA 注入與保真契約

> 狀態：#135 `che-excel-mcp` 離線 `inject_vba` 能力的設計依據
>
> 適用範圍：以受信任的 VBA carrier 將一般 `.xlsx` 轉為 `.xlsm`
>
> 來源：PsychQuant/macdoc#136；document-module 綁定陷阱見
> PsychQuant/macdoc#138

## 1. 核心原則

`.xlsx` 與 `.xlsm` 都是 OPC ZIP package。巨集注入不需要先開啟 Excel，也不應把
整份活頁簿交給另一套文件模型重寫；它只應修改明確列入契約的 package parts，並
保留其餘 ZIP entry 的**解壓後 payload bytes**。

這裡有兩種不可混稱為「保真」的模式：

| 模式 | 負責的事 | 可主張的保證 |
|---|---|---|
| 離線 OPC 手術 | 精準修改 package、加入 VBA binary、補宿主綁定 | 未觸碰 entry payload byte-identical；預期 XML 可逆 |
| 活 Excel 開啟／另存 | 重算、執行巨集、讓 Excel 驗證與重寫文件 | 功能與 Excel 相容；不保證 ZIP entry 或 XML bytes 不變 |

ZIP central directory、壓縮層級、時間戳或 entry 順序可能因封裝工具重建而改變；因此
「整個 `.xlsm` 檔案的 bytes 等於某個預期 ZIP」不是本契約。保真比較的單位是 entry
名稱集合與每個 entry 的解壓後 payload。

## 2. `.xlsx → .xlsm` 的 package delta

### 2.1 固定三項

一般 `.xlsx` 轉成含 VBA project 的 `.xlsm`，固定需要以下三項變更：

| Part | 變更 |
|---|---|
| `[Content_Types].xml` | 將 `/xl/workbook.xml` 的 main content type 改成 `application/vnd.ms-excel.sheet.macroEnabled.main+xml`，並宣告 `bin` 為 `application/vnd.ms-office.vbaProject` |
| `xl/_rels/workbook.xml.rels` | 新增 type 為 `http://schemas.microsoft.com/office/2006/relationships/vbaProject`、target 為 `vbaProject.bin` 的 internal relationship |
| `xl/vbaProject.bin` | 加入與受信任 carrier asset 完全相同的 binary payload |

實作者不得假設固定 `rId`；relationship ID 必須在現有集合中唯一。若 package 已有
VBA relationship、VBA part，或既有 `.bin` Default 使用不同 content type，第一版
應 fail-loud，不得靜默覆寫或重新分類其他 binary parts。替換既有 VBA project 必須
是另一個有明確驗收的操作模式。

### 2.2 條件式宿主綁定

「固定三項」只描述 package 最小差異，不代表每個來源活頁簿都只需改三個 parts。
只要 carrier 的 VBA project 含 document modules，注入器還必須讓宿主 XML 的
`codeName` 與 carrier binding manifest 一致：

| VBA project 宣告 | 宿主綁定 |
|---|---|
| workbook document module，通常為 `ThisWorkbook` | `xl/workbook.xml` 的 `<workbookPr codeName="ThisWorkbook"/>` |
| worksheet document module | 對應 `xl/worksheets/sheetN.xml` 的 `<sheetPr codeName="…"/>` |

這些是**條件式 delta**。如果來源 XML 已有相同綁定，就不應改寫；若缺少，才做
窄幅插入；若現值衝突或 manifest 無法完整對映，必須停止並回報衝突。

`codeName` 不是使用者在頁籤看到的 sheet name。工作表必須透過
`xl/workbook.xml` 的 sheet relationship ID、workbook relationships 與 manifest
對映到實際 worksheet part；不得用頁籤順序或顯示名稱猜測。manifest 至少要記錄：

- workbook document-module code name；
- 每個 document module 對應的 worksheet part 與 code name；
- carrier `vbaProject.bin` 的 SHA-256；
- 產生 carrier 的來源活頁簿與文字模組版本。

寫入 XML 時有三項結構要求：

1. 既有 `workbookPr`／`sheetPr` 要保留其他屬性與未知子節點，只更新 `codeName`。
2. 元素不存在時要依 SpreadsheetML schema 順序插入。
3. 每個容器最多只能有一個 `workbookPr` 或 `sheetPr`；不得用 regex 直接附加而產生
   duplicate elements。

## 3. document-module 綁定為何會靜默失敗

carrier 的 `vbaProject.bin` 內含 VBA project stream。實戰 carrier 的 `PROJECT`
stream 宣告了 `ThisWorkbook` 與 worksheet document modules；如果宿主 XML 沒有
對應 `codeName`，Excel 雖然仍可能列出一般巨集，document object 卻無法正確解析。

這個錯誤特別危險，因為三個現象會疊在一起：

1. VBA 的 `On Error` handler 可能吃掉 runtime error 429，讓使用者只看到 no-op。
2. Mac Excel 的 AppleScript `run VB macro` 對無法解析或不存在的巨集可能回傳成功，
   所以 process exit status 不能證明巨集執行過。
3. 若測試資料原本就等於預期輸出，「結果正確」也無法區分成功與完全沒執行。

因此 `inject_vba` 的完成條件不能只有「Excel 可開啟」、「巨集出現在清單」或「命令
沒有報錯」。宿主綁定必須先由離線結構檢查證明，功能驗收還必須觀察狀態改變。

## 4. `vbaProject.bin` 的來源與供應鏈

`vbaProject.bin` 是含 OLE streams、壓縮來源與編譯產物的專有容器。本專案不把它
視為可由任意文字即時可靠生成的檔案，也不從不受信任的活頁簿抽出後直接重用。

建議的受控產製流程是：

1. 以版本控制中的文字模組作 source of truth；標準 module 使用 `.bas`，需要時另存
   `.cls`／`.frm` 與資源。
2. 文字來源採可預測的 ASCII policy；非 ASCII 顯示文字用 `ChrW` 等明確組合，避免
   VBE legacy code page 把多位元組尾碼與引號誤判在一起。
3. 由明確版本的真實 Excel 將來源匯入受控 carrier 活頁簿，編譯後另存 `.xlsm`。
4. 從 carrier 抽出 `xl/vbaProject.bin`，同時產生 binding manifest。
5. 將文字來源版本、Excel 版本、carrier digest、binary digest、manifest 與產製日期
   一起保存；binary 是 build artifact，不取代文字來源。

任何 VBA 邏輯或 document-module 組成變更，都必須重走產製與驗證流程。已簽章的
VBA project、含密碼或不明保護的 carrier 不屬於第一版支援範圍。

## 5. 注入演算法的交易邊界

### 5.1 Preflight

在寫入任何資料前：

1. 計算來源活頁簿與 VBA asset digest，核對 caller 提供的 expected digest。
2. 驗證副檔名、OPC root parts、workbook main part 與 relationships 存在且唯一。
3. 拒絕 traversal、absolute／non-canonical path、duplicate entry、symlink entry、
   不安全 external relationship，以及超過 entry 數量、解壓總量、壓縮比、XML
   深度或節點數上限的 package。
4. XML parser 停用 DTD 與 external entities；未知 parts 保留但不執行。
5. 拒絕已加密、密碼保護、數位簽章或帶未知保護語意的輸入。
6. 驗證 carrier provenance、binary hash、binding manifest 與允許的 macro 清單。

### 5.2 Staging

1. 在目的檔案相同檔案系統建立不可預測名稱的 staging file。
2. 逐 entry 讀取來源；只有 allowed touched parts 進入專用 XML patcher，其餘 payload
   原樣複製。
3. 加入 `xl/vbaProject.bin`，並記錄每一筆實際 mutation 的 before／after bytes 與
   semantic assertion。
4. 完成 ZIP 後 fsync staging file，重新開啟並跑結構與 digest 驗證。
5. atomic replace 前再次比較來源 expected digest，若外部程式已更新檔案就拒絕 stale
   save；成功 replace 後同步目的目錄 metadata。

staging 驗證失敗不得改到來源或既有目的檔。若 caller 要保留來源，預設輸出到新的
`.xlsm` URL；覆寫模式必須另外明示。

## 6. Byte-level 保真驗收

對來源 snapshot 記錄 `entry name → SHA-256(uncompressed payload)`。注入後的契約如下：

### 6.1 Entry 集合

在不支援既有 VBA project 的第一版：

```text
output entries = input entries ∪ {xl/vbaProject.bin}
```

不應多出暫存檔、重複 entry 或未宣告 part。

### 6.2 Allowed touched parts

固定可改：

- `[Content_Types].xml`
- `xl/_rels/workbook.xml.rels`
- 新增的 `xl/vbaProject.bin`

只有 manifest 要求且來源缺少相同綁定時，才可再改：

- `xl/workbook.xml`
- manifest 列出的 `xl/worksheets/sheetN.xml`

所有其他 entry 的 payload bytes 與 digest 必須逐筆相同。

### 6.3 被修改 XML 的可逆性

每個 XML patch 都要有 typed patch manifest。驗收先確認輸出語意，再只撤回 manifest
列出的變更；撤回後的 XML bytes 必須與來源完全相等。這能抓到 formatter 順手改了
空白、attribute order、namespace、XML declaration 或其他無關節點的問題。

只比較 parse tree 不夠，因為它看不出非必要的 byte drift；只比較 bytes 也不夠，
因為它不能證明 relationship、content type 與 `codeName` 語意正確。兩種檢查都要做。

### 6.4 Binary 與結構

- 輸出的 `xl/vbaProject.bin` bytes 必須與已核准 asset 完全相同。
- package 重新開啟後必須只有一個 VBA part 與一條對應 internal relationship。
- workbook main content type、binary content type、relationship target 與所有 manifest
  綁定都必須精確吻合。
- offline 驗證完成後才可把副本交給 Excel 作功能驗收；Excel 另存後的 package 不再
  使用上述 byte-preserving 主張。

## 7. 巨集真的有執行：狀態改變驗收

功能驗收必須使用受控 fixture、受控 macro allow-list 與真實 Excel for Mac：

1. 先驗證活頁簿 identity、檔案 digest、巨集清單、VBE 非 break mode，且沒有 modal
   dialog。
2. 讀取挑戰輸入、輸出與 checksum，確認測試前置條件成立。
3. 將至少一個輸入改成會讓獨立 oracle 產生不同輸出的值。
4. 以 module-qualified 名稱執行允許的巨集；設定 timeout，任何 dialog 或失去目標
   workbook 都要 fail-loud。
5. 重新讀取輸出，斷言它確實改變，並逐格與獨立實作的預期結果比對。
6. 還原輸入後再執行一次，斷言輸出也復原。

以下都不是充分證據：AppleScript exit 0、巨集名稱可列出、Excel 沒跳錯誤、輸出
剛好等於測試前的預填值。

#138 記錄的歷史案例曾在 42,112 格中觀察到 310 格隨挑戰輸入改變，並與獨立計算
結果一致。這是失敗模式的實戰證據；在對應 fixture、oracle 與命令正式進入 repo 前，
不能把該數字當成可重現的自動驗收結果。

## 8. 巨集與應用程式安全

- **注入與執行分離**：離線 `inject_vba` 不啟動 Excel、不執行事件巨集。執行巨集是
  另一個需要使用者明示同意的操作。
- **三重身分核對**：執行前核對 workbook identity、當下檔案 digest 與 macro
  allow-list；任一項不同就停止。
- **不降低安全設定**：不得自動修改 Excel Trust Center、macOS TCC、VBE trust 或
  系統權限，也不得把安全提示當成要繞過的錯誤。
- **外部內容**：external links、DDE、OLE／ActiveX、XLM macro、事件巨集與網路存取
  預設拒絕；若未來要支援，必須有獨立威脅模型與逐次同意。
- **輸出語意**：離線手術產生結構標準的 `.xlsm`，不代表檔案可信。Excel 開啟時仍
  應套用原本的 Protected View、macro policy 與平台安全機制。

## 9. 平台與家族邊界

- 離線 OPC patcher 的設計可使用 ZIPFoundation 與 Foundation XML，不依賴 Python、
  LibreOffice 或 Excel runtime；第一個產品實作仍由 #135 定義與驗收。
- 活 Excel 驗收只承諾**互動式、單一使用者的 macOS 工作階段 + Excel for Mac**。
  它不是無頭、多租戶或遠端服務的安全邊界。
- `.docm` 與 `.pptm` 也屬 OPC，能借用「窄幅 patch + 未觸碰 payload byte equality」
  的方法；但它們的 main part、content type、relationships 與 document-module 綁定
  不同，沒有各自 fixture 與驗收前不得宣稱可直接平移。

## 10. #135 實作交接清單

`che-excel-mcp` 的 `inject_vba` 在進入 verify 前至少要有：

- [ ] typed request：來源／目的 URL、expected input digest、asset ID／digest、binding
      manifest、overwrite policy；
- [ ] hostile OPC preflight 與明確的 typed errors；
- [ ] fixed delta 與 conditional binding delta 的窄幅 XML patcher；
- [ ] entry-set、untouched payload、reverse-patch、binary 與結構驗收；
- [ ] same-filesystem staging、fsync、fresh reopen、generation check 與 atomic replace；
- [ ] 受控 fixture 的 macro-alive 狀態改變測試；
- [ ] 真 Excel integration gate 與缺少 Excel 時的明確 skip／fail policy；
- [ ] 文件化的平台、巨集授權與不支援封裝邊界。

## 非目標

- 不把 `vbaProject.bin` 當成文字來源，也不宣稱任意 VBA project 可由純 Swift 生成。
- 不以 Excel 另存取代 byte-preserving OPC 手術。
- 不以注入成功推論巨集可信或已執行。
- 不在本文件新增 `macdoc convert` 的 xlsx 路徑。
