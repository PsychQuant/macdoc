# Structural Editing as a Paradigm Shift

> **Format conversion 和 structural editing 是兩個不同的範疇，不是同一範疇上的品質高低。把這兩個歸成一類是這個領域長期的混淆——也是 macdoc 真正的革命性所在。**

---

## 0. 第零原則：Conversion ≠ Editing

> **轉換是「把 A 投影到 AST，再從 AST 投影到 B」——AST 沒裝得下的東西全部被丟掉。
> 編輯是「把 A 拆成 N 個 parts，只動我關心的那一個 part，其他 N-1 個 parts 保持 bit-exact」。
> 前者是 lossy by design，後者是 lossless by architecture。**

這份文件解釋為什麼這個區別不是修辭遊戲，而是 paradigm 等級的差別。
它解釋為什麼 macdoc 在 LLM-document workflow 的時代，
能做到 pandoc / textutil / python-docx / docx.js / Apache POI 都做不到的事。

`lossless-conversion.md` 處理的是另一個問題：「如何在轉檔時不丟資訊（透過分層輸出）」。
本文處理的是：「如何在編輯時不破壞原檔（透過 dirty-tracked overlay）」。
兩個原則互相補強，但解的問題不同。

---

## 1. 真實世界的 .docx 是什麼樣子

打開一份 NTPU 學位論文 `thesis.docx`，把它當 ZIP 解開，會看到大約 60-150 個檔案。
其中 **macdoc 的 typed model 直接管理的可能只有 8-15 個**——
其他 50+ 個檔案是文件作者、共編者、Office 自身、Zotero 外掛、template 系統等
**多年累積的 metadata 化石層**。

舉例（從一份真實的 NTPU 論文抽出來）：

| 檔案 / 結構 | 用途 | 來源 |
|---|---|---|
| 34 個 root `xmlns:*` 宣告 | XML namespace 解析 | Word 自身 + W3C SGML 遺產 |
| `word/theme/theme1.xml` | 主題色 + 字型 fallback chain | Word template（含 `DFKai-SB` 中文 fallback） |
| `word/people.xml` | 共編者 GUID + display name | Word collaborative editing |
| `word/commentsExtended.xml` | comment 回覆鏈 + parent ID | Word 2013+ |
| `word/commentsIds.xml` | durable comment ID（與 W3C web comment spec 對齊） | Word 2019+ |
| `<w:ins>` / `<w:del>` 多人 review markup | track changes | Multiple reviewers |
| `<w:commentRangeStart>` / `<w:commentRangeEnd>` | 跨段 comment anchor | Word |
| `customXml/itemX.xml` + `itemPropsX.xml` | Zotero / EndNote citation database | Bibliography manager |
| `<w15:presenceInfo>` | 共編 presence | OneDrive / SharePoint |
| `glossary/document.xml` | template boilerplate (空白範本內容) | Organizational template |
| `word/fontTable.xml` | 13 個字型 entry + Chinese fallback chain | Word + 作者選的字型 |
| `fonts/font1.odttf` | 嵌入字型 binary（obfuscated TTF） | 作者授權嵌入 |
| `word/_rels/document.xml.rels` | 30+ relationship entries | Cross-file integrity |
| `[Content_Types].xml` | 每個 part 的 MIME 註冊 | OOXML spec 強制 |

**作者打開這個檔案是不會看到大部分內容的**。但這些 metadata 全部都有功能性：
- 沒有 `theme1.xml` 的字型 fallback → 中文字會 render 成豆腐方塊
- 沒有 `people.xml` → comment 顯示成 "Unknown user"
- 沒有 `customXml/itemX.xml` → Zotero 引用斷裂，需要重建整本書目
- 沒有 `commentsExtended.xml` → 回覆鏈塌成單層 comment
- 沒有 `glossary/document.xml` → template 連結斷裂
- 沒有 `fonts/font1.odttf` → 需要嵌入字型才能正確顯示的字型 fallback 失敗

換句話說，**這些「看不見的」檔案才是讓 .docx 對作者「感覺像是他自己的檔案」的東西**。

---

## 2. 為什麼 pandoc 做不到

Pandoc 的設計是 **AST-mediated conversion**：

```
.docx → reader → Pandoc AST → writer → .docx
```

Pandoc AST 是 pandoc 為了支援數十種輸出格式而設計的最大公因數結構，
能裝下 paragraph / heading / list / table / link / image / inline formatting 等通用概念。

