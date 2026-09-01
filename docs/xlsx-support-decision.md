# XLSX 支援決策紀錄

> 狀態：採用「Excel 讀寫能力進入 macdoc 家族，但不擴充通用轉檔矩陣」
>
> 決策日期：2026-08-13
>
> 來源：PsychQuant/macdoc#144；實作追蹤為 #135，OPC／VBA 文件追蹤為 #136

## 決策

macdoc 家族有真實的 Excel 需求，而且需要的是**讀寫**，不只是
`xlsx → Markdown/JSON` 的文字抽取。不過，第一個正式產品邊界是
`che-excel-mcp` 的試算表自動化能力，不是替 `macdoc convert` 新增 xlsx
來源或目標格式。

因此目前決定：

1. 由 #135 承接離線 xlsx/xlsm 操作與真實 Excel 自動化。
2. 由 #136 記錄 OPC ZIP 手術、`vbaProject.bin` 來源與 byte-level 驗證契約。
3. `Sources/MacDocCLI/MacDoc+Convert.swift`、`CONVERSIONS.md` 與既有
   converter package graph 暫時不增加 xlsx 路徑。
4. 未來只有在下方的再評估條件發生時，才考慮抽出共用 `xlsx-swift`，或新增
   xlsx 與 Markdown／JSON 等格式之間的直接 converter。

這不是「不做 Excel」，而是把兩個不同問題分開：

- **試算表自動化**：儲存格、公式、巨集、重算、另存及真實 Excel 驗證；
- **文件格式轉換**：把一種內容格式轉成另一種內容格式。

現有證據支持前者，尚不足以支持後者。

## 需求證據與頻率

### 已證實的工作流

#135 記錄了一個已完成的顧問交付流程，而不是推測性的功能清單：

1. 產生 `.xlsx`／`.xlsm`；
2. 以 OPC ZIP 手術注入 `vbaProject.bin`；
3. 讀寫 range 與 formula；
4. 驅動 Microsoft Excel 重新計算並執行 VBA；
5. 用第二套實作及逐格比較驗證結果；
6. 在真實 Excel 中另存並確認產物可用。

該流程同時揭露數個只有讀取 API 無法處理的失敗模式：巨集不存在或
VBE break mode 時的靜默 no-op、File Provider 儲存路徑錯誤、VBA module 與
`workbookPr/@codeName` 的宿主綁定，以及輸出原本就等於預期值時的假陽性驗收。

### 頻率判斷

目前 repo 能證明的是**一個完整、近期且已有具體步驟紀錄的專案型案例**。這足以
證明需求存在，也足以證明 read-only 不夠；但 repo 沒有可執行的 fixture、命令與
測試資產可證明該案例已可重現，也不足以推論時間頻率或日常轉檔需求。

所以本決策將頻率標成：

| 維度 | 判斷 |
|---|---|
| 已觀察案例數 | 1 |
| 已觀察案例型態 | 專案交付 |
| 時間頻率 | 未知 |
| 單次價值 | 高；牽涉交付正確性、公式與巨集驗證 |
| 日常 `convert` 使用頻率 | 尚無證據 |
| 重複利用潛力 | 合理但未驗證；同類精算、財務、成績與報表工作可能共用能力 |
| 長期統計 | 未知；不得由單一案例外推 |

## 為什麼必須是讀寫

| 能力 | 純 read-only xlsx parser 能否完成 | 本工作流是否需要 |
|---|---:|---:|
| 列出 sheet／讀取 range | 可以 | 是 |
| 讀取 formula 與 cached value | 可以 | 是 |
| 寫入 range／formula | 不行 | 是 |
| 建立 xlsx／xlsm | 不行 | 是 |
| 注入或更新 VBA project | 不行 | 是 |
| 強制重新計算 | 不行 | 是 |
| 另存並保留巨集 | 不行 | 是 |
| 擾動輸入後重算、另存並驗證結果 | 不行 | 是 |

