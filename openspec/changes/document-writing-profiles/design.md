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

共用 DocumentProfileStore 放在 OOXMLSwift 的獨立來源檔，以明確 configURL 初始化；只有 CLI/MCP adapter 主動呼叫 store 時才讀 config，不從 generic writer/importer 隱式讀取。resolve 接受 typed profile kind 與 new/existing context；existing 無 explicit 以及 explicit inherit 不讀不必要的 snapshot。import 每次產生新 UUID 的 immutable snapshot 檔，再原子更新 officialSnapshot 參照；config 保存失敗不覆寫舊快照。document 區段內未知欄位也保留。CLI document 設定命令支援 --config，convert/render 支援 --document-config 作明確替代路徑；MCP 以 constructor 注入 configURL 測試，不改真實使用者設定。

### CLI 與 MCP 的顯式套用

新增 macdoc config document show、set-default <inherit|official>、import-official --template <path>。import-official 預設來源可定位目前帳號 Normal，但只在該命令執行；不在每次產檔時讀 Normal。convert --to docx 使用 --profile 逐次覆寫，MCP create_document 使用 profile 參數。word render／MCP execute_script／open_document 只處理明示 profile，忽略 creation default。unsupported profile 報錯。

### 套用先於驗證與發布

ScriptPipeline 的 profile 參數預設 nil，在 replay 後、staging write 之前套用，再走現有 verify 與 publish。四個 DOCX converters 已有 convertToDocument，CLI 直接取得新建 WordDocument 後套 profile，再寫入同目錄私有 staging，檢查成品後原子發布；不新增 converter 公開 API，也不先寫 user output 再補格式。MCP session 只有套用成功才註冊，新建/既有顯式變更正確標示 dirty。

## Implementation Contract

- 官方基底：使用者選定目前 Normal 的格式快照（A4、12 pt、其餘值由檔案解析），繁中字型標楷體；不是 Formal.dotx。
- 安全匯入：只取 styles/docDefaults、受限 theme/fonts/numbering 與 body 最終 section 的安全格式值。去掉正文、修訂資訊、header/footer/printer 引用、外部 rels、嵌入字型與影像；未支援且影響格式完整性的內容明確拒絕，不宣稱完整保留。
- 型別與 API：DocumentFormattingProfile 可 Codable 且有 schemaVersion；匯入與套用 throw；未知版本、缺必要資料、壞 XML fail-loud。任何 zip path 不可變成任意本機寫入目標。
- 決策優先：新建 explicit > config default > inherit；既有／replay 無 explicit 就完全不套 profile。呼叫者已明示的文字格式不被 inherit 清除。
- 設定操作：show 不列機密 AI/OCR 值；import 不在 snapshot 記原始絕對路徑；所有新設定寫入保留未知欄位。
- 驗收：合成 Normal fixture 檢查允許的 twips/half-point 值、禁止內容不存在、原檔 hash 不變、ordinary/authoring writer 一致。壞設定與 verify failure 檢查舊檔 bytes 不變。
- 相依工作在獨立 Git 工作樹執行；本機整合使用 SwiftPM editable dependency 或等價明確 local override，不編輯 .build/checkouts；未發布的上游依賴不偽造 release version。
- 套用脈絡使用明確 newDocument／existingDocument enum；由 converter staging 讀回的文件仍傳 newDocument，不以 archive 存在推斷。
- 樣式合併保留目標正文仍引用的 style IDs；Normal 的 localized styleId 依 default paragraph 標記辨認，不硬編碼為 Normal。驗證 basedOn／next／linked 等依賴不懸空。
- 匯入 docDefaults 與安全 ancillary parts 必須保存在可持久寫入的 document state；updateStyle 或 markTypedDirty 後再次 save 仍保留，不只第一輪 XML 寫入成功。
- authoring writer 必須輸出 profile theme/fontTable 等允許 parts 並合併 content types／relationships；fontTable 是字型登錄，不等於對文字施加字型。
- existingDocument 明確 official 只套用最終 body section 的安全版面欄位，保留目標原本的 header/footer 參照與其他分節；不把快照沒有引用誤作刪除目標引用。
- 第一版拒絕帶實際 numbering definition 或非零 numId 的範本格式，使用具名 unsupported numbering error；不重寫目標既有 numbering，避免映射錯接。原始 Normal 是否可匯入以實測驗證。
- 測試以 configURL 依賴注入或新 document 指令明確的 --config 路徑使用隔離設定；不得覆寫真實使用者 config 作為測試。

## Risks / Trade-offs

- [安全與完整性衝突] → 不安全引用剔除；不可表示的必要格式拒絕並回報，不假裝完整。
- [字型不存在] → Mac/Windows 渲染驗收各自標示，不用 XML 字型名稱冒充已安裝。
- [多 consumer 設定覆蓋] → 已知鍵更新與未知欄位保留測試；不在本案承諾跨程序並發交易鎖。
- [上游 API 未發布] → 各 repo 留 commit 與 local integration 證據，發布前維持依賴追蹤，不宣稱可從遠端乾淨重建新功能。

## Migration Plan

預設 inherit；沒有 document 區段的設定正常讀取。新功能使用新 profile 參數，不改变未指定 profile 的腳本。回退時移除 document 區段即可停用；不刪原始範本或範本快照。正式上游發布與版本提升另走 release 流程。

## Open Questions

(none)；Mac/Windows 字型與視覺檢查是待執行驗收，不是未決產品選擇。