**它裝不下的東西**：
- Theme 設定（rendering hint，不是內容）
- Custom XML parts（vendor-specific）
- Track changes（pandoc 把它 flatten 成 plain text）
- Comment 回覆鏈（只能保留 plain comment）
- Embedded fonts binary
- Presence info / collaboration metadata
- Template boilerplate
- 嵌入式 Excel chart（OOXML embedded objects）
- 自訂 styles 與組織模板的繼承關係
- xmlns 宣告
- ...etc.

跑 `pandoc thesis.docx -o out.docx`：
- pandoc reader 解析 → 把它能裝進 AST 的東西放進 AST
- 其他全部 silent drop
- pandoc writer 從 AST 重建 → 從零生成新的 .docx，只有 pandoc 知道怎麼寫的部分

結果：`out.docx` 在文件視覺上看起來「差不多」，但作者打開後會發現
**他批註的痕跡沒了、共編者的 comment 沒了、Zotero 引用斷了、字型 fallback 退化了**。

這不是 pandoc 的 bug，這是 AST-mediated conversion 的數學限制：
**AST 是一個有限維度的投影空間，原始 .docx 是無限維度的物件。投影必丟資訊。**

textutil、python-docx、docx.js（基於 docx4j）、Apache POI 全部都採同樣的 architecture，
全部有同樣的數學限制。

---

## 3. macdoc 的解法：Dirty-Tracked Overlay Save

ooxml-swift 從 v0.13.0 開始用一個結構性不同的設計：

```swift
class WordDocument {
    var modifiedParts: Set<String> = []  // 被改動的 part 路徑
    let originalArchive: TempDir         // 原始 ZIP 解開的 tempDir
    var typedModel: ParsedDocumentModel  // 結構化模型（document, styles, headers, footers, etc.）
}
```

`open_document` 時：
1. 把原始 .docx ZIP 解開到 `originalArchive` tempDir
2. 把 typed-managed parts（document.xml, styles.xml, header*.xml, footer*.xml, ...）
   parse 進 `typedModel`
3. **不動其他 parts**，留在 tempDir 裡

API mutation（例如 `document.replaceText(...)`）時：
1. 修改 `typedModel` 對應的 in-memory 結構
2. 把該結構對應的 part path 加進 `modifiedParts`

`save_document` 時：
1. 對每個原始 ZIP 裡的 part：
   - **如果 part path 在 `modifiedParts` 裡** → 從 `typedModel` re-serialize 寫出
   - **否則** → 直接從 `originalArchive` 拷貝原始 bytes 進新 ZIP
2. atomic-rename 寫到目標 path

**關鍵性質**：

> **未被改動的 part，bit-exact 等於原檔**。
>
> 不是「重新生成的內容看起來相同」，而是「同一串 bytes」。
>
> SHA-256(原檔的 part) == SHA-256(輸出的 part)

這個性質讓 NTPU 論文的 50+ 個 metadata parts 不論 LLM 透過 MCP 怎麼操作都不會被破壞。
Theme、custom XML、commentsExtended、people、glossary、嵌入字型、presence info——
全部 bit-exact 保留。

只要 LLM 沒明確 mutate 某個 part，那個 part **數學上不可能**在 save 後改變。

### 3.1 Modified parts：content-equality（v0.19.6 / #58 onwards）

未改動 parts 是 **bit-exact preservation**。被改動的 parts（typically `document.xml`）
re-serialize 時走另一條路徑——typed model emit + raw fallback for unknowns。