只交付 `xlsx → text` 或 `xlsx → JSON` 會讓專案看似支援 xlsx，卻避開真正需要
封裝的寫入、公式、巨集與驗證路徑。因此 read-only parser 可以是日後的內部元件，
不能被視為 #135 的替代方案。

## 架構邊界

### che-excel-mcp 負責

- 離線 OPC 能力：建立活頁簿、精準更新 XML part、注入 VBA、保留未觸碰的
  ZIP entry payload。
- 活 Excel 能力：開關活頁簿、讀寫 range／formula、重新計算、列出與執行巨集、
  另存及比較結果。
- 驗證：輸入擾動後輸出必須跟著改變、逐格比較、必要時對照獨立計算引擎。
- 型別化錯誤：巨集不存在、VBE break mode、modal dialog、sandbox path 與 timeout
  都必須明確失敗，不能回傳成功的魔法字串。

AppleScript 或 ScriptingBridge 是 bridge 的實作細節。tool handler 只呼叫型別化
Swift 函數，遵守 `docs/applescript-swift-parity.md`。

### macdoc convert 暫時不負責

- 不新增 `xlsx → md`、`xlsx → json`、`md → xlsx` 等 CLI route。
- 不因格式表看起來缺一格，就建立所有 xlsx 與既有格式的兩兩 converter。
- 不把公式計算、巨集執行或 Excel object model 壓成一般 `DocumentConverter`。
- 不把試算表當成只有文字與表格的文件；formula、style、defined name、chart、
  validation、pivot、macro 與 calculation state 都是格式語意。

### 未來可抽出的共用層

如果多個非 MCP caller 都需要相同的 OPC 讀寫能力，可從 #135 抽出獨立
`xlsx-swift` package。抽取條件是已有共用 caller 與穩定契約，不是先建立一個
預想式 abstraction。

## native-macos-compat 檢查

`.claude/rules/native-macos-compat.md` 要求 converter 的基礎層優先對映原生能力，
並記錄必要例外。XLSX 沒有可直接取代完整 object model 的 Apple system framework，
但其 OPC 結構與活 Excel automation 都有符合專案原則的路徑：

| 檢查項 | 決策 |
|---|---|
| 基礎提取使用原生能力 | OPC ZIP 使用既有允許例外 `ZIPFoundation`；XML 使用 Foundation parser |
| 不引入可由原生能力取代的外部依賴 | 不把 Python/openpyxl、LibreOffice CLI、calamine 或 IronCalc 設為必要 runtime |
| 真實應用程式能力 | 透過 AppleScript／ScriptingBridge 的型別化 Swift bridge 驅動 Excel for Mac |
| 外部依賴例外 | Microsoft Excel 是 oracle 與 automation target；缺席時相關能力 fail-loud，不以其他 renderer 假冒 |
| CLI 規範 | 本階段沒有新增 converter route，因此不修改 textutil-compatible CLI |
| conversion matrix | 本階段不新增 route，因此 `CONVERSIONS.md` 保持不變 |
| 平台範圍 | 活 Excel 路徑為 macOS + Excel for Mac；離線 OPC 核心可保持純 Swift，但本輪不承諾跨平台產品支援 |

LibreOffice 可以作人工診斷工具，不能成為交付能力的必要正規化步驟。否則部署會
多一個大型外部 runtime，而且它不是 Excel 的計算與序列化 oracle。

## 安全與資料完整性邊界

本文件只決定能力歸屬，不代表「以型別化 Swift 包住 AppleScript」就已解決授權、
惡意輸入或儲存安全。#135 的實作與驗收至少必須遵守以下硬邊界：

- **巨集與活 Excel 授權**：`vbaProject.bin` 必須來自受信任來源，保存來源、雜湊與
  對應原始碼版本；注入及執行是兩個分開的明示操作。執行時以活頁簿身分、檔案雜湊
  與巨集 allow-list 驗證目標，不因開檔自動執行事件巨集，也不得自動降低 Excel
  Trust Center、TCC 或 VBE 安全設定。外部連結、外部內容與網路存取預設拒絕或明確
  要求使用者同意。
