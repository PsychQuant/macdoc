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

這三個 URI 是第一版刻意採用的 **canonical Excel layout profile**。preflight 必須從
package root relationship 解析 office document、再由 workbook relationships 解析每個
sheet，並確認實際 URI 正是這個 profile；合法但使用其他 part URI 的 OPC package
目前應回報 `unsupportedPackageLayout`，不得仍向寫死路徑寫入。實作者也不得假設固定
`rId`；relationship ID 必須在現有集合中唯一。

來源 workbook content type 必須是一般 `.xlsx` 的
`application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml`。若 package
已是 macro-enabled、已有 VBA relationship／part、已有 VBA content-type Override，或
既有 `.bin` Default 使用不同 content type，第一版應 fail-loud，不得靜默覆寫或重新
分類其他 binary parts。同樣要拒絕重複／衝突的 workbook Override，以及 TargetMode、
Target 或 type 不符與懸空的疑似 VBA relationship。替換既有 VBA project 必須是另一個
有明確驗收的操作模式。

### 2.2 條件式宿主綁定

「固定三項」只描述 package 最小差異，不代表每個來源活頁簿都只需改三個 parts。
只要 carrier 的 VBA project 含 document modules，注入器還必須讓宿主 XML 的
`codeName` 與 carrier module inventory 及本次 target binding 一致：

| VBA project 宣告 | 宿主綁定 |
|---|---|
| workbook document module，通常為 `ThisWorkbook` | `xl/workbook.xml` 的 `<workbookPr codeName="ThisWorkbook"/>` |
| worksheet document module | 對應 `xl/worksheets/sheetN.xml` 的 `<sheetPr codeName="…"/>` |

這些是**條件式 delta**。如果來源 XML 已有相同綁定，就不應改寫；若缺少，才做
窄幅插入；若現值衝突，或 inventory／target binding 無法完整對映，必須停止並回報衝突。

`codeName` 不是使用者在頁籤看到的 sheet name。工作表必須透過
`xl/workbook.xml` 的 sheet relationship ID 與 workbook relationships 對映到實際
worksheet part；不得用頁籤順序或顯示名稱猜測。這需要兩份不能混用的資料：

1. **Carrier module inventory** 跟 `vbaProject.bin` digest 綁定，記錄受控 asset ID／
   版本、workbook document-module code name，以及每個 module 的 kind、code name 與
   文字來源版本；另列出完整 callable／event procedure inventory，以及 prohibited
   auto／event entrypoint scan 的工具版本、source digest 與結果。不得保存使用者本機
   路徑。carrier 自己的 `sheetN.xml` URI 不能拿來決定另一份目標活頁簿的對映。
2. **Target binding** 由本次 caller 明示，將 inventory 中每個 worksheet module 一一
   對映到目標 workbook 裡的 sheet relationship ID／解析後 part URI。preflight 必須
   驗證 module 集合完整、沒有多餘項目、每個 target 是 workbook 實際列出的 worksheet，
   且 module 與 target 都是一對一。

第一版 typed host kind 只支援 `workbook` 與 `worksheet`。carrier 若含 chart sheet、
dialog sheet、macro sheet 或無法對映的 document module，資產註冊與注入都要 fail-loud；
不可把它猜成 worksheet。所有 code names 必須符合 Excel 的長度／identifier 限制；
每個宿主 code name 要與 inventory 中對應 document-module identifier 不分大小寫相等，
再對不同 logical modules 的 identifier 做不分大小寫的唯一性檢查，且不得與不相干的
standard／class module 撞名。正確的 `ThisWorkbook ↔ ThisWorkbook` 對應不是衝突。

寫入 XML 時有三項結構要求：