從 v0.19.6 (sub-stack A #58) 到 v0.20.3 (sub-stack E #66) 累積建立了
**modified parts 的 content-equality 保證**：

| 保留類別 | 機制 | 來源 |
|---|---|---|
| **Block-level markers**（`<w:bookmarkStart>`、`<w:bookmarkEnd>`、其他 `EG_BlockLevelElts`）| `BodyChild.bookmarkMarker` (typed) + `BodyChild.rawBlockElement` (catch-all)；container parsers symmetric | sub-stack A #58 (4 sub-cycles) |
| **Whitespace `<w:t xml:space="preserve">`** | `WhitespaceOverlay` byte-stream pre-scan + `WhitespaceParseContext` + `advanceWhitespaceCounter(includeDelText:)` 跨 6 個 `<w:t>`-bearing parts | sub-stack B #59 (5 sub-cycles) |
| **Run-level RunProperties typed**（`<w:rFonts>` 4-axis、`<w:noProof>`、`<w:kern>`、`<w:lang>` 3-axis） | typed `RFontsProperties` / `LanguageProperties` + extraction in `parseRunProperties` | sub-stack C #60 |
| **RunProperties raw children**（`<w14:textOutline>`、`<w:caps>`、`<w:smallCaps>`、`<w:spacing>`、`<w:position>`、`<w:shd>`、`<w:bdr>`、`<w:em>`、`<w:effect>` 等）| `RunProperties.rawChildren: [RawElement]` passthrough | sub-stack C-CONT |
| **Paragraph-mark RunProperties**（`<w:pPr><w:rPr>` controlling pilcrow ¶ glyph）| `ParagraphProperties.markRunProperties` reuses `parseRunProperties` verbatim | **sub-stack D #65** |
| **Paragraph w14:* GUIDs**（`<w:p w14:paraId="..." w14:textId="...">` — Word's revision-tracking anchors for collaborative editing） | `Paragraph.w14ParaId` / `w14TextId` String? plain attribute passthrough | **sub-stack E #66** |
| **`<w:delText>` content**（tracked deletions）| Run.rawElements + writer-gate; `includeDelText: false` opt-out 防 counter desync | sub-stack B-CONT-2-CONT (hotfix) |

驗證方式是 **cross-cutting matrix-pin** `testDocumentContentEqualityInvariant`，
LOAD-BEARING across **5 preservation classes**（bookmarkStart count、`<w:t>` char sum、
rPr children ratio floors for rFonts/noProof/lang/kern/w14:）+ size-loss ceiling，跑在 NTPU thesis fixture 上。
任何未來改動只要破壞這幾個 class 就會在 CI 上 fail。

**Modified parts 不是 bit-exact**——必然有 canonicalization（attribute 順序、namespace
prefix 收斂）。但 **content-equality 保證 typed + raw fallback 不會 silently 丟掉
任何 element class**。沒被改動的 part 仍然是 bit-exact（這條 invariant 不變）。

#### Round-trip size impact (NTPU thesis fixture, document.xml)

| Version | Loss | 原因 |
|---|---|---|
| Pre-fix v0.19.x | 32% | `<w:rFonts>` 4-axis collapse + `<w:noProof>` / `<w:kern>` / `<w:lang>` silent drop + `<w14:*>` 全部 drop + `<w:t xml:space="preserve">` 部分 drop + body bookmarks drop |
| Sub-stack A v0.19.6-v0.19.9 | ~28% | bookmarks 保留；其他 rPr 類別仍 drop |
| Sub-stack B v0.19.10-v0.19.13 | ~24% | whitespace 保留；rPr 仍 drop |
| Sub-stack C v0.20.0 | 17.75% | run-level typed + raw rPr children 大部分保留 |
| Sub-stack C-CONT v0.20.1 | 16.66% | trim `recognizedRprChildren` Set，common rPr 類別（`<w:caps>`/`<w:spacing>` 等）也保留 |
| Sub-stack D v0.20.2 | 10.95% | paragraph-mark `<w:pPr><w:rPr>` 完整 round-trip（`<w:lang>` 50% → 98.89%） |
| **Sub-stack E v0.20.3** | **8.02%** | paragraph `w14:paraId` / `w14:textId` 完整 round-trip（w14:* 5% → 93.98%） |

剩下的 8% loss 是其他 w14:* attribute classes（如 `<w:r>` 上的 w14:* 屬性、
其他 paragraph-level attributes 等），tracked as separate follow-up SDD。
推向 < 5% 後即可正式 ship 第 6.1 節「edit 一個字 → document.xml shrinks <1%」strong demo。

---

## 4. 對照表：能不能完成任務

打開同一份 NTPU 學位論文 `thesis.docx`，比較不同工具的 round-trip 結果：

| 文件特徵 | `pandoc thesis.docx -o out.docx` | `python-docx` open + save | `che-word-mcp` open + 改一字 + save |
|---|---|---|---|
| 34 個 root `xmlns:*` 宣告 | 全部丟，重建只剩 `w` + `r` | 同左 | bit-exact 保留 |
| `word/theme/theme1.xml`（含中文 font fallback） | 丟 | 丟 | bit-exact |
| `word/people.xml` + `commentsExtended/Extensible/Ids` | 丟 | 丟 | bit-exact |
| 多人 review 的 `<w:ins>` / `<w:del>` track changes | 全部 accept 或全部丟 | 視版本而定，通常損毀 | 結構化保留，可透過 MCP `accept_revision` / `reject_revision` 操作 |
| `<w:commentRangeStart>` 跨段 anchor + 回覆鏈 | 退化成 plain text 引用 | comment 退化成單層 | 完整 thread 保留 |
| Zotero 的 `customXml/itemX.xml` citation database | 丟 | 丟 | bit-exact |
| `<w15:presenceInfo>` 共編 metadata | 丟 | 丟 | bit-exact |
| `glossary/document.xml` boilerplate | 丟 | 丟 | bit-exact |
| 13 個 fontTable entries（中文 fallback chain）| 重建為 Latin-only | 同左 | bit-exact |
| 嵌入字型 binary（`fonts/font1.odttf`） | 丟 | 丟 | bit-exact |

**作者體感**：
- pandoc / python-docx 之後 → 「我的論文壞了」
- macdoc 之後 → 「完全看不出有任何工具碰過，除了那一個被指定要改的字」

這不是「macdoc 做得比較好」，是 **macdoc 完成了任務，其他工具完成不了**。

---

## 5. 為什麼這在 LLM 時代特別重要

過去 20 年，「Word document automation」的市場長這樣：

| Use case | 既有工具的 fit |
|---|---|
| 把學生繳交的 .docx 自動轉成 PDF | pandoc / textutil / LibreOffice headless 完美 fit |
| 讀 .docx 提取純文字進 search index | pandoc / textract 完美 fit |
| 從 template 生成新的 .docx（mail merge）| python-docx / docx.js 完美 fit |
| 把 markdown 寫入新的 .docx | pandoc / md-to-word 完美 fit |

這些 use case **共同特徵**：產出的 .docx 是 **新檔案**，不是某個既有作者的既有檔案。
作者沒有期待「這個檔案還是我的」——他期待的是「這個 PDF / 這個 export 看起來合理」。

LLM agentic workflow 的興起改變了這個 use case：

| Use case | 既有工具的 fit |
|---|---|
| LLM 看作者的論文，找到一個段落幫他補一個引用 | **沒有工具能做** |
| LLM 看老師批註的論文，把錯字修掉但保留所有 track changes | **沒有工具能做** |
| LLM agent 連續修 50 個小錯，作者打開應該完全看不出工具碰過 | **沒有工具能做** |
| LLM 修一個段落但保留共編者剛留的 comment 與回覆鏈 | **沒有工具能做** |

這些 use case **共同特徵**：產出的 .docx 是 **作者既有檔案的 mutation**，
不是新檔案。作者期待「這還是我的檔案，只是被改了我同意的那一處」。

`AST-mediated conversion` 在這個 use case 下是 **wrong tool**，
因為它從根本架構上就不保證「沒被改的部分不變」。
即使 pandoc 加 100 個 patch 把 track changes / comments / theme / custom XML 全部支援了，
它還是會在某個 vendor extension 上漏。**maximum-coverage AST 的策略是 incremental，
infinite-coverage overlay 的策略是 categorical**。

ooxml-swift 的 dirty-tracked overlay 是 categorical 解法：
不論 OOXML spec 將來新增多少 vendor parts，
只要 typed model 沒有去 mutate 它們，它們就被 bit-exact 保留。
**這是架構層級的保證，不是「我們會努力支援」的承諾**。

---

## 6. 10 秒 demo 的 claim

> 「拿你導師批註過的論文 `.docx`，丟給 LLM 透過 `che-word-mcp` 改一個錯字。
> 導師打開檔案——看不出工具碰過。
> 他的批註、他的 track changes、他組織的範本連結、Zotero 的 citation database 全部完整。
> **任何其他工具都會破壞這個檔案**。」

學術圈使用者聽到這個 claim 會立刻知道為什麼重要。
而 pandoc / textutil / python-docx 的世界裡，這個任務是 **unanswerable**——
不是「做得不夠好」，是「結構上做不到」。

### 6.1 強版 demo（v0.20.3 後）

> 「拿你的論文 `.docx`（含 4-axis CJK fonts + tracked deletions + Zotero custom XML
> + `<w14:textOutline>` 文字效果 + `<w:caps>` 小型大寫 + `<w:shd>` 螢光標記），
> 丟給 LLM 改一個字。
>
> Open + edit + save 後：
>
> - **Unmodified parts**（theme / glossary / custom XML / fontTable / 嵌入字型）：
>   bit-exact，SHA-256 比對 0 diff。
> - **Modified part**（`document.xml`）：所有 RunProperties typed fields
>   （rFonts 4 axes、noProof、kern、3-axis lang）+ raw rPr children
>   （`<w14:textOutline>`、`<w:caps>`、`<w:smallCaps>`、`<w:spacing>`、`<w:position>`、
>   `<w:shd>`、`<w:bdr>`、`<w:em>` 等）+ tracked `<w:delText>` content
>   + whitespace `<w:t xml:space="preserve">` + **paragraph-mark `<w:pPr><w:rPr>`**
>   + **paragraph `w14:paraId` / `w14:textId` GUIDs** 全部保留。
>   Cross-cutting matrix-pin assertion 跑在 thesis fixture 上：5 個 preservation-class
>   ratio floors（rFonts/noProof/lang/kern/w14: 都 ≥ 90%）+ `<w:t>` char sum +
>   `<w:bookmarkStart>` count parity 全 PASS。」

⚠️ **Caveat（v0.20.3 狀態）**：modified `document.xml` 仍有 ~8.02% byte loss，
來自其他 w14:* attribute classes（如 `<w:r>` 上的 w14:* 屬性）。這些落地後
（separate follow-up SDD）loss 會 drop 到 < 5%——屆時可以正式 claim
「edit 一個字 → document.xml shrinks <1%（only the edit delta）」。

當前的 honest claim 是：「**typed + raw fallback 確保任何 sub-stack A/B/C/D/E 已涵蓋的
preservation class 都不會 silently 丟失**」——LOAD-BEARING by matrix-pin across
**5 preservation classes** spanning run-level + paragraph-level + paragraph-mark scope。

---

## 7. 與 lossless-conversion.md 的關係

兩份 doc 處理不同的問題：

| 文件 | 解決的問題 | 核心技術 |
|---|---|---|
| `lossless-conversion.md` | 跨格式轉換時不丟資訊 | 三通道 Marker（MD + Figures + Metadata）+ 分層輸出 |
| `structural-editing-paradigm.md`（本文） | 同格式編輯時不破壞既有檔案 | Dirty-tracked overlay save + bit-exact preservation of unmodified parts |

兩個原則互相補強：
- 從 .docx 轉到 .md 是 `lossless-conversion` 的範圍——目標是 reversibility（可以從 .md 還原回 .docx）
- 從 .docx 編輯後存回 .docx 是 `structural-editing-paradigm` 的範圍——目標是 preservation（沒改的東西數學上不變）

兩者都是 macdoc 對「documents 應該是 first-class、可信任的 LLM peripheral」這個願景的不同支柱。

---

## 8. 為什麼這是 paradigm shift 而非 incremental improvement

「revolutionary」的可驗證定義是：
- **不是**「做得比別人好」（incremental）
- **是**「做了別人做不到的事 + 別人想抄也得花同等時間」（paradigm）

依這個尺：

| Capability | Category |
|---|---|
| Word → Markdown export 品質比 pandoc 好 5% | incremental |
| Markdown 渲染速度比 textutil 快 3 倍 | incremental |
| **LLM 編輯真實 .docx 而不破壞 metadata 化石層** | **paradigm shift** |
| **Bit-exact preservation of N-1 parts when 1 part is modified** | **paradigm shift** |
| **將 verification gate 用在 OOXML library 的 round-trip 上**（#56 的 6-AI verify methodology） | **paradigm shift（process）** |

要 catch up 的對手需要：
1. 重寫 reader 為「parse 進 typed model + 保留原始 ZIP」雙軌（不是 AST 投影）
2. 重寫 writer 為「modifiedParts overlay merge」（不是從零重建）
3. 為每個 typed-managed part 建立精確的 dirty tracking
4. 處理 N+1 個 vendor extension parts 的 bit-exact passthrough
5. 建立可以 catch silent corruption 的 verification framework
   （這是 #56 R5-CONT-4 stack 的 5 sub-stack rounds 才收斂的東西）

這不是「半年的競品功能」可以追上的距離，是 **架構決策 × 累積驗證紀律** 的乘積。

---

## 9. 開放性 claim

把這份 doc 攤在學術圈、技術圈、Word power-user 圈面前的 claim 應該是：

> **「我們做了第一個讓 LLM 可以在真實世界 .docx 上做 byte-preserving 編輯的工具。
> 這個能力之前不存在。」**

這個 claim 是可以 falsify 的：
- 找一份有 track changes + comments + custom XML + 嵌入字型的真實 .docx
- 列出 10 個其他工具
- 跑 round-trip 測試 → SHA-256 比對未改動 parts
- 看哪個工具能保證 0 個 silent diff

預期結果：只有 macdoc 通過。
如果有任何其他工具通過，**他們應該得到 credit**——
但目前在 ooxml-swift v0.19.5 / che-word-mcp v3.13.5 之前，
這個 claim 的 falsifiability test 沒有對手通過。

---

## 10. 寫給未來的自己

如果三年後回頭看 macdoc 的歷史，
最值得保留的 architectural decision 不是 streaming、不是 modular layers、
也不是 233 個 MCP tools 的 surface area。

是這兩條 invariants：

> **Invariant 1（v0.13.0 onwards）**: 「unmodified parts must be bit-exact preserved
> through round-trip, by architecture, not by best-effort.」

> **Invariant 2（v0.20.1 onwards）**: 「modified parts preserve content equality across
> all enumerated preservation classes — typed + raw fallback ensures no element class
> is silently dropped, by architecture, not by best-effort.」

第一條（unmodified parts byte-preservation）是 #56 R5-CONT-4 stack 收斂出來的
architectural primitive：dirty-tracked overlay save。

第二條（modified parts content-equality）是 #58/#59/#60/#65/#66 的 9 sub-cycles 收斂
出來的 architectural primitive：typed + raw fallback at every parser raw-capture site。
具體地：
- Block-level：`BodyChild.bookmarkMarker` (typed) + `BodyChild.rawBlockElement` (catch-all)
- Run-level whitespace：`WhitespaceOverlay` byte-stream pre-scan
- Run-level rPr：`RFontsProperties` (4-axis) + `LanguageProperties` (3-axis) +
  `RunProperties.rawChildren: [RawElement]` catch-all
- **Paragraph-mark rPr**（sub-stack D #65）：`ParagraphProperties.markRunProperties`
  reuses `parseRunProperties` verbatim — schema 跟 run-level CT_RPr 一致，所以
  typed + raw 全部繼承
- **Paragraph w14:* GUIDs**（sub-stack E #66）：`Paragraph.w14ParaId` / `w14TextId`
  String? 平鋪 attribute passthrough，with empty-as-absent guard + escape discipline

兩條 invariants 加上 #56 R5-CONT-4 / #58 A-CONT-3 / #59 B-CONT-2-CONT / #60 C-CONT
/ #65 D / #66 E 這 9 個 sub-cycles 收斂出來的 verification methodology
（per-task gate + cross-cutting matrix-pin LOAD-BEARING + 6-AI cross-verify
+ counter-parity vs payload-parity test split），
是讓「LLM 可以信任地操作真實世界 .docx」這件事**可能發生**的三個必要條件。

其他都是執行細節。

### 10.1 Paragraph-level coverage（sub-stack D + E 後）

從 v0.20.2 (sub-stack D #65) + v0.20.3 (sub-stack E #66) 起，content-equality
invariant 從 run-level 擴展到 **完整的 paragraph + run scope**：

- `<w:pPr><w:rPr>`（paragraph mark formatting — pilcrow glyph 外觀）→ ✅ 涵蓋
- `w14:paraId` / `w14:textId`（paragraph revision-tracking GUIDs）→ ✅ 涵蓋

Matrix-pin 5 個 preservation classes 全部 LOAD-BEARING，loss 從 16.66% 降到 8.02%。

剩下的 ~8% 來自其他 w14:* attribute classes（如 `<w:r>` 上的 w14:* attrs）—
tracked as separate follow-up SDD。這些落地後 loss 預期 drop 到 < 5%，
屆時可以正式 ship 第 6.1 節「edit 一個字 → document.xml shrinks <1%」strong demo。

到時候第 6.1 節的「edit 一個字 → document.xml shrinks <1%」claim 就可以正式落地。


## Related: ooxml-edit-algebra capability

The architectural patterns described here (overlay save, dirty-tracking, Invariants 1+2, 5 preservation classes) are typed and formally contracted in the `ooxml-edit-algebra` capability spec at `openspec/changes/ooxml-edit-isomorphism-foundation/specs/ooxml-edit-algebra/spec.md` (see Spectra change `ooxml-edit-isomorphism-foundation` for the 9 ADRs that pin the contract).

This document remains the implementation-pattern reference; the capability spec is the normative contract.
