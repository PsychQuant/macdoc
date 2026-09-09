# macdoc plugin

## 文件格式 profile：原始碼建置功能，尚未發布

macdoc#185 新增 CLI 與 Word MCP 共用的文件格式設定。需要整合尚未發布的 OOXMLSwift profile/store 與 PDFToLaTeXCore 設定保留變更；本機最終驗收使用 OOXMLSwift `3aa221aa3bba3657af68f1c8d22416d3efe9863e` 的 editable dependency，沒有把遠端 pin 偽裝成已發布版本。目前 plugin 下載的 macdoc 0.7.0 不支援。完成本機 SwiftPM editable 相依套件建置後，使用該工作樹的 `.build/debug/macdoc`。

```bash
.build/debug/macdoc config document show
.build/debug/macdoc config document import-official --template /path/to/Normal.dotm
.build/debug/macdoc config document set-default official
.build/debug/macdoc convert --to docx notes.md --profile inherit --output notes.docx
.build/debug/macdoc word render notes.mdocx.swift --to-docx result.docx --profile official
```

設定位於 `~/.config/macdoc/config.json`，格式如下；既有 AI/OCR 與未知欄位會保留：

```json
{
  "document": {
    "defaultProfile": "inherit",
    "officialSnapshot": "profiles/official-<UUID>.json"
  }
}
```

`import-official` 產生安全格式快照並更新參照，不切換 defaultProfile；省略 `--template` 時才使用目前帳號 Office 範本目錄的 Normal.dotm。後續不重讀原範本，也不複製正文或修改 Normal。繁中字型為標楷體，OOXML 使用 `DFKai-SB` 識別名稱；Mac Word 已實測 localized 名稱會觸發替代字型，因此不能以「標楷體」字串取代該識別名稱。core `992a3d67` 產生的 DOCX 已由 Mac Word 16.112.3 與 Windows Word 16.0.20326 實際驗收：A4、12 pt、左右 90 pt／上下 72 pt、段後 8 pt，兩邊 PDF 均嵌入 DFKaiShu-SB-Estd-BF 與 Aptos，PNG 無缺字、裁切或重疊。最終 reader 修補 core `3aa221aa` 以原合成測試固定 IDs／時間重新產檔，全部 10 個 package parts 與已驗輸入逐位元組相同，沿用該證據，本輪未重新執行 Word。其餘支援的版面及文字預設值來自範本，不等於一套法定公文格式。

新文件依序採明示 profile、設定預設、inherit。`inherit` 只在首次序列化前去掉記憶體中可證明由 factory 產生的預設字型，保留呼叫者明示字型；provenance 不寫入 OOXML，因此讀回文件的字型視為來源文件所有，不以 style ID 或字型值推測刪除。word render 與 MCP 既有文件操作只在明示 profile 時套用。官方快照缺失、損毀或不支援時會報錯。

文件設定命令接受 `--config`；convert/render 接受 `--document-config` 指定隔離設定。`show` 不輸出 AI/OCR 值。`--profile` 僅適用於轉換為 DOCX。convert 先套用格式，再於同目錄私有暫存區檢查成品、原子發布，保留既有一般檔覆寫方式與 Word 開檔鎖保護；render 驗證失敗保留舊檔，覆寫仍需 `--force`。
