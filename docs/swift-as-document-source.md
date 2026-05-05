# Swift 腳本作為 Word 文件的 source of truth

> **腳本就是文件。Word 是另一個寫作介面，不是輸出端。**
>
> 跑同一個 Swift 腳本兩次必須產生 byte-equal 的 docx；Word 在那份 docx 上的編輯必須能 import 回 Swift 端，且不會被下次 re-run 蓋掉。
> 這個雙向對齊（bidirectional alignment）是 `word-aligned-state-sync` Spectra change 的核心，也是 macdoc 區別於 docx-js / python-docx / pandoc 的設計位置。

本文件解釋為什麼一個 Word 對齊用的 Swift DSL 必須長成「authoring DSL → op log → XmlNode tree → docx」三層；為什麼 stable element ID 是不能讓步的設計約束；以及 macdoc 在 docx-js / python-docx / pandoc 三個典範座標系中的定位。

相關文件：
- `structural-editing-paradigm.md`：為什麼 conversion ≠ editing，editing 必須是 dirty-tracked overlay。
- `lossless-conversion.md`：分層輸出怎麼避免轉檔資訊流失。
- `openspec/changes/word-aligned-state-sync/`：本設計對應的 Spectra change（含 proposal / design / specs / tasks）。

---

## 0. 第零原則：腳本與 Word 是平等的兩個寫作介面

> **macdoc 不是「能用 Swift 產生 docx 的工具」。它是「能用 Swift 跟 Word **同時**寫一份 docx 的工具」。**

傳統的「Swift 產生 docx」工具（docx-js、python-docx、Apache POI、word-builder-swift）都假設一個方向：
**腳本 → docx → 給 Word 開**。Word 一旦動到那份 docx，腳本端就什麼都不知道；下次重跑腳本，Word 的修改會被蓋掉。

macdoc 把這個關係翻過來。腳本是 source of truth，Word 是另一個 actor：

```
Swift 腳本 ──┐                          ┌── Word 編輯
            │                          │
            ▼                          ▼
        op log（append-only, semantic operations）
            │
            ▼
        OperationReducer.materialize(log)
            │
            ▼
        XmlNode tree → docx bytes
```

兩邊的編輯都是 **operation**，都進同一個 log。Reducer 把 log 摺成最終 tree。
腳本重跑 = 把腳本對應的 ops 重新 emit；Word 端 import = 把 Word 的 diff 變成 ops 接到 log 後面。
**沒有「腳本端」跟「Word 端」誰主誰次——只有 op log 是唯一的真實**。

---

## 1. 為什麼三層架構是必要的，不是過度工程

|層|內容|為什麼不能省|
|---|---|---|
|**Layer 1 — Authoring DSL**|`WordDocument { Section(id: "ch1") { Paragraph(...) } }`，給人寫的 Swift result builder|沒有 DSL：人就要直接寫 `{op: "InsertParagraph", id: "...", in: "...", at: 0}` 或 raw XML，不可讀也不可組合|
|**Layer 2 — Op log**|append-only JSONL，每行一個 operation：`{op: "InsertSection", id: "ch1", at: 0}` / `{op: "SetRuns", id: "ch1-intro", runs: [...]}`|沒有 op log：腳本跟 Word 的編輯沒共同語言，alignment 無法 reduce 成「append 兩邊的 ops」|
|**Layer 3 — XmlNode tree → docx bytes**|`OperationReducer.materialize(log) → XmlTree → docx zip`|沒有 tree：ops 不能 replay 成可序列化的 docx；無法做 byte-equal round-trip|

**省掉 Layer 1**：腳本變成「手寫 op log」，沒人會用。
**省掉 Layer 2**：腳本直接生 tree → docx，Word 的編輯沒對應的 op 表示，alignment 變成 file-level diff（pandoc 等級的 lossy 比對）。
**省掉 Layer 3**：op log 沒有最終形態，不能 export 成 docx。

三層缺一不可。

---

## 2. Stable Element ID 是全局約束

> **沒有 stable ID，整個對齊架構會塌。**

腳本裡每個 `Section` / `Paragraph` / `TitlePage` 都要帶 `id:`，這個 id 會寫進 docx 對應元素的 `w14:paraId` 屬性（OOXML 原生有的 stable identifier）。

