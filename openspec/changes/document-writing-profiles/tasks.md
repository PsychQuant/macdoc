## 1. OOXML 格式 API

- [x] 1.1 實作 Safe official template snapshot 與 Snapshot stability and failures，依「安全格式快照與 OOXML 狀態同步」允許清單建立版本化純資料；以含正文／VBA／外部關聯的合成 fixture 驗證匯入安全、壞 XML 拒絕、原檔 hash 不變。
- [x] 1.2 實作 Shared explicit OOXML API、Official formatting 與 Inherit preserves document-owned formatting；以普通 writer／authoring writer 的 styles/theme/section 測試驗證 twips 值一致、新文件無強制字型、既有文件不變。
- [x] 1.3 實作 Verification before publication，依「套用先於驗證與發布」將 profile 接在 ScriptPipeline staging 前；測試 verify failure／overwrite refusal 不改既有 output。

## 2. 共用設定與 consumer

- [x] 2.1 實作 Configuration coexistence，依「文件設定與未知欄位保留」修正 AIConfig.save；測試 AI/OCR/document 交替更新、已知 optional 清空及損壞 JSON 不覆寫。
- [x] 2.2 實作 Profile selection 的 config document show／set-default／import-official 與 CLI convert profile，依「CLI 與 MCP 的顯式套用」選擇新建 explicit > default > inherit；測試缺快照報錯、顯式 inherit 不讀 snapshot、轉換 staging 後發布。
- [x] 2.3 將 Profile selection 接到 Word MCP create/open/execute 與 CLI render；測試新建預設、既有/replay 無 explicit 不變、失敗不註冊 session／不發布 output。

## 3. 整合與驗收

- [x] 3.1 更新 plugin 文件與設定範例，說明 Snapshot stability and failures 及未發布依賴；執行合成 CLI/MCP 契約測試並檢查實際輸出，不提高不存在的 binary_version。
- [x] 3.2 完成 Cross-platform verification honesty：以目前 Normal 格式快照在 Mac Word 驗證繁中字型、A4/12pt/邊界；記錄平台、字型、輸出比對結果。
- [x] 3.3 完成 Cross-platform verification honesty：在 Windows Word 驗證同一份成品；環境不可用則保持此項未完成，不用 XML 測試取代。

2026-09-09 驗收註記：初次探測逾時，後續收到命令引號解析錯誤；改用單次 EncodedCommand 後，Windows Word 16.0.20326 成功匯出相同測試文件。PDF 嵌入 DFKaiShu-SB-Estd-BF，A4、12 pt、左右 90 pt／上下 72 pt 邊界、段後 8 pt，PNG 無缺字或裁切且與 Mac 版面一致。未修改 PowerShell 執行原則、安裝軟體或操作其他文件；測試文件及本次啟動的空白 Word 程序已關閉，VM 已恢復暫停。

以上為初輪完成紀錄；正式驗證發現的新缺口由以下追加任務管理，必須全數完成才可再主張最終版本完成。

## 4. 正式驗證修補

- [x] 4.1 依正式驗證修補契約實現 Shared explicit OOXML API 的 Replay preserves unrelated package registrations：以真實 relationships／目標 parts 重現 official+replay，再修正 metadata 合併，ordinary／authoring／script／reopen 均無懸空引用且無關 bytes 不變。
- [x] 4.2 實現 Encoded styles and unchanged metadata：UTF-16 styles 的 typed edit 可保存；無 profile 且註冊未變時 content types／relationships bytes 保持原樣，以 focused regression 的 RED/GREEN 驗證。
- [x] 4.3 實現 Inherit preserves document-owned formatting 的 Explicit font equals a generated default 與 Serialized font provenance is unknown：同名同值的 caller 明示字型保留、其餘可證生成器字型省略；creation 在首次序列化前套用，讀回後保留不明來源的既有字型。以輸出 XML 與雙 writer 測試驗證，不以相等的值猜意圖。
- [x] 4.4 查核 Verification before publication 的 convert readback 相容性與失敗原子性；保留新建 profile 決策，僅對可重現問題修補；CLI/MCP 聚焦及完整回歸各通過一次，原始 remote pins 保留並揭露 editable 邊界。

## 5. 最終版本證據

- [x] 5.1 實現 Cross-platform verification honesty 的 Final writer snapshot evidence：以最後 core revision 重建 generator 與 DOCX、保存來源及逐 part hash，Mac／Windows Word 實測或證明與既有驗收輸入全部 parts 等價；四份 README 與證據範圍一致。
- [x] 5.2 對本輪修補 delta 完成獨立與正式驗證，確認先前 blocker 已解且未新增回歸；逐案記錄結果，只有通過者執行結案，不自動發布或合併。
