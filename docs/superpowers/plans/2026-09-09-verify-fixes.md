# 正式驗證修補與結案計畫

## Global Constraints

使用臺灣正體中文。保留既有工作；只在已建立的隔離工作樹實作。不修改 .build/checkouts，不自動推送／發布／合併。使用者已明確授權修正 #187、#181、#185、重驗並對通過者結案，這取代舊計畫的 no-close 邊界；不代表上游發布已獲授權。#186 已結案，不重做；#189–#194 是後續待辦，不擴大本輪範圍。TDD 先重現再修補，每案獨立提交、覆核及證據。程式碼凍結後驗證；不得審查中改 HEAD。

## Task 1: #187 驗證缺口

讀取既存 formal-close-review/issue-187-r1.md 的 F1–F5。
修 Tests/MacDocCLITests/README.md：release recipe 明列 #188 與 --disable-swift-testing；以 debug test bundle 加明確 release override 的替代流程區分產品與 runner。scratch-path 範例改用 mktemp 目錄，說明獨立 DocxIntegration 不受 override 控制、cwd/fixture 缺失可 skip。說清楚 skip-build、已 export override 不保證新鮮度；日誌僅由 run/convert 印 path，不宣稱全體runProcess或mtime。
新增直接驗 binaryPath 的真實組態接線測試，清除／還原測試用 env，防止分支反轉仍全綠；使用真實 debug/release 測試組態取得證據，不只傳入字串。不得改獨立 DocxIntegration resolver，不新增 mtime 政策，不碰產品CLI。
聚焦測試與 RED/GREEN；全 suite 一次。SwiftPM 若改 pins，只還原這次產生的鎖檔變化並記錄。報告提供執行命令、exit、計數、限制與精確 commits。

## Task 2: #181 文件與負向契約

讀 formal-close-review/issue-181-r1.md 的 M1–M6。保持生產 predicate 的精確條件與 coverage/stdout契約。
修 swiftify 範例：真 v0.7.0 不支援 coverage-only／新版根因，將完整診斷流程標示需本機包含相應提交的未發布CLI；舊版只提供真可用的明確段落替代路徑。不同輸出檔只避免彼此撞檔，重跑仍需新路徑或使用者同意覆寫。移除重申錯誤的0%量測，區分歷史樣本與本次可重現合成案例；保留任一表格門檻，不把 parse-error/byte-mismatch 皆歸為表格問題。
補 default+有paraId 不提示的負向e2e；負向斷言用flag token、保留有效原斷言。示範放寬predicate能使新test RED。
將被追蹤的 task-3-report.md 內容保留至 docs/superpowers/ 合理位置，再取消舊 scratch 路徑的追蹤；不得刪掉報告內容。不提高binary_version、不發布。驗證文中命令適用性、覆寫拒絕、slot/full-fidelity回歸；更新skill時遵守writing-skills測試紀律。

## Task 3: #185 核心格式保留

讀 formal-close-review/issue-185-r1.md 及父任務GitHub Verify處置，使用已核准Spectra規格。
先以含圖片、超連結、頁首頁尾、必要content types與rels的合成文件重現 official+script/replay。修profile apply與authoring writer保存完整原始metadata並合併profile parts，不留下dangling references；兩種writer與save/reopen保持一致。測試必驗實際relationships及target parts，不只驗document.xml id文字。
對無profile的普通文件保留metadata語意／必要保真，不讓格式finalizer多餘改寫；UTF-16 styles保存原始Data或從XMLparser正確轉換，不硬解UTF-8；加typed edit回歸。查核convert readback新增reader依賴與錯誤發布邊界。inherit對明示字型的保留遵守規格，不擅靠ID/值清掉caller格式。
只修confirmed問題；先重現可達路徑再裁定。維持explicit profile、不依內容自動猜官方文件。rules/缺席的review推論不得擅自轉成自動判斷；若需文件可補明確選取說明。不發布上游tag、不虛構remote pins。
相關工作樹：OOXML ../codex-185-ooxml（base d9f1f59）、config ../codex-185-config（base1db90dc，除確有本案缺陷不改）、MCP mcp/che-word-mcp（base7c261fa）。
TDD、集中回歸與每套件全suite一次；報告清楚分splitcommit與localeditable依賴。

## Task 4: 最終證據與結案

核心修補提交後，以最後凍結OOXML commit重新編譯generator產出測試DOCX，保存來源／產物hash，Mac與Windows Word驗收或證明全部packageparts與已驗成品等價。若操作Windows僅用先前核准的同一VM／同一測試文件，完成恢復suspended，不安裝軟體、不操作其他文件。
同步README的精確版本與平台狀態。正式重驗採既有R1+本輪修補delta為明確範圍，保留六路模型與反方覆核，Claude CLI使用前景Agent避免print背景600秒截斷；不得用缺失的reviewer冒稱PASS。
通過後按使用者指定idd-close 2.20 gate，逐案Closing Summary、close、立即CurrentStatus同步與讀回。未通過不關。上游依賴發布仍是獨立明確授權邊界。