1. 既有 `workbookPr` 要保留其他屬性與 namespace 宣告；它在 schema 中是 leaf，若含
   無法解釋的子節點應拒絕輸入。既有 `sheetPr` 則要保留其他屬性與合法子節點，兩者
   都只更新 `codeName`。
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
4. 從 carrier 抽出 `xl/vbaProject.bin`，同時產生 carrier module inventory。
5. 將文字來源版本、Excel 版本、opaque carrier asset ID、carrier digest、binary
   digest、module inventory 與產製日期一起保存；binary 是 build artifact，不取代
   文字來源。

來源模組與 carrier 進入資產庫前要做 secrets、個人資料、硬編碼路徑與不必要外部
連線的掃描及人工審查。binary 與可解出的 VBA streams 都視為敏感 build artifact，
使用最小權限存放；一般執行日誌只能記錄 asset ID、版本與 digest，不得複製 VBA
source、binary、工作表內容或本機來源路徑。

任何 VBA 邏輯或 document-module 組成變更，都必須重走產製與驗證流程。已簽章的
VBA project、含密碼或不明保護的 carrier 不屬於第一版支援範圍。

## 5. 注入演算法的交易邊界

### 5.1 Preflight

在寫入任何資料前：

1. 將 caller 明確授權的來源與目的 URL canonicalize；以 no-follow 語意逐段檢查父目錄
   及 leaf identity，拒絕 symlink／alias 跳轉與授權範圍外的目的地。開啟並持有來源、
   staging 與目的 parent directory file descriptors，後續 I/O 只用 descriptor + relative
   leaf 錨定，不能在 commit 時重新解析整條 pathname。計算來源活頁簿與 VBA asset
   digest，核對 caller 提供的 expected digest。
2. 驗證副檔名、OPC root parts、workbook main part 與 relationships 存在且唯一，並
   確認上一節的 canonical layout、一般 `.xlsx` content type 與無既存 VBA 狀態。
3. 拒絕 traversal、absolute／non-canonical path、duplicate entry、symlink entry，
   以及超過 entry 數量、解壓總量、壓縮比、XML 深度或節點數上限的 package。
   每個 internal relationship Target 都要相對 owning part 做 URI 解析與 canonical
   resolution，且結果必須仍在 package 內；不得以 ZIP root 為所有 Target 的共同基準。
   既有 external relationship 只可作 opaque metadata 保留，offline validator 永不對
   `file:`、網路或其他 external Target 解參照；新增 external relationship 一律拒絕，
   要交給活 Excel 前則依第 8 節另做 deny／consent gate。
4. XML parser 停用 DTD 與 external entities；未知 parts 保留但不執行。
5. 拒絕已加密、密碼保護、數位簽章或帶未知保護語意的輸入。
6. 驗證 carrier provenance、binary hash、carrier module inventory、target binding
   的完整雙射，以及允許的 macro 清單。
7. 第一版只接受 **distinct new destination**：來源與目的經 canonical／no-follow
   identity 判定後必須不同，目的在 preflight 必須不存在。任何 existing destination、
   `overwrite = true` 或 source = destination 都要拒絕；支援既有目的檔的 conditional
   replace 必須另案設計。

### 5.2 Staging

1. 透過目的 parent dirfd 以 `mkdirat` + 隨機名稱原子建立同檔案系統的**私有 staging
   directory**；owner 必須是目前使用者、mode 為 `0700`，且不得有 ACL、group／other
   write 或其他 writer。以 `O_DIRECTORY | O_NOFOLLOW` 開啟並持有 staging dirfd。
   候選檔再以 `openat(O_CREAT | O_EXCL | O_NOFOLLOW, 0600)` 建立，從不重用既有 leaf，
   也不把 staging 路徑暴露給 log、callback 或其他程序。
2. 逐 entry 讀取來源；只有 allowed touched parts 進入專用 XML patcher，其餘 payload
   原樣複製。
3. 加入 `xl/vbaProject.bin`；before／after bytes 只存在受限的暫存記憶體或 staging
   驗證範圍，工作完成即清除。持久日誌只記 part name、mutation kind、before／after
   digest 與 semantic assertion，不得記錄 raw XML、cell value 或 VBA bytes。
