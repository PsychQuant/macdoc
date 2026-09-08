# 四案實作交付紀錄

日期：2026-09-09。隔離分支 `codex/187-186-181-185`；原始 checkout 的既有變更保留。未發布、推送、合併或關閉 issue。

## 實作結果

- #187：依測試組態選 binary；明確且不可退回其他路徑的 `MACDOC_TEST_BINARY`，選取紀錄不污染 CLI 輸出。
- #186：三套件 Bundle.module 合成 bibliography；四個端到端測試不依賴個人檔案；subtitle mutation 確認會失敗。
- #181：限定 document.xml / paragraph-no-paraId / 非 coverage 情境的 stderr 提示；未調升 binary_version。
- #185：共享 config、inherit/official、安全且固定的格式快照、明確套用優先序、AI/OCR 保存未知欄位、CLI/MCP 整合。已修正失敗 open 的 session 回復及 theme 修改的讀取／持久化一致性。

## 精確驗證邊界

| 範圍 | 最新結果 |
|---|---|
| macdoc | 137 項，4 skipped，0 failures |
| OOXML | 1589 項，32 skipped，0 failures |
| Word MCP | 379 項，12 skipped，0 failures |
| bibliography 三套件 | 35 項通過，subtitle mutation RED/GREEN 通過 |
| AIConfig | 19 項通過；完整 119 項有 3 個既存失敗測試／6 個 assertion failures，已在原始版本重現 |
| Mac Word | 實際 PDF 字型與版面通過；Word 16.112.3，DFKaiShu-SB-Estd-BF，A4、12 pt、預期邊界與段落 |
| Windows Word | 實際 PDF 與畫面通過；Word 16.0.20326，標楷體、A4、12 pt、邊界／段落與 Mac 一致；VM 已恢復暫停 |

測試總數包含表列 skips；不可解讀為所有測試均實際執行。#187 的 release 產品另以 debug 測試 bundle + explicit release binary 驗證；原生 release Swift Testing 啟動問題另追蹤 macdoc#188。

本次有各工作項目獨立審查與整體分支審查，不等同正式 `/idd-verify` 的完整多模型流程。Windows task 3.3 已以實際 Word 匯出驗收通過；Spectra 任務 9/9 完成，但不代表正式發布或 issue 結案。

最後限定範圍複審通過：獨立重現確認 official/inherit 的後續 theme 修改在普通存檔、authoring 及重新開啟皆保留。沒有未處理的 Critical／Important。

## 尚未發布的本機依賴

| 儲存庫 | 本機分支 | 實作 HEAD |
|---|---|---|
| ooxml-swift | codex/macdoc-185-profile | d9f1f592d1c088b0969abc86030c9f50e37be25a |
| pdf-to-latex-swift | codex/macdoc-185-config | 1db90dc |
| che-word-mcp | codex/macdoc-185-profile | 7c261fa1493bf8ee5331a67ed7884b5563cae0a0 |

整合測試使用 SwiftPM editable dependencies 指向隔離工作樹；沒有修改 `.build/checkouts`。追蹤的 Package.resolved 保留原始遠端版本，不假稱新 API 已發布。因此全新遠端 checkout 尚不能只靠既有 pins 建置本次功能，須先完成上游審查／發布與依賴更新。

上游追蹤：PsychQuant/ooxml-swift#158、PsychQuant/pdf-to-latex-swift#2、PsychQuant/che-word-mcp#223。既存 normalizer 失敗另追蹤 pdf-to-latex-swift#3、#4，不混入設定修補。

## 實作裁定

- `DFKai-SB` 為序列化字型名稱，介面稱標楷體；Mac Word 證實本地化字串會退回其他字型，Windows Word 亦確認此識別名稱會使用標楷體。
- 共用 store 接受明確 configURL；一般 OOXML writer 不讀使用者設定。
- 快照使用不可變 UUID 檔案再原子更新設定參照；不修改 Normal 或實際使用者設定。
- v1 拒絕範本中的實際 numbering，避免錯接目標文件的 ID；不以靜默降級取代錯誤。
- 新文件依 explicit > config > inherit；既有文件與 replay 沒有 explicit profile 即保持原行為。
- Windows 初次逾時與引號錯誤改用單次 EncodedCommand 解決；未修改既有指令碼執行原則或安裝軟體。匯出後 Quit 的 COM ref 參數另行正確呼叫，已確認本次空白 Word 程序關閉，再恢復 VM 暫停。