```swift
Paragraph(id: "ch1-intro") { "本章探討".text; Bold("意識本質"); "的議題。".text }
//             ▲
//             └── 寫入 <w:p w14:paraId="ch1-intro">
```

之所以非要 stable ID 不可，是因為對齊的核心邏輯依賴 ID 對應：

1. **Word import**：Word 把 `<w:p w14:paraId="ch1-intro">` 的內容改成「本章主要探討意識的本質與物質的關係。」
   `WordImport` 看到 paraId 還是 `ch1-intro`，但 textContent 變了 → 產出 `{op: "SetRuns", id: "ch1-intro", runs: [...]}`。
   **沒有 stable ID**：Import 只能用 positional index（「第 5 段」），但段落順序一變就全錯。

2. **腳本 re-run**：再跑一次腳本，emit 出來的 ops 跟上次一模一樣（因為 ID 一樣、內容一樣、順序一樣）。Reducer 看到 ops 跟 log 裡已有的等價，no-op。
   **沒有 stable ID**：每次 re-run 都產生「新的」段落（不同的隨機 ID），舊的「被刪除」，等於整份文件每次 re-build。Word 的編輯全部 orphaned。

3. **Conflict 解析**：腳本改 `ch1-intro` 的文字 + Word 改 `ch1-intro` 的文字 → 兩個 ops 都指向同一 ID，conflict 邊界清楚，policy（`.swiftWins` / `.wordWins` / `.abortOnConflict`）可以套上去。
   **沒有 stable ID**：conflict 是「兩個段落的文字都不同，誰是誰的修改？」——unsolvable。

ID 策略上有兩條路，**`word-aligned-state-sync` 設計選 explicit**：

|策略|寫法|優點|缺點|
|---|---|---|---|
|**Explicit**（推薦）|`Paragraph(id: "ch1-intro") { ... }` — 由作者命名|腳本重排不影響對齊；ID 有語意，方便 review|多打字；命名要紀律|
|Auto-derive|`Paragraph { ... }` — 從 `#filePath:#line` 自動 hash|不用打|腳本重排（移行、refactor）ID 全漂走，Word 對齊瞬間崩|

Auto-derive 看起來方便但對齊崩 = 整個架構失效，所以一定走 explicit。
作者體驗的成本由 IDE auto-complete + lint rule 補（「同 parent 下的 sibling ID 必須 unique」、「ID 必須匹配 `[a-z][a-z0-9-]*`」）。

---

## 3. DSL 的形狀

> **預設作者是 AI，不是人類。** 這個前提決定下面所有設計取捨：verbosity 不是成本（AI 不疲勞），命名一致性不是負擔（AI 擅長），自訂 component 學習曲線不是阻礙（AI 看 codebase 就會用）。整個 DSL 為「AI 寫腳本 + 人類寫提示」這個工作流優化。

人類也可以直接寫 `.mdocx`，但那是次要 use case。AI 是一級公民，DSL 的設計決定先優先 AI 可預測性、編譯期回饋、跟 op log 的 1:1 對應，**才**考慮純人類體驗。這個排序解釋了為什麼 §3.5 拒絕 Markdown layer。

```swift
import OOXMLSwift

let doc = WordDocument(metadata: .init(title: "賽斯書輕導讀", author: "作者")) {

    TitlePage(id: "title") {
        Heading1("賽斯書輕導讀", style: .titleBrown)
        Heading2("第一章", style: .secondaryDark)
    }

    Section(id: "ch1") {
        Paragraph(id: "ch1-intro") {
            "本章探討".text
            Bold("意識本質")
            "的議題。".text
        }

        Summary(id: "ch1-summary") {           // 自訂 component
            "重點：意識先於物質"
        }

        Paragraph(id: "ch1-body-1") {
            "更詳細的內文。".text
        }
    }

    Section(id: "ch2") {
        Paragraph(id: "ch2-intro") { "第二章開頭。".text }
    }
}

try doc.save(to: URL(fileURLWithPath: "賽斯書.docx"))
```

`save(to:)` 同時寫三個檔案：