4. 完成 ZIP 後 fsync 持有的 staging file descriptor；透過 staging dirfd + relative
   leaf 重新開啟，跑結構與 digest 驗證。commit 前再次以 `fstat`／`fstatat` 核對持有
   file descriptor 與 leaf 的 device、inode、type、owner、mode、link count、size、
   digest 完全相同，也重驗私有 staging directory identity／權限；不符就停止。
5. 同時透過持有的 descriptors 重新檢查來源 identity／digest 與目的 parent identity。
   最後提交不可使用「先檢查 absent、再一般 rename」；必須以 relative leaf
   呼叫 macOS `renameatx_np(fromDirFD, ..., toDirFD, ...,
   RENAME_EXCL | RENAME_NOFOLLOW_ANY)`，或語意等價、descriptor-anchored 的單一 atomic
   no-replace primitive。不支援這種 primitive 就 fail-loud。若 race 中目的 leaf 出現，
   commit 必須失敗並保留外部 bytes；失敗處理只清除 staging，不得用 backup 回滾或
   覆蓋目的檔。若原 pathname 的 ancestor 被換成 symlink，descriptor-anchored commit
   仍可安全寫入原先已授權的 directory object，但絕不可寫入 redirect target；回傳值
   要包含透過 `toDirFD` 重新開啟驗證的 output identity／handle，原 pathname 只作提示，
   不宣稱仍指向產物。成功後透過 `toDirFD` 以 `O_NOFOLLOW` 重開輸出，確認 inode 與
   已驗證候選相同並重算 digest，再透過持有的 directory descriptor 同步 metadata。

staging 驗證失敗不得改到來源或目的檔。第一版一律輸出到新的 `.xlsm` URL，不提供
覆寫模式。

上述保證的威脅模型是互動式單一使用者，且私有 staging directory 在交易期間只有
本程序能修改。能以同一使用者權限無視 `0700`、注入程序或修改其記憶體的惡意程序
不在第一版邊界內；若 staging identity／post-commit digest 仍不一致，必須回報完整性
事件、不得把產物交給 Excel，也不得自動用任何 backup 覆寫現場證據。

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

只有 target binding 要求且來源缺少相同綁定時，才可再改：

- `xl/workbook.xml`
- target binding 列出的 `xl/worksheets/sheetN.xml`

所有其他 entry 的 payload bytes 與 digest 必須逐筆相同。

### 6.3 被修改 XML 的可逆性

每個 XML patch 都要有交易內的 typed patch ledger。每筆 mutation 記錄 part、唯一
typed locator、原始 byte range、expected-before digest／bytes、after digest／bytes 與
patch order；後續 patch 的定位以當下版本重新驗證，任何 ambiguity 或 expected-before
mismatch 都要停止，不能猜測。raw bytes 只存在交易內受限暫存，不進一般日誌。

驗收先確認輸出語意，再依 ledger 反向順序只撤回列出的變更；撤回後的 XML bytes 必須
與來源完全相等。這能抓到 formatter 順手改了空白、attribute order、namespace、XML
declaration 或其他無關節點的問題。

只比較 parse tree 不夠，因為它看不出非必要的 byte drift；只比較 bytes 也不夠，
因為它不能證明 relationship、content type 與 `codeName` 語意正確。兩種檢查都要做。

### 6.4 Binary 與結構

- 輸出的 `xl/vbaProject.bin` bytes 必須與已核准 asset 完全相同。
- package 重新開啟後必須只有一個 VBA part 與一條對應 internal relationship。
- workbook main content type、binary content type、relationship target 與所有 target
  binding 都必須精確吻合。
- offline 驗證完成後才可把副本交給 Excel 作功能驗收；Excel 另存後的 package 不再
  使用上述 byte-preserving 主張。

## 7. 巨集真的有執行：狀態改變驗收

功能驗收必須使用受控 fixture、受控 macro allow-list 與真實 Excel for Mac：

