# genoffice round-trip 對照：substring-splice vs op log vs mutate-tree

> #143 產物。分析基準 pin 在 `reference/genoffice` @ upstream snapshot **2026-08-03（commit `4da673d`）**——
> upstream 是 snapshot-sync 模式，clone 會漂移，引用行號以該 commit 為準。
> 比較基準（per #143 Clarity Surface 裁決）：**byte-level fidelity 為主**，render 層只留一節（§8）不實測。
> 方法：三個 read-only 讀者分讀 `parse.ts` / `patch.ts`+`text-patch.ts` / `generate.ts`+tests；**genoffice 側主張皆附
> `檔:行`**，macdoc / python-docx 側標注文件或原始碼出處；`notes.ts`（僅核 import 與呼叫點兩行）、`theme.ts`、
> `section.ts`、`ink.ts`、`sources.ts` 未讀，涉及處明標「推測」（§9 誠實邊界）。
> genoffice 為 **Apache-2.0**（© Mainfunc, Inc.；GenOffice / Genspark 為其商標）。本篇為外部靜態分析評論，
> 未複製其原始碼；授權細節見 `reference/README.md`。

**一句話回答 #143 的原始問題**（「怎麼確保改寫後的文件還保留原本的 Word 格式，那是最難的事情吧」）：
genoffice 的答案是**繞開最難的事情**——沒動過的內容從原始 XML 逐字複製（不需要理解格式），只有動過的內容
才重新生成；而重新生成的保真範圍**恰好等於它詞彙表建模的範圍**，沒建模的（rsid、proofErr）在段落被**完整
重生**時靜默消失——主文 body 的編輯一律走重生路徑；手術式 text-patch 只掛在 comments / footnotes 通道（§3）。macdoc/ooxml-swift 攻的是更難的那半：重建出 byte-equal 的檔案且逐步「理解」每個形——代價是
事件溯源架構複雜度與誠實的低 coverage 起點。

## 1. genoffice 機制全覽（資料流）

```
.docx (Uint8Array)
  │ JSZip 解 zip；word/document.xml → .async('string') UTF-8 decode     parse.ts:88-92
  ▼
documentXml (JS string) ── scanBody(): regex + depth 計數器切 top-level    scan.ts:30-82
  │   body elements 為「字元 offset 範圍」{name,start,end}——刻意不用
  │   XML parser（檔頭註解：parse→serialize 會靜默改動未動的 bytes）      scan.ts:1-9
  ▼
Block[]：每個 block 帶 docxIndex（原文第幾個元素）+ originalXml（原文     types.ts:602-710
  │   slice）；語義抽取（格式、run）才用 fast-xml-parser，限單一 block    parse.ts:457,480
  │   範圍內——「邊界用笨掃描器保 byte 精確、語義用真 parser」雙層架構
  ▼
編輯（GUI）……未動的 block 原封不動
  ▼
saveDocx(SaveBlock[])（union 定義 patch.ts:59-73）
  ├─ isUnchanged？（blocks 全 original 且順序一致 + 26 個 save option     patch.ts:358-391
  │   欄位為空——其中 4 個接受空值、其餘要求 undefined，欄位間不對稱）
  │   → return originalBytes ← 唯一檔案級 byte-identity                   patch.ts:392
  ├─ kind:'original' → documentXml.slice(el.start, el.end) 逐字拼入       patch.ts:856-864
  ├─ kind:'generated'/'xml'/'image'/'chart' → 重生 XML fragment
  │   （手術式 text-patch 不在此路徑——只服務 comments/footnotes，§3）
  └─ zip 重組：document.xml 必重寫；14 個 part 條件式重寫；其餘 entry      patch.ts:1089-1131
      解壓後內容 byte-copy——輸出一律以 DEFLATE-6 重新打包，不保留          patch.ts:1183-1187
      原 entry 壓縮方式與 zip record bytes
```

三個容易誤讀的定位（讀 upstream README 看不出來、讀 code 才浮現）：

1. **錨定在字串層，不在 byte 層**。`bodyInnerStart/End` 與 block offset 是 UTF-8 decode 後 JS string 的
   **UTF-16 code-unit index**（賦值 `parse.ts:270`，型別 `types.ts:1006`；`scan.ts:19-24`），不是檔案
   byte offset。「byte-for-byte」依賴「decode → slice → re-encode」對 JSZip 能無損解碼的合法 UTF-8 可逆
   （malformed 序列、BOM 行為、非 UTF-8 編碼不在保證內）；`originalBytes` 這個名字容易誤導。