```
賽斯書.docx              # 主文件（Word 開的）
賽斯書.docx.oplog.jsonl  # 完整 operation history
賽斯書.docx.snapshot.json # 上次 sync 後的 tree 快照（給 import diff 用）
```

`oplog.jsonl` 對應的內容：

```jsonl
{"op": "InsertSection", "id": "title", "at": 0, "ts": "2026-05-05T18:00:00Z"}
{"op": "InsertParagraph", "id": "title-h1", "in": "title", "at": 0, "ts": "..."}
{"op": "SetRuns", "id": "title-h1", "runs": [{"text": "賽斯書輕導讀", "style": "Heading1"}], "ts": "..."}
{"op": "InsertSection", "id": "ch1", "at": 1, "ts": "..."}
{"op": "InsertParagraph", "id": "ch1-intro", "in": "ch1", "at": 0, "ts": "..."}
{"op": "SetRuns", "id": "ch1-intro", "runs": [{"text": "本章探討"}, {"text": "意識本質", "bold": true}, {"text": "的議題。"}], "ts": "..."}
{"op": "InsertParagraph", "id": "ch1-summary-frame", "in": "ch1", "at": 1, "ts": "..."}
...
```

---

## 3.5 為什麼不混 Markdown layer

> **任何在 `.mdocx` 內嵌 Markdown 內容塊的設計都被拒絕。** Markdown 帶來的 ergonomics 在「AI 作者」前提下價值為零；它帶來的 **format determinism 風險** 卻會直接打破整個 alignment 系統。

### 3.5.1 Markdown 的三個不確定來源

|不確定來源|後果|
|---|---|
|**Flavor 分歧**（CommonMark / GFM / pandoc-md / MultiMarkdown 行為不同）|同一份 `.mdocx` 在不同 macdoc 版本可能產出不同 docx|
|**Parser 升級**（即使選定 flavor，bug fix 也算行為變動）|同一份 `.mdocx` + parser 升級 → 不同 ops → 不同 docx|
|**Markdown ↔ Word 不雙射**|Word 改了「**bold**」對應的 docx run，import diff 變成 op；要把 op 逆轉回 Markdown 等價字串需要 lossy converter，alignment 鏈條中斷|

第三點最致命——`.mdocx` 設計的整個前提是「op log 是 source of truth，腳本可以 reverse 自 oplog」。一旦腳本內含 Markdown，op log 沒辦法逆推 Markdown 字面量（因為 Markdown 跟 op log 不是 1:1 mapping），reverse direction 永遠不準。

### 3.5.2 四條曾考慮的路（全部拒絕）

|選項|設計|為什麼拒絕|
|---|---|---|
|A 純 Swift DSL，不接 Markdown（**選此**）|全部 `Paragraph(id:) { Bold(...); ... }`|無|
|B Markdown 限制在 inline-only（不能放 heading / list / table）|只 `**bold**` / `*italic*` / `[link](url)`|inline ambiguity 沒消除（GFM vs CommonMark）；reverse direction 仍 lossy|
|C 定義 `mdocx-md` v1：版本化 Markdown 子集 + pinned parser|規格 freeze，parser 版本進 `.mdocx` header|跟業界 Markdown 生態切斷（自創方言），且還是要寫 parser/converter 雙邊|
|D Markdown 只當 build-time sugar：compile 時翻成等價 Swift DSL|最終 `.mdocx` 等價於沒寫 Markdown|build-time parser 行為要凍結；升級走明確 migration；複雜度沒降只是搬位置|

### 3.5.3 AI 作者翻轉了 ergonomics 計算

人類作者寫 prose 時，`Paragraph(id:) { Bold("..."); "...".text; ... }` vs `**bold** ...` 的差距是巨大的疲勞成本——人類會懶得寫前者，會願意為後者承擔不確定性。

AI 作者完全沒這個成本：
- AI 對「verbose typed builder」跟「terse markdown」**沒有偏好**——都是 token generation
- AI 反而擅長維持一致命名（ch1-intro / ch1-body-1 / ch1-summary-frame ...）
- AI 看 codebase 就學會自訂 component 用法，不需要「直覺」UX
- Compiler 給 AI 的精確錯誤訊息 >> Markdown parser 給的「looks like a list but maybe not」silent behavior

