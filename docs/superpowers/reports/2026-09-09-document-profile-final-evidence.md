# 文件格式 profile 最終平台證據

日期：2026-09-09。這份報告記錄尚未發布的 macdoc#185／che-word-mcp#223 本機 editable 整合驗收；不代表已發布 release、遠端依賴 pin 或 plugin binary 已包含此功能。

## 來源與產物

- 最終 OOXMLSwift：`992a3d67b772e99e420a7ffcbb54749dece39ceb`。
- generator 由該提交的 OOXMLSwift 與 ZIPFoundation `.swift.o` 重新連結，不含既有 runner main；source SHA256 `56c6a0da6dab6027701bae5ce88f9124f2f93396400a19b2906eb306d228be2b`，executable SHA256 `53295f5edffcf06e9a11a41ccc0dd881724f5ce61839743e5f08866db8309e6a`。
- 選定的 `Normal.dotm` 只讀輸入 SHA256 為 `4344474f78cf11a7b3517d662669cdb8093545cd94e2800516ad7cb51b7c53f1`；generator 前、generator 後與兩個平台驗收後三次讀值相同。原範本未複製、上傳或修改，實際使用者設定亦未變更。
- 新 DOCX SHA256 `71036f8a7fbac6f517fcc2d381d2af1e4f733cd11d532c41c2358011a718fd37`。

DOCX 的全部 package parts：

| Part | SHA256 |
|---|---|
| `[Content_Types].xml` | `623062aab4734ab83eb985cd6dbbd5340d9f036096fec186a6ba70d920cedd28` |
| `_rels/.rels` | `f4632f35d7e4caf33b80315621397c7ff899aff0c055d89b08fa8df31a4fe076` |
| `docProps/app.xml` | `65765e938f5e2363bf85f8ab7003956bd7694c72912ffa5990c663d143497c64` |
| `docProps/core.xml` | `01f8aaca494d7852e7aa71edeea713d523f2809dbc240893368774bc52cd25c9` |
| `word/_rels/document.xml.rels` | `c999e0d0352f1c5fb553be9655d6d9abcaff6ca4677343117924bc2762830d65` |
| `word/document.xml` | `fea96911dae7a040f9220dfe0b31bfa582581532fb78b148788e26124d78388a` |
| `word/fontTable.xml` | `fd7f4832dc29af2e5ef735b65bc3586719cb2628f7e5e6268985e3b398dbc4b7` |
| `word/settings.xml` | `fe934a948da7668164c7c52b025797a163226629af757c90deb6750326778afa` |
| `word/styles.xml` | `9294859615a50d1a687f910fa653856c174968734c17db0d8bb439567e3e0467` |
| `word/theme/theme1.xml` | `f8224736bec462156d02b4af55545a18c2a7165af2d90bfe735207a596e639f3` |

完整本機來源、連結物件、產物及逐 part 清單保存在 `.superpowers/sdd/2026-09-09-verify-fixes/visual/`；該工作證據依既有 ignore 規則不提交。

## Mac Word

- Microsoft Word 16.112.3，build 16.112.830。
- 原生欄位：A4 595.299987792969 × 841.900024414062 pt；左右 90 pt、上下 72 pt；首段 12 pt、`NameFarEast=DFKai-SB`、段後 8 pt。
- PDF SHA256 `f30c0d5f9bea2ce43e8f345c912135a84dc5d66b3bf4353d72121bc522af15f4`；`pdfinfo` 為 1 頁 A4、無 JavaScript；`pdffonts` 顯示嵌入子集 DFKaiShu-SB-Estd-BF 與 Aptos。
- 144 DPI PNG 已人工檢視：繁中楷體與西文清楚，無缺字方塊、裁切、重疊。
- Word 原本正在執行且有 0 份文件。匯出時 Word 顯示「授與檔案存取權」sheet；兩次匯出呼叫均沒有可宣稱的 process-level exit 0，第二次在 transport 的 30 秒等待內已產生 PDF。sheet 使腳本沒有完成 close；只在 FullName 精確符合本次合成文件後關閉該文件，沒有 quit Word。另一次唯讀開啟的原生度量腳本成功回傳並自行關閉，最終文件數為 0。平台結論依最終穩定 PDF、原生度量及 PNG，不把 timeout 冒充成功 exit。

## Windows Word

- 只啟動使用者核准的 che Windows 11 VM；開始前該 VM 與另一台 VM 都是 suspended。
- 使用 `prlctl exec --current-user PowerShell -EncodedCommand` 執行 UTF-16LE Base64 inline COM；沒有執行 `.ps1`、修改 execution policy 或安裝軟體。原始較長 EncodedCommand 超過 transport 可接受範圍，回 `Unable to open new session`；壓短為同一操作及防護後成功回傳 JSON。
- Microsoft Word 16.0，build 16.0.20326。輸入 FullName 精確等於指定 hostshare UNC，`readOnly=true`；原生欄位為 1 頁 A4 595.3 × 841.9 pt、左右 90 pt、上下 72 pt、首段 12 pt、`NameFarEast=標楷體`、段後 8 pt。
- PDF SHA256 `45d2271fc481efdab72b5b62d2175b403a6797a23f6192684d8b578508febef2`；`pdfinfo` 為 1 頁 A4、無 JavaScript；`pdffonts` 顯示嵌入子集 DFKaiShu-SB-Estd-BF 與 Aptos。
- 144 DPI PNG 已人工檢視：繁中楷體與西文清楚，無缺字方塊、裁切、重疊，版面與 Mac 一致；不宣稱兩份 PDF bytes 相同。
- 完整 EncodedCommand 在 30 秒 transport 等待內已輸出 JSON、PDF 與 metrics，但沒有可宣稱的整條命令 exit 0。隨後 host 無殘留該次 `prlctl`／PowerShell 程序，guest `tasklist` 無 WINWORD；VM suspend 成功，最後讀回兩台 VM 均為 suspended。只開啟本次合成文件，沒有操作其他文件或系統設定。

## 字型 provenance 與發布邊界

字型來源只存在於未序列化的記憶體物件。CLI／MCP creation adapter 必須在首次序列化前套用 `inherit` 或 `official`；`inherit` 只能移除可證明由 factory 產生的預設字型，caller 明示字型應保留。provenance 不寫入 OOXML，因此檔案讀回後的字型一律視為來源文件所有，即使再次以 `newDocument` context 套用，也不得以 style ID 或相同字型值猜測來源並刪除。

這次只更新證據與四個 README，沒有重跑完整程式碼測試套件、沒有修改 core production/tests、沒有發布、推送、合併或變更 GitHub issue。正式重驗與結案由 controller 另行執行。
