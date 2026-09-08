## Context

Parent macdoc#185 已核准完整計畫。現有 typed writer 與 authoring writer 使用不同資料来源，單改 styles 或 fontTable 會漏掉 replay。AIConfig.save 會丟棄其他 consumer 的 JSON 欄位。上游工作分別由 ooxml-swift#158、pdf-to-latex-swift#2、che-word-mcp#223 追蹤。

## Goals / Non-Goals

**Goals:** 格式來源可重現、安全匯入、兩種 writer 一致、跨 CLI/MCP 選擇一致、既有驗證先於發布。
**Non-Goals:** 不制定台灣法定公文格式，不讀取巨集，不複製範本正文，不自動猜情境，不修改使用者 Normal，不自動發布 binary。

## Decisions

### 安全格式快照與 OOXML 狀態同步

在 OOXMLSwift 提供 DocumentFormattingProfile 純資料與匯入／套用能力。匯入時依允許清單重建 XML／結構，不將任意 ZIP parts 塞進 Codable。使用自身 page 值解析，不能依賴只包裝 xmlNode 的 SectionProperties initializer。套用需覆蓋 docDefaults、styles、theme 與 safe section，並同步 ordinary writer／authoring writer 真正讀取的狀態。generic API 預設沒有 profile，舊 caller 不受影響。

### 文件設定與未知欄位保留

document 設定包含 defaultProfile 與 officialSnapshot 參照；profiles 僅 inherit/official。快照以版本化檔案存於 config 同目錄的 profiles 子目錄。先驗證並原子保存快照，再更新 config；已存在快照不默默重匯入。AIConfig.save 以已知鍵集合更新最新讀取的 object，保留未知鍵，nil 的已知欄位須移除，不能採只覆蓋非 nil 的天真 merge。

### CLI 與 MCP 的顯式套用

新增 macdoc config document show、set-default <inherit|official>、import-official --template <path>。import-official 預設來源可定位目前帳號 Normal，但只在該命令執行；不在每次產檔時讀 Normal。convert --to docx 使用 --profile 逐次覆寫，MCP create_document 使用 profile 參數。word render／MCP execute_script／open_document 只處理明示 profile，忽略 creation default。unsupported profile 報錯。

### 套用先於驗證與發布

ScriptPipeline 的 profile 參數預設 nil，在 replay 後、staging write 之前套用，再走現有 verify 與 publish。convertToFile 若沒有寫前套用入口，CLI 將轉換輸出導向本次私有 staging，讀取後套用並在最終原子發布前驗證；禁止先寫 user output 再補格式。MCP session 只有套用成功才註冊，新建/既有顯式變更正確標示 dirty。

## Implementation Contract

- 官方基底：使用者選定目前 Normal 的格式快照（A4、12 pt、其餘值由檔案解析），繁中字型標楷體；不是 Formal.dotx。
- 安全匯入：只取 styles/docDefaults、受限 theme/fonts/numbering 與 body 最終 section 的安全格式值。去掉正文、修訂資訊、header/footer/printer 引用、外部 rels、嵌入字型與影像；未支援且影響格式完整性的內容明確拒絕，不宣稱完整保留。
- 型別與 API：DocumentFormattingProfile 可 Codable 且有 schemaVersion；匯入與套用 throw；未知版本、缺必要資料、壞 XML fail-loud。任何 zip path 不可變成任意本機寫入目標。
- 決策優先：新建 explicit > config default > inherit；既有／replay 無 explicit 就完全不套 profile。呼叫者已明示的文字格式不被 inherit 清除。
- 設定操作：show 不列機密 AI/OCR 值；import 不在 snapshot 記原始絕對路徑；所有新設定寫入保留未知欄位。
- 驗收：合成 Normal fixture 檢查允許的 twips/half-point 值、禁止內容不存在、原檔 hash 不變、ordinary/authoring writer 一致。壞設定與 verify failure 檢查舊檔 bytes 不變。
- 相依工作在獨立 Git 工作樹執行；本機整合使用 SwiftPM editable dependency 或等價明確 local override，不編輯 .build/checkouts；未發布的上游依賴不偽造 release version。

## Risks / Trade-offs

- [安全與完整性衝突] → 不安全引用剔除；不可表示的必要格式拒絕並回報，不假裝完整。
- [字型不存在] → Mac/Windows 渲染驗收各自標示，不用 XML 字型名稱冒充已安裝。
- [多 consumer 設定覆蓋] → 已知鍵更新與未知欄位保留測試；不在本案承諾跨程序並發交易鎖。
- [上游 API 未發布] → 各 repo 留 commit 與 local integration 證據，發布前維持依賴追蹤，不宣稱可從遠端乾淨重建新功能。

## Migration Plan

預設 inherit；沒有 document 區段的設定正常讀取。新功能使用新 profile 參數，不改变未指定 profile 的腳本。回退時移除 document 區段即可停用；不刪原始範本或範本快照。正式上游發布與版本提升另走 release 流程。

## Open Questions

(none)；Mac/Windows 字型與視覺檢查是待執行驗收，不是未決產品選擇。