當作者是 AI，A 的所有「verbose」缺點消失，所有「determinism」優點變成 net win。

### 3.5.4 連帶 hidden bonus：reverse direction 變可行

選 A 後，op log 跟 Swift DSL 是 1:1 mapping——意思是：**從 oplog 重新生成等價 Swift DSL 是無損操作**。

```bash
macdoc word reverse mydoc.docx --to mdocx               # 純從 docx 反推
macdoc word reverse mydoc.docx --to mdocx --from-oplog  # 含 Word 修改的當前狀態
```

這對 AI workflow 是**核心 dependency**——AI 要修改文件先要讀當前狀態。沒有 reverse 就沒有 AI 迭代。

選 B/C/D 都做不到無損 reverse（Markdown 部分一定 lossy），所以選 A 不只是 alignment 保證的問題，也是 AI workflow 能不能成立的問題。

---

## 4. 三個設計決定

### 4.1 ID 策略：Explicit

見第 2 節。**選 explicit**。

### 4.2 自訂 component：Swift `struct` + `@WordBuilder`

```swift
struct Summary: WordComponent {
    let id: String
    @WordBuilder var content: () -> WordContent

    var body: some WordContent {
        Paragraph(id: "\(id)-frame", style: .summaryFrame) {
            Symbol("◆ ")
            content()
        }
    }
}
```

|選項|寫法|評估|
|---|---|---|
|**Struct + @WordBuilder**（推薦）|`struct Summary: WordComponent { ... var body: some WordContent }`|SwiftUI mental model；component hierarchy 對應 op-log structure；可帶狀態（`let style: SummaryStyle`）|
|純函式|`func summary(id: String, _ text: String) -> ParagraphSpec`|簡單，但不能 nest 自訂 component；style / state 要靠參數 plumb|

選 struct + builder 的關鍵理由：**component hierarchy 是 op log 的天然 grouping 單位**。當 Word 改了 `Summary` 內部一個段落，import diff 可以說「這次修改影響 component `ch1-summary` 的內部一個 frame paragraph」，而不是「文件第 7 段被改了」。

### 4.3 Style：Inline，不獨立 stylesheet

```swift
Heading1("賽斯書輕導讀", style: .titleBrown)
//                       ▲
//                       └── enum value，腳本就讀得懂
```

|選項|評估|
|---|---|
|**Inline `style: .titleBrown`**（推薦）|腳本是 self-contained source of truth；看一個檔案就知道 docx 長怎樣|
|獨立 stylesheet `Document.styles += [...]`|分離 concern，但兩處同步很煩；ID 對齊時 style ID 也要 stable|

Inline 不代表 style 定義在腳本裡寫死——它是 enum reference，定義在獨立檔案：

```swift
// Styles/PaperStyles.swift
extension WordStyle {
    static let titleBrown = WordStyle(
        font: "Noto Serif TC",
        fontSize: 36,
        color: "#663300",
        bold: true
    )
}
```

腳本只 reference enum value，定義集中管理。Style 的 op 在 first-use 時 emit `{op: "DefineStyle", id: "titleBrown", ...}`，後續 reference 不重複定義。

---

## 5. 對齊 Word 的完整流程

下圖展示「腳本寫完 → Word 修改 → 腳本 re-run」的完整 cycle：

```
┌─────────────────────────────────────────────────────────────┐
│ T0  Author writes Swift script + run.                       │
│     → 賽斯書.docx + .oplog.jsonl + .snapshot.json           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ T1  Author opens 賽斯書.docx in Word, edits "本章探討" →    │
│     "本章主要探討", saves.                                   │
│     macdoc's SyncOrchestrator detects file change.          │
│     → Diffs current tree against snapshot.json              │
│     → Infers ops: {op: "SetRuns", id: "ch1-intro", ...}     │
│     → Appends to .oplog.jsonl                               │
│     → Updates .snapshot.json                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ T2  Author re-runs Swift script.                            │
│     Script emits ops (same as T0).                          │
│     Reducer sees:                                            │
│       - ops at T0 already in log (no-op)                    │
│       - Word's op at T1 in log between T0 ops and re-run    │
│     Reducer materializes tree:                              │
│       - ch1-intro text = "本章主要探討" (Word's edit wins)   │
│     New docx written; Word's edit preserved.                │
└─────────────────────────────────────────────────────────────┘
```

