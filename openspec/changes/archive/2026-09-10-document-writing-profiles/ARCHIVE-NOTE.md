# 手動同步與歸檔紀錄

- 日期：2026-09-10；schema：spec-driven。
- 使用者已確認手動同步／歸檔，並接受不更新 Spectra 原生索引的限制。
- 15 項任務及全部 artifacts 均已完成；新增主規格中的 9 項 requirements、16 個 scenarios，規範本文不變。
- [主規格](../../../specs/document-writing-profiles/spec.md)已建立；原 change 目錄移入此處，五份原始文件（含 .openspec.yaml）原封保留。
- 原生 Spectra 2.3.1 將相同絕對路徑誤認為 main／worktree 兩份 change，因此未執行原生 archive。此為手動檔案層歸檔，不宣稱原生索引、identity bookkeeping 或自動 @trace 注入已完成。
- 未刪除既有驗證報告、未修改產品程式、未推送／發布／合併。既有 issue 結案狀態不變。

## 原始文件 SHA256

驗證：五份原始文件的歸檔前後 SHA256 全部一致；主規格的 requirements／scenarios 本文與原 delta 逐字相同（9／16），15 項任務均為完成，`git diff --check` 通過。此版本 CLI 的 `validate --specs` 回傳的是其他 change 清單，未驗到新主規格；因此本次主規格驗證為結構計數與規範本文一致性檢查，不冒稱原生主規格驗證已通過。

| 檔案 | SHA256 |
|---|---|
| .openspec.yaml | 1f3705b02fe2a94792852b5dcf6fdbd7ae90168046c68c474b3ca5f11932862f |
| proposal.md | 2340fa293699c513b39a4f199f5a990170877f1ce38c10d9ade8a80cce3726f5 |
| design.md | 7238c80bc9cd2af75b593ef5847779cfe9a51f8782848a1d6a65fffd3e33251c |
| tasks.md | 8bdf6f30bfe51651324fe120577787c3802ac5d679485923c934c64bf87419a3 |
| specs/document-writing-profiles/spec.md | fbb8a8f50d81f14614da13bcfefe2fb5e64e7283586dde18d5cbf3bb42c9d903 |