2. **保證的對象是「解壓後的 part 內容」，不是 .docx 檔案 bytes**。任何非 no-op 存檔都會（a）**嘗試** bump
   `docProps/core.xml` 的 `dcterms:modified` + `cp:revision`（`patch.ts:320-335,1084-1087`——part 與兩個
   tag 存在時生效；真實 Word 文件恆成立，合成 fixture 無此 part 故 `roundtrip.test.ts:28-67` 不需排除它），
   （b）以 DEFLATE-6 重新打包整個 zip、不保留原 entry 壓縮方式（Word 對 media 常用 STORE）與 record
   bytes——所以**檔案級 bytes 幾乎必變**。
3. **`kind:'original'` 也不是無條件保護**。三種情況會改寫 original block 的 bytes：sectionHf 的
   header-ref 注入（`patch.ts:879-884`）、`options.inks` 有值時全 block 過 `stripInkRuns`
   （`patch.ts:887-889`）、`revision` 包 `<w:ins>/<w:del>`（`patch.ts:895` 一帶）。

## 2. byte 保證的確切邊界（操作 → 失去 byte-equal 的範圍）

「未動的東西 bytes 不變」的實際邊界（精煉自 `patch.ts` 全讀，行號見各列）：

| 操作 / 觸發 | 失去 byte-equal 的範圍 | 行號 |
|---|---|---|
| **任何**非 no-op 存檔 | `docProps/core.xml`（modified/revision——**part 與 tags 存在時**；真實 Word 文件恆成立）＋ zip 容器層（DEFLATE-6 重打包） | 320-335, 1084-1087, 1183-1187 |
| 編輯任一段落 | `word/document.xml` 整 part 重建（未動 block 的**片段內容**仍逐字保留） | 1089-1099 |
| 多節 header/footer 差異化（sectionHf） | 對應 section-break 段落（**即使 kind:'original'**）＋ header/footer part（文字段落**整批重生**，僅 drawing/pict/object 段落保留原 XML；part 內**全是**文字段落時連 root 都用硬編碼 namespace 重建） | 879-884, 1230-1342, 1311 |
| `options.inks`（含空陣列！） | 每個含 ink run 的 block ＋ rels ＋ ink media entry | 887-889, 987-991, 1096 |
| comments | `comments.xml` 整 part 重拼（未改文字的 `<w:comment>` 元素 bytes 保留；`commentsExtended.xml` 則**完全重建、零保留**） | 1350-1390, 1393-1412 |
| numbering / styles upsert | 對應 part 以字串 splice 就地改寫（surgical，非 parse→serialize；wrapper 與未觸碰條目 bytes 保留），該 part 於 zip 層重壓。**注意 styles 的「upsert 既有 styleId」是整個取代**（見 §7） | 649-702, 205-246, 718-720 |
| 新增 image/chart | rels 整檔重寫；新 part 類型才動 `[Content_Types].xml` | 984-1082 |
| 完全無變更 | **無** —— `return originalBytes`，唯一檔案級 byte-identity 路徑 | 358-392 |

跟 ooxml-swift 對照時要抓住的差異：genoffice 的保證是**條件式 passthrough**（範圍隨觸碰面收縮，退化
發生時使用者不可見）；ooxml-swift 的 Stage B 是**重建後全 part-set byte-equal 的驗證 gate**（每次都證明，
不成立就是測試紅——退化在結構上不可能靜默發生），見 §5。

## 3. 詞彙層：被編輯段落的退化模式

未動 block 靠 raw 複製、與詞彙無關；**一旦段落被編輯**，重生 XML 的保真範圍就等於 `generate.ts` 的詞彙表：

| 詞彙 | genoffice 重生時 | ooxml-swift reverse 通道 |
|---|---|---|
| rsid 家族（`w:rsidR` 等） | **消失**——從 parse 就不讀入，`grep rsid src/` 零命中 | typed 表示，byte-equal 重現 |
| `xml:space="preserve"` | **無條件**加在每個 `<w:t>`（generate.ts:1968-2006）——非判斷式 | 依原文有無重現 |
| root namespace 雲 | `w:` 等主 prefix 依賴 root 宣告——root start tag 由原文 slice 保留、雲原樣存活；drawing fragment 的 `wps/a/wp` 自帶局部宣告；`xmlns:m` 由 patch.ts:931-934 事後補 root | root 詞彙 typed 化 |
| bookmarkStart/End | 保留，但 `w:id` 用名稱 hash **決定性重算**（generate.ts:904-909）——穩定但非原值 | passthrough marker，原值保留 |
| proofErr | **完全丟棄**（src/ 零命中） | passthrough marker |
| 段落邊框 `w:pBdr` | 段落格式被編輯時**整組正規化重造**（硬編碼 `sz=4 space=1 color=auto`） | **reverse 未支援**——不在 typed pPr 詞彙（`ReverseExtractor.extractPPr` 僅收 7 種子元素），含 pBdr 的 document.xml 整 part 留 raw、bytes 靠 raw floor；authoring 側另有 `ParagraphBorder` API |
| rPr/pPr 子元素順序 | `RPR_CHILD_ORDER`/`PPR_CHILD_ORDER` 明確 schema 順序表（generate.ts:591-635, 1436-1478）＋ Word 慣用 self-closing 極簡形 | canonical writer 對齊 |