**關鍵不變式**：
- T0 跟 T2 的 Swift 腳本完全一樣，但 T2 產出的 docx 包含 Word 在 T1 的修改。
- **不是腳本「合併」了 Word 的修改**——是 op log 把兩邊的 ops 都收進去，reducer 摺出當前狀態。
- 腳本作者下次想覆蓋 Word 的修改，只要把 `Paragraph(id: "ch1-intro")` 的內容改成新文字，再 run，腳本對應的 op 在 log 裡比 Word 的 op 晚，新文字勝出。

---

## 6. 三個典範座標系裡的 macdoc 位置

`reference/` 收三個 docx 領域的代表 library：

|Library|語言|典範|對應 macdoc 哪一層|缺的是什麼|
|---|---|---|---|---|
|**docx-js**|TypeScript|Typed builder|Layer 1（Authoring DSL）|沒 op log；沒 stable ID 強制；沒 Word import|
|**python-docx**|Python + lxml|Tree-backed wrapper|Layer 3（XmlNode tree → bytes）|沒 op log；沒 DSL；對齊全靠人 + lxml diff|
|**pandoc**|Haskell|AST converter|—（不對齊任何特定 format）|Pandoc AST 是 lossy intermediary，無法做 byte-equal round-trip，更不可能 align Word 編輯|

把三個座標畫成軸：

```
                  Build docx
                  from scratch
                       │
                  docx-js（typed builder）
                  word-builder-swift（同模式）
                       │
       ┌───────────────┼────────────────┐
       │               │                │
   Read & edit         │           Convert to
   existing docx       │           another format
       │               │                │
   python-docx     macdoc            pandoc
   （tree wrap）   （DSL + op log     （AST + Reader/
                    + tree + sync）    Writer）
                       ▲
                       │
              **能跟 Word 雙向對齊**
              **的唯一一個**
```

|功能|docx-js|python-docx|pandoc|word-builder-swift|**macdoc**|
|---|---|---|---|---|---|
|Build docx from scratch|✓|✓ (clumsy)|✓ (markdown→docx)|✓|✓|
|Read existing docx|✗|✓|✓ (lossy)|—|✓|
|Mutate existing docx|✗|✓ (manual)|✗|—|✓|
|**Stable element ID**|✗|✗|✗|✗|**✓**|
|**Op log persistence**|✗|✗|✗|✗|**✓**|
|**Word import as ops**|✗|✗|✗|✗|**✓**|
|Byte-equal round-trip|N/A|✗|✗|—|**✓**|
|Replayable history|✗|✗|✗|✗|**✓**|

macdoc 在 op log + stable ID + sync 三個面向是這四個 library 中唯一全備的。
這個 differentiator 不是行銷話術，是來自一個非常具體的工作流需求：作者想在 Swift 跟 Word 兩邊同時寫，且不互相蓋。

---

## 7. 為什麼這個設計現在才出現

`word-aligned-state-sync` 之前的 ooxml-swift 是 destroy-and-rebuild parser：read → typed model → write。
這條路 5 天內爆了 6 個 cluster bug（PsychQuant/ooxml-swift #62 / #63 / #64 / #65 / #67 / #69），
原因是 typed model 不可能涵蓋每一個 OOXML element class，read 階段 silent drop，write 階段重建會少東西。

要逃脫這個架構陷阱，必須讓 tree 變成第一公民，typed API 變成 tree 的 view。
而既然 tree 已經是 source of truth、且要支援 Word 端的修改 import，那麼 op log 變成必然——
**沒有 op log 就沒辦法 reconcile Swift 端跟 Word 端的編輯**。

DSL 是這條鏈的最後一環：
- 沒有 DSL：人寫不出 op log
- 沒有 op log：Swift 跟 Word 對不齊
- 沒有 tree：op log 沒有最終形態

三件事必須同時成立。這就是為什麼 `word-aligned-state-sync` 是一個 9-phase / 72-task 的大遷移，
而不是「加個 fluent builder」就能解決的小事。