1. **第一次交給 Excel 前**，重新核對受信任 carrier module inventory 的 procedure
   清單與 prohibited-entrypoint scan attestation，確認其 source／binary digest 仍吻合，
   且沒有 `Auto_Open`、`Workbook_Open` 或其他 auto／event entrypoint；external content
   policy 也必須通過。以事件巨集停用、外部更新拒絕的方式開啟；無法保證時就不執行。
2. 使用隔離的受控 Excel session，不同時開啟可能暴露同名 macro 的其他 workbook 或
   add-in；驗證目標活頁簿 identity、檔案 digest、巨集清單、VBE 非 break mode，且
   沒有 modal dialog。先切為 manual calculation、停用 refresh；無法控制這兩者時就
   不執行該驗收。
3. 受控 fixture 的 allow-listed macro 必須另外更新專用 execution witness（caller
   nonce 或單調 counter）；witness 不能由公式、recalculation、refresh 或一般輸入寫入。
4. 讀取挑戰輸入、輸出、checksum 與 witness，確認測試前置條件成立。
5. 將至少一個輸入改成會讓獨立 oracle 產生不同輸出的值；呼叫巨集前立即重讀，斷言
   輸出與 witness 都尚未改變，排除 automatic calculation 或 data refresh 的假陽性。
6. 以 Excel bridge 驗證過的 **workbook／project-qualified + module-qualified** 名稱執行
   allow-list 內的巨集；執行前後都重驗 target identity。設定 timeout，任何 dialog、
   作用中活頁簿漂移或失去目標 workbook 都要 fail-loud。
7. 重新讀取輸出，斷言結果與 witness **同時**按本輪 nonce／counter 改變，並逐格與
   獨立實作的預期結果比對。
8. 還原輸入後再執行一次，要求新的 witness，再斷言輸出也復原。

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

- [ ] typed request：經使用者授權且 identity 不同的來源／新目的 URL、expected input
      identity／digest、`expectedDestination = absent`、asset ID／digest、carrier module
      inventory、target binding；
- [ ] hostile OPC preflight 與明確的 typed errors；
- [ ] canonical Excel layout、一般 `.xlsx` content type、無既有 VBA 與只支援
      workbook／worksheet document modules 的 fail-loud gate；
- [ ] owning-part-relative relationship confinement，以及 external Target 永不解參照；
- [ ] fixed delta 與 conditional binding delta 的窄幅 XML patcher；
- [ ] entry-set、untouched payload、reverse-patch、binary 與結構驗收；
- [ ] same-filesystem staging、fsync、fresh reopen、source generation check 與 atomic
      no-replace；pre-rename race 建立目的檔時必須失敗並保留外部 bytes；
- [ ] 私有 `0700` staging directory、`O_EXCL | O_NOFOLLOW` candidate、pre-rename
      fd／leaf inode+digest equality 與 post-commit inode+digest equality；同名 leaf 取代
      的 deterministic hook 必須在最後 identity gate 被拒絕；
- [ ] pre-rename 把 pathname ancestor 換成 symlink 時，產物仍只落在原授權 directory
      object，redirect target bytes 不變，且回傳的是由持有 dirfd 重開驗證的 identity；
- [ ] raw workbook／VBA bytes 不進日誌、telemetry 或一般 artifact 的隱私測試；
- [ ] 受控 fixture 的 macro-alive 狀態改變測試；
- [ ] 另一 workbook 暴露同名 module／macro 時仍不會誤呼叫的 integration regression；
- [ ] 真 Excel integration gate 與缺少 Excel 時的明確 skip／fail policy；
- [ ] 文件化的平台、巨集授權與不支援封裝邊界。

## 非目標

- 不把 `vbaProject.bin` 當成文字來源，也不宣稱任意 VBA project 可由純 Swift 生成。
- 不以 Excel 另存取代 byte-preserving OPC 手術。
- 不以注入成功推論巨集可信或已執行。
- 不在本文件新增 `macdoc convert` 的 xlsx 路徑。