**但 genoffice 有一個聰明的中間層**：`rawRPr`/`rawPPr` **格式 property（rPr/pPr 子元素）群組級
passthrough**——run/paragraph 的原始 rPr/pPr fragment 存起來，save 時 `mergeRPrModel` 逐群組判斷「這群
有沒有被編輯」，沒動的群組直接複製原始 fragment bytes，只有真的被改的群組才按 schema 順序重組
（`raw-rpr.test.ts` 驗證了十幾種非受管 property——caps/vanish/dstrike/bdr/themeColor/字元間距——在文字
編輯後原封不動）。這是「編輯了段落文字但沒動格式」情境下格式 bytes 存活的原因，粒度介於 ooxml-swift 的
「per-part 全有全無 gate」與「全 typed」之間。

`text-patch.ts` 再往下一層——**但注意它的掛載範圍**：呼叫點只有 comments（`patch.ts:1365`）與
footnotes/endnotes（`notes.ts:180-181`，帶 `stripFirstParaLeadingSpace: true`），**主文 body 的被編輯
段落不走這條、一律整段重生**。機制本身：段落內純文字替換用 common prefix/suffix diff 找出**最小觸碰的
`<w:t>` 區間**，區間外的 run 與所有非文字節點完全不動（text-patch.ts:138-213）；patch 完後**自我驗證**
（重新抽文字比對目標，不符回傳 null → fallback 整段重建，text-patch.ts:53-59）——文字結果不符就放棄
手術（防的是錯位輸出；「壞 XML」層級靠 fallback 重建兜底）。

## 4. 保真怎麼被「證明」

- **有真的 byte-equal 斷言，集中在少數核心測試**（50 個 `.test.ts` 中大多數走 re-parse 語意比對）：
  - `roundtrip.test.ts:20-26`——no-op 存檔 `expect(saved).toBe(bytes)`（同一個物件層級的相等）。
  - `roundtrip.test.ts:28-67`——**編輯一個段落後，其餘每個 zip entry `toEqual` 逐 byte 比對**，且未動
    block 的 `originalXml` 逐字出現在新 document.xml。這是「edit one, everything else untouched」
    不變量的直接測試，比「整檔重建相等」更尖銳。
  - `raw-rpr.test.ts:117-189`——同一不變量對**真實 Word 文件**跑（`describe.skipIf` 條件式讀一份
    gitignored 本機中文 docx，不進 CI），排除 document.xml 與 core.xml 兩個「本來就會動」的例外。
  - `comments/ink/sections/revisions.test.ts` 各自的 no-op round-trip 都斷言 `toBe(bytes)`。
- **Fixtures 是程式合成的**（`tests/helpers/build-docx.ts`，zip mtime 釘死 2026-01-01 保 byte-deterministic），
  真實 Word 文件只有上述一份 local-only。對照 ooxml-swift：合成 fixtures 進 CI ＋ 真實 template
  （`90_template_ja.docx` 134KB、thesis-fixture 1.7MB）env-gated 常態量測。

## 5. 三方對照表