---

## 8. 實作藍圖（對應 Spectra change phases）

|Phase|對應本文|產物|
|---|---|---|
|**Phase 0**（v0.30.0, ✓ 已完成）|Layer 3 的基礎|`XmlNode` tree IO + `normalizedFingerprint` + corpus|
|Phase 1|Layer 3 的 typed view 改造|`Paragraph` / `Run` / `Table` / `SectionProperties` 變成 tree projection|
|Phase 2|Layer 2 的開頭|`OperationLog` + element ID 機制|
|Phase 3|Layer 2 的 reducer|`OperationReducer.materialize(log)`|
|Phase 4|Layer 2 的 typed-API 整合|`paragraph.text = "x"` 變 `log.append(.setText(...))`|
|Phase 5|Word import|`WordImport.diff(snapshot, current) → [Op]`|
|Phase 6|Sync orchestrator|file watcher + conflict policy|
|Phase 7|**Layer 1 — DSL（forward）**|`@WordBuilder` + `WordDocument { ... }` + script → op log transcoder。對應 §3 / §3.5 / §10|
|Phase 7|**Layer 1 — DSL（reverse, 核心 dependency）**|op log → 等價 Swift DSL transcoder。`macdoc word reverse mydoc.docx --to mdocx [--from-oplog]`。對應 §3.5.4|

**Reverse direction 不是 nice-to-have。** AI 是預設作者（見 §3 開頭 callout），AI 修改文件的前提是讀得到當前狀態的 Swift DSL 表示——沒有 reverse 就沒有 AI 迭代。Phase 7 必須同時 ship forward + reverse，否則 alignment 系統技術上完成但實際無法被 AI 使用。

`forward` 跟 `reverse` 在選 §3.5 的「純 Swift DSL，不接 Markdown」設計後是無損雙向（op log ↔ Swift DSL 是 1:1 mapping），實作上是兩個 transcoder 各自獨立的工程而非一個 reversible operation。

本文件描述的 DSL 是 Phase 7 的目標形狀。Phase 0-6 是讓 DSL 能成立的基礎建設。
跑完 Phase 7（含 reverse）= `word-aligned-state-sync` 全部完成 = ooxml-swift v1.0.0。

---

## 9. 邊界條件 / 已知拒絕的設計

|拒絕的設計|為什麼|
|---|---|
|腳本是「描述式」（YAML / JSON）|YAML 不能組合 component；不能帶邏輯；不能 type-check|
|Auto-derive ID（從 `#filePath:#line`）|腳本重排 ID 漂走，對齊崩|
|腳本直接生 tree、不經 op log|Word 編輯沒對應 op 表示，無法 reconcile|
|Op log 寫在 docx 內部（custom XML part）|Word 自動 strip 不認得的 attribute / part，sync metadata 會被消滅|
|Two-actor 同時 live editing（CRDT / OT）|Word 鎖檔機制不支援；CRDT 在 docx 上落地無解（同前理由）|
|多人同時 import + script run|單人 single-source-of-truth 設計；多人協作走 git，不走 oplog 合併|

這些拒絕設計在 `openspec/changes/word-aligned-state-sync/proposal.md` 的 **Non-Goals** 一節有完整列表。

---

## 10. 副檔名：為什麼是 `.mdocx`

DSL 的腳本檔副檔名是 **`.mdocx`**（不是 `.swift`、不是 `.wdoc`、不是 `.macdoc`）。

### 10.1 為什麼必須有自己的副檔名

詳見 `.claude/rules/extension-first-dsl.md`。一句話：**副檔名是 contract**——它告訴人 + 告訴工具這個檔案是什麼。
沿用 `.swift` 會讓 IDE 不知道這是普通 Swift 還是 Word DSL，shell tools 不能用 `find -name "*.mdocx"` 撈出所有 word 腳本，macdoc CLI 不能 file-association dispatch。

### 10.2 為什麼是 `.mdocx` 而不是 `.wdoc` / `.macdoc` / `.docscript`

家族公式：`.m<目標 format 的副檔名>`。