- **不受信任的 OPC 輸入**：ZIP entry 必須先驗證 canonical relative path、拒絕
  traversal、重複／非 canonical entry 與不安全的 external relationship target，
  並設定 entry 數量、解壓總量、壓縮比及 XML 深度／節點上限。XML parser 必須停用
  DTD 與 external entity，未知 part 預設保留但不執行。
- **原子儲存與世代檢查**：離線手術先寫入同檔案系統的 staging file，完成 fsync、
  重新開啟及結構驗證後才 atomic replace；replace 前用預期輸入 digest 拒絕外部改寫
  後的 stale save。Excel 另存會重寫 package，必須與 byte-preserving OPC 手術分成
  不同模式與驗收，不可共用「保真」主張。
- **受保護封裝**：加密、密碼保護、數位簽章或未知保護機制一律 fail-loud；除非有
  專門驗收，不宣稱能在修改後保留簽章有效性或保護狀態。
- **部署模型**：第一階段只承諾單一使用者、互動式 macOS 工作階段與使用者已授權的
  Excel for Mac；不把同一 bridge 宣稱為無頭、多租戶或遠端服務安全邊界。

## genoffice 對照的正確用法

分析固定在 `genspark-ai/genoffice`
`4da673d4dfa994bd0b4a9bc43430e4a058a17c61`（2026-08-03）。

genoffice 提供兩個不同層次的參考：

1. `packages/file-parse/src/xlsx.ts` 共 110 行，只做 sheet、shared strings 與基本
   cell value 的文字抽取。它適合證明 read-only 最小路徑很小，不代表完整支援很小。
2. `apps/sheets/native/xlsx-engine/` 的 Rust source 共 6,536 行，依賴 calamine、
   IronCalc、ZIP 與多套 XML parser，涵蓋 shared formulas、styles、comments、
   validation、defined names、charts、images、pivot、recalc 與 archive 操作。
   其中 recalculation 明列為 prototype，部分其他能力是讀取或索引 surface；這是
   較廣泛的能力面參考，不代表已具備完整 Excel 讀寫相容性。

應借鏡的是**能力分層與邊界可見性**，不是照搬 Rust sidecar 或依賴組合。macdoc
的差異是以 Swift、既有 OPC 保真方法與真實 Excel oracle 為主。

## 再評估觸發條件

發生任一條件時，重新開啟 `macdoc convert` 或共用 `xlsx-swift` 的評估：

1. 出現第二個與 #135 不同、且確實需要 `xlsx → md/json/csv` 的交付案例。
2. 至少兩個非 MCP caller 需要共用同一套 workbook parser／writer。
3. CLI 批次工作反覆需要在不啟動 Excel 的情況下讀寫 range 或 formula。
4. 需要支援沒有 Excel for Mac 的環境，且需求方接受與 Excel 不同的計算／渲染
   oracle；此時必須另案審核跨平台依賴與相容性主張。
5. #135 的實作證明某個離線子集已穩定，且抽成 package 能減少實際重複，而非只
   增加抽象層。

重新評估時仍要一個 converter 一張 issue，更新 `CONVERSIONS.md`，並逐路徑定義
formula、formatting、chart、macro 與 cached value 的資訊損失；不能只用「xlsx 已
支援」一個布林值概括。

## 非目標

- 本決策不實作 #135 或 #136。
- 不承諾任意 xlsx/xlsm 都能由 macdoc 無損編輯。
- 不把 genoffice 較廣泛的 Rust xlsx sidecar／engine 列為本專案的必備同等功能。
- 不宣稱 Excel for Mac 的 AppleScript dictionary 覆蓋所有 VBE／object model 能力。
- 不以一次顧問案推論長期使用頻率。
