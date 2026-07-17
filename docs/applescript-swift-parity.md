# AppleScript–Swift Parity

一個關於「驅動活 App」類 MCP(che-excel-mcp 起)的設計規則。

---

## 核心主張

> **AppleScript 是實作細節,Swift 函數是契約。**
>
> 每一個 AppleScript 能力都必須有一個型別化的 Swift 函數對應;
> tool handler 永遠只呼叫 Swift 函數,永不直接觸碰
> `osascript` / `NSAppleScript` / 內嵌腳本字串。

---

## 1. 為什麼需要這條 rule

### 1.1 AppleScript 直呼是 stringly-typed 的

參數拼進字串、回傳靠解析文字、錯誤只在 runtime 出現。更糟的是
Apple event 的失敗模式經常是**靜默的**。實戰(2026-07,Excel
自動化)踩到的地雷全屬此類:

| 地雷 | 直呼的行為 | 型別化後的行為 |
|------|-----------|---------------|
| `run VB macro` 呼叫不存在的巨集 | **silent no-op,exit 0** | `throws MacroNotFound` — 呼叫前先驗巨集清單 |
| VBE 處於 break mode | 之後所有巨集執行被**靜默吞掉** | `throws VBEInBreakMode` — 執行前偵測 |
| 巨集彈 `MsgBox` | AppleEvent 被擋,呼叫端不知情 | wrapper 內建 dialog 偵測 + timeout |
| `save as` 到 File Provider 路徑 | 錯誤 **-50「參數錯誤」**(實為 sandbox) | `throws SandboxDeniedPath` + 建議改走進程內 SaveAs |
| 舊 API `make new button` | 建立成功,**存檔時**才序列化失敗 | wrapper 直接不暴露已知損壞的 API |

錯誤不消失,但從「靜默/誤導」變成「具名、可攔截、可測試」。

### 1.2 單一 API surface

AppleScript、ScriptingBridge、JXA、AX API 是四種可互換的實作路徑
(同一能力常有多條路,可靠度不同)。Swift 函數層讓實作可以換路
而 tool handler 零改動。

### 1.3 能力盤點 = 函數清單

「這個 MCP 能對 Excel 做什麼」的答案應該是掃一份 Swift 函數清單,
而不是讀散落的 `.applescript` 檔。

---

## 2. Rule 的精確形式

1. **粒度是 capability,不是 script 檔。**
   一個動作一個函數(`readRange`、`runMacro`、`saveAs`),
   不是「一個 `.applescript` 檔一個函數」。整塊多步驟腳本
   (如驗證流程)是**組合**,由 Swift 層以函數組合表達。

2. **方向性:Swift 函數是唯一入口。**
   可機械檢查:`osascript` / `NSAppleScript` / `OSAScript` 字面
   只允許出現在 `Sources/**/AppleScriptBridge/` 之內。
   出現在任何 tool handler = 違規。

3. **錯誤路徑必須型別化。**
   每個 wrapper 至少涵蓋:目標 app 不在跑、目標物件不存在、
   modal dialog 擋道、timeout。`Result`/`throws`,不回傳魔法字串。

4. **`AppleScriptTask` 資產也算。**
   部署到 `~/Library/Application Scripts/<bundle-id>/` 供 VBA 回呼的
   `.scpt` 是**資產**不是入口;它的 Swift 對應物是
   「部署函數」(install/verify)+ 對 handler 簽名的契約測試。

5. **每個 wrapper ≥ 1 integration test(真 App)+ ≥ 1 錯誤路徑 test。**
   AppleScript 層無法單元測試,正是把它包進 Swift 的主因——
   測試義務落在 wrapper 上,不得以「腳本測不了」為由跳過。

---

## 3. 範例簽名(che-excel-mcp 草案)

```swift
enum ExcelBridgeError: Error {
    case appNotRunning
    case workbookNotFound(String)
    case macroNotFound(String)
    case vbeInBreakMode
    case blockedByDialog(title: String?)
    case sandboxDeniedPath(String)
    case timeout(seconds: Double)
}

func readRange(workbook: String, sheet: String, range: String)
    throws -> [[ExcelValue]]

func runMacro(workbook: String, name: String,
              dialogPolicy: DialogPolicy = .failOnDialog,
              timeout: Double = 60) throws

func saveAs(workbook: String, url: URL,
            format: WorkbookFormat) throws   // 內部走進程內 SaveAs,繞 sandbox
```

---

## 4. 與家族其他成員的關係

- `che-ical-mcp`(EventKit)與 `che-apple-mail-mcp`(AppleScript)
  已隱式遵守此模式;本文把它升為明文 rule。
- macdoc 既有 mcp(word/pptx/pdf)是離線檔案轉換,無 AppleScript 層,
  不受本 rule 約束;若日後加入「驅動活 Word/PowerPoint」能力,
  同樣適用。

## 參照

- 提案與實戰經驗清單:PsychQuant/macdoc#135
- 三層 AppleScript alignment(驅動 / 語意對齊 / AppleScriptTask 回呼):
  #135 的設計補充 comment
