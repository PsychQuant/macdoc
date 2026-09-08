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
- [ ] 3.3 完成 Cross-platform verification honesty：在 Windows Word 驗證同一份成品；環境不可用則保持此項未完成，不用 XML 測試取代。

2026-09-09 驗收註記：經使用者授權啟動 Windows VM，確認 Word 執行檔與 COM 註冊存在；自動化及共享路徑探測逾時，未成功開啟或匯出測試文件。VM 已恢復暫停。此項仍未驗證，不能據此結案。