| 軸 | genoffice（substring-splice） | ooxml-swift（op log + byte-equal gate） | python-docx（mutate-tree） |
|---|---|---|---|
| 核心策略 | 解析時字元 offset 錨定原文；存檔拼接「原文 slice ∪ 重生 fragment」 | XmlNode tree + op log；存檔重建，Stage B 全 part-set byte-equal 驗證；typed DSL 經 trial-rebuild gate 升級 | lxml tree 直接 mutate，序列化交給 lxml |
| byte 保證層級 | **條件式**：未觸碰的解壓後內容（§2 邊界表）；檔案級僅 no-op 短路 | **測試層 gate**：`macdoc word reverse` 重建檔的 Stage B 全 part-set byte-equal（`FormatAlignmentAcceptanceTests` 恆綠）＋ typed 升級的 trial-rebuild gate——非 runtime save 檢查 | **無**——XML part 一律經 lxml 重序列化（`part.py:221-222` → `oxml.py:53-59` `etree.tostring`），無 byte 保留路徑 |
| 詞彙未覆蓋時 | 未動 block 沒事；**被編輯 block 靜默退化**（rsid 消失、proofErr 丟、bookmark id 重算） | 整 part 誠實留 raw（0% coverage），bytes 仍對；升級須 byte-equal 證明 | 直接輸出 lxml 的形 |
| 退化可見性 | 未建模詞彙（rsid/proofErr）不可見；已入 rawRPr 群組的 property 有 `raw-rpr.test.ts` 守著 | 結構上不可能靜默（gate 紅 = 測試紅；coverage 數字誠實） | 無承諾——實務上 silent，直到 render 或結構測試才現形 |
| 歷史/重放 | 無 op log；SaveBlock 是單次快照 | oplog sidecar、replayable、slots（script-text ＋ op-level 替換） | 無 |
| 驗證基建 | 50 test 檔；byte 斷言集中 roundtrip/raw-rpr；真實文件 1 份 local-only | 1293+ tests（`func test`+`@Test` 計數，2026-08-14 實測 1296）；coverage 量測（90_template_ja document.xml 0%→**100%** per-part）；render probes（§8） | 成熟但無 byte 軸 |
| 架構成本 | 低-中：regex 字串管線，逐案例長出（fldChar/sectPr 判斷混用 substring 與 tree 查詢） | 高：事件溯源 + canonical writer + 三層方法學 | 低 |
| 適用場景 | GUI 編輯器「別弄壞使用者的檔」 | agent 工作流「與 Word 並行寫同一份檔 + 可追溯」 | 腳本式產生/修改，格式不敏感 |

三家其實在解**不同強度的問題**：python-docx 不承諾保真；genoffice 承諾「你沒碰的不變」（把難題縮小到
編輯點）；ooxml-swift 承諾「重建的檔案逐 byte 等於原檔，且逐步理解每個形」（正面攻堅）。genoffice 的
選擇對 GUI 產品是對的——使用者只在乎 Word 打開不跑版；macdoc 的選擇對 agent 基建是必要的——op log 與
byte-equal gate 是「AI 與人並行編輯 + 審計」的入場費（呼應 `docx-libraries-comparison.md` §7）。

## 6. 值得 ooxml-swift 借鏡的（5 點）

1. **no-op 短路**（`patch.ts:358-392`）：blocks 全 original 且零 option → 直接回傳原始 bytes，不再
   重新編碼或重組 zip（load 時的 decode 已發生）。macdoc 的 save path 值得確認是否有等價 fast path
   （無變更時跳過重建與 Stage B）。注意他們的教訓：26 個 option 欄位逐一檢查、且欄位間不對稱
   （`numbering: {}` 空物件就誤判有變更）——如果做，判準要集中定義，別散裝。
2. **屬性群組級 raw passthrough**（`rawRPr` merge）：介於「per-part 全有全無」與「全 typed」之間的
   中間粒度。ooxml-swift 目前 document.xml 是 per-part gate（一個 form-gap → 整 part 留 raw）；
   若未來想讓 thesis-fixture 這類含 `drawing/oMath/sdt` 的文件部分升級，「element-level 混合 channel」
   是已被 genoffice 驗證可行的設計點——但要保住我們的 gate 紀律（混合後仍須 trial-rebuild byte-equal）。
3. **「edit one, everything else byte-equal」測試不變量**（`roundtrip.test.ts:28-67`）：逐 zip-entry
   比對 + 未動片段逐字存在斷言。比「整檔 Stage B 相等」更能定位「是誰動了不該動的」。
   FormatAlignmentAcceptanceTests 可加一組這種形狀的 case。
4. **手術 patch 的自我驗證 pattern**（`text-patch.ts:53-59`）：patch → 重抽 → 比對 → 不符即 fallback。
   便宜且 fail-safe，slot 替換（op-level setRuns）已有渲染驗收，可考慮加這層「文字往返」自檢。
5. **雙層掃描器的佐證**（`scan.ts:1-9`）：他們用註解明說「XML parser 不可信任來 round-trip」，與
   macdoc「tree + byte-verified serializer」是同一判斷的兩種回應——這是跨實作的獨立確認，
   `native-macos-compat` 路線（不引 libxml 做 round-trip）站得住。

**不適用/不要學的**：regex 字串管線（我們有 byte-verified tree serializer——就保真「驗證」能力而言
嚴格更強；表達彈性是另一軸）；code-unit offset 錨定（依賴 decode/re-encode 可逆性，macdoc 用 tree +
trial rebuild 沒這個隱含假設）；zip 全檔重打包（macdoc 控制自己的 zip writer 時應保留 entry 壓縮方式
與順序——這是檔案級 byte-identity 的必要條件之一，非充分：timestamp/headers/deflater 版本仍可造成差異）。