| 副檔名 | 解讀 | 目標產出 |
|--------|------|---------|
| **`.mdocx`** | **m**acdoc script that produces `.docx` | Word `.docx` |
| `.mpdf`（未來）| **m**acdoc script that produces `.pdf` | PDF `.pdf` |
| `.mbib`（未來）| **m**acdoc script that produces `.bib` | BibLaTeX `.bib` |
| `.mpptx`（未來）| **m**acdoc script that produces `.pptx` | PowerPoint `.pptx` |

`m` prefix = macdoc 品牌前綴，整個 family 由 macdoc owns。副檔名末段直接是目標格式（`.docx` / `.pdf` / `.bib`）——使用者一眼看到 `.mdocx` 就知道輸出 `.docx`，0 認知負擔。
比起 `w` prefix（可讀作 Word 或 writable，含糊），`m` 不歧義；比起 `.docscript` / `.macdoc-document` 等長前綴，`m` 短到能在 shell 裡 daily use。

被拒絕的選項：

|候選|為什麼不選|
|---|---|
|`.wdocx` / `.wpdf`| `w` 在不同 format 解讀不同（Word? Writable?），ambiguous|
|`.wdoc`| 不夠精確——「doc」可指 `.doc` (legacy) 或 `.docx`，且失去 m-prefix 的 macdoc 品牌歸屬|
|`.macdoc`| 太長；不能延伸到其他 format|
|`.docscript`| 太長；shell 裡常用副檔名應該短|
|`.swift`| IDE / find / file association 全部失效（見 §10.1）|
|`.docx-script` / `.smdocx`| 多一個 dash 或 prefix 字母，可讀性沒提升，只變難打|

### 10.3 Pattern：dual extension `mydoc.mdocx.swift`

實際 commit 進 repo 的檔名是 `mydoc.mdocx.swift`，不是純 `.mdocx`：

|看誰看|怎麼解析|得到|
|---|---|---|
|Xcode / SwiftLSP / `swift build`|看末段 `.swift`|完整 IDE 支援 / 編譯 / lint / auto-complete|
|macdoc CLI / file watcher|看末段 `.mdocx.swift` 或前段 `.mdocx`|知道這是 mdocx，dispatch 對應 pipeline|
|`find -name "*.mdocx*"`|匹配|找得到所有 word 腳本|
|作者腦袋|看到中間的 `.mdocx`|知道「這是會跟 Word 對齊的腳本」|

跟 `.tsx` / `.mdx` 走同條路：host 語言原生擴展（TypeScript / Markdown）+ DSL semantic marker。
零 IDE 配置成本，因為 Swift toolchain 認 `.swift`。

純 `.mdocx`（不加 `.swift` 後綴）也支援，但 Xcode 不會自動以 Swift mode 開——需要使用者手動設定 file association。**預設推薦 dual extension**。

### 10.4 副檔名跟 `WordDocument { ... }` builder 的關係

副檔名是檔案層級的 contract，builder DSL 是檔案內容的 contract。兩者互相獨立但互相補強：

```swift
// mydoc.mdocx.swift
//                ↑ 副檔名說：「這是會 align Word 的腳本」
import OOXMLSwift

let doc = WordDocument(metadata: ...) {
//          ↑ Builder 說：「這個檔案具體在 build 一份 Word document」
    Section(id: "ch1") { ... }
}

try doc.save(to: ...)
```

`WordDocument` builder 沒有 `.mdocx` 副檔名也能用（純拿來生 docx），但檔案副檔名告訴整個生態系（IDE / shell / macdoc CLI）這份檔案的「一級身份」是 word 腳本。建立關聯要靠副檔名 + import + builder 三件事一起，不是只靠 builder。

### 10.5 落地 checklist

`extension-first-dsl.md` 規定新 DSL 副檔名要走完這個 checklist。`.mdocx` 對應的進度：

- [x] 在 `docs/` 寫 design doc（**本文件**）
- [x] 在 `.claude/rules/extension-first-dsl.md` 「已註冊副檔名」表格 list
- [ ] macdoc CLI 加 `--from .mdocx` / file-glob dispatch（**Phase 7 工作**）
- [ ] `.gitignore` 區分 `*.mdocx.swift`（原始）vs `*.docx`（產物）（Phase 7 工作；目前可手動 ignore .docx）