**授權邊界**：以上皆為**設計層**借鏡（想法不受著作權保護）。若實作時要逐行對照移植 genoffice 程式碼
（例如 `mergeRPrModel` 的結構），先回 `reference/README.md` 的授權注意確認 Apache-2.0 NOTICE 義務。

## 7. 對 #142 的旁證（verify 後修正版）

genoffice 的 **numbering append**（`patch.ts:697-700`，既有條目 bytes 不動）與 **rawRPr/rawPPr 群組級
passthrough**（§3）示範「沒建模的子樹，搬運而非重建」的心法——修 #142 可參考。

**但 styles upsert 是反例，不是示範**：`patch.ts:718-720` 對既有 styleId 是**整個取代**——`buildStyleXml`
（`patch.ts:205-246`）純從 model 重新生成 minimal stub，該 style 原有的未建模屬性（`w:link`、
`w:uiPriority`、`w:next`、`w:basedOn`、`w:semiHidden`…）**全數被清掉**，且 regex 也匹配 Word 內建樣式
（upsert `Heading1` 會把內建定義換成 stub）。這正是 #142 tblPr 清空的同一個形狀。

所以對 #142 的正確定性是：**兩個獨立實作在「重建時丟掉沒建模的子樹」這個坑上各踩了一次**（genoffice 在
styles、macdoc 在 tblPr）——#142 不是孤例，是這類 mutate-rebuild 路徑的系統性風險，比「別人都做對了」
的版本更值得優先修。（本節初版誤把 styles 也寫成 append-only，經 verify 6-AI 抓出並更正；#142 上的
參照 note 已同步 errata。）

## 8. render 層（不實測，兩家處理方式）

- **genoffice**：測試裡**沒有** render 驗證（全樹 grep libreoffice/puppeteer/pixelmatch/screenshot 等
  render 設施 0 命中，僅 `xml-utils.ts:81` 註解順帶提及）——保真信心止於 byte/語意斷言，「Word 打開長
  什麼樣」交給 Word 自己。合理的產品取捨（GUI 使用者立刻會看到跑版），但意味著「未動片段 byte 對了 ≠
  被編輯段落版面對了」這件事他們沒有機制化的答案。
- **ooxml-swift**：第三層 render-effect-semantics——`render-effect-registry.md` 台帳（7 verified probes，
  no probe no claim）、gated perturbation probes（真實 Word + PDFKit 幾何量測）、visual diff harness、
  slot 換內容的渲染驗收（頁數/頁框/未動頁 pixel-equal）。這層是 macdoc 獨有的，也是「能拼寫 ≠ 理解
  渲染效果」區辨的機制化。

## 9. 誠實邊界

- `theme.ts`、`section.ts`、`ink.ts`、`sources.ts` **未讀**；`notes.ts` 僅核 import 與呼叫點兩行
  （`notes.ts:1` import `patchParagraphTexts`、`:180-181` 帶 `stripFirstParaLeadingSpace: true` 呼叫
  ——footnote/endnote 走 text-patch **已證實**，初版標「推測」經 verify 升級）。
- 行號對 snapshot `4da673d`；upstream snapshot-sync 活躍，re-pull 後行號會漂。
- 本筆記純靜態閱讀，**未實際執行** genoffice 或其測試；「測試怎麼斷言」的描述來自讀測試碼，非跑測試。
- 三個閱讀 pass 由 read-only agents 完成；verify 階段（6-AI）另抽查 40+ 條行號主張無一錯誤，並補驗
  python-docx（`part.py:221-222`/`oxml.py:53-59`）與 §8 的 universal negative。
- **Errata**：issue #143 body 初查寫「51 個 test 檔」為誤計（把 `tests/helpers` 目錄算入），實為 **50**。

## 相關

- [`reference/README.md`](../reference/README.md) genoffice 條目（clone 方式、授權注意、成熟度警語）
- [`docs/docx-libraries-comparison.md`](docx-libraries-comparison.md)（docx-js / python-docx / pandoc 的既有對照，本篇補上第四家）
- [`docs/format-alignment-baselines.md`](format-alignment-baselines.md)（ooxml-swift 欄位所有數字的出處）
- [`docs/render-effect-registry.md`](render-effect-registry.md)（§8 render 層台帳）
- #143（本筆記的 issue）、#144（xlsx 評估旁支）、#142（tblPr 清空，§7 旁證）
