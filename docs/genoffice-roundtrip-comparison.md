# genoffice DOCX 窄幅修補與 macdoc round-trip 對照

> 分析基準：`genspark-ai/genoffice` snapshot `4da673d4dfa994bd0b4a9bc43430e4a058a17c61`
>（2026-08-03）。本文件以 byte-level fidelity 為主；render fidelity 另節討論，
> 不把兩者混為同一種保證。

## 結論先行

genoffice 為研究 DOCX round-trip 所需的原始碼，**實質上完整公開**：
`packages/docx-engine/src/` 共 10,958 行 TypeScript，runtime 只依賴
`jszip` 與 `fast-xml-parser`；`tests/` 有 50 個 `*.test.ts` suite，加上一個
`helpers/build-docx.ts`，合計 51 個 TypeScript 測試檔。`ee/` 只有授權與
說明檔，沒有藏住 DOCX engine 的另一份實作。

這不等於「整個 Genspark 產品都完整開源」。雲端 AI service、選配的瀏覽器
driver 與內部完整開發歷史不在 snapshot 裡；但它們不參與本文件研究的 DOCX
格式保留路徑。因此，對「能不能研究它如何保留 Word 格式」的答案是**可以**，
對「整套產品是否一行不漏」的答案則是**不能如此宣稱**。

genoffice 的核心不是把整份 `document.xml` parse 成 tree 後再序列化，而是：

1. 掃描原始 `document.xml`，記住 `<w:body>` 每個直屬元素的字串範圍。
2. 用 `docxIndex` 把 editor block 對回原始範圍。
3. 儲存時，以 `SaveBlock` 決定逐塊複製原始 substring，或重生一個新 fragment。
4. 只替換需要異動的 ZIP part；其他 entry 的**解壓內容**原樣搬運。

這個設計很有效，但保證必須說精確：

- **零修改**：直接回傳輸入的同一份 `Uint8Array`，整個 DOCX 檔案逐位元組相等。
- **有修改**：未動的 top-level body block 在 UTF-8 解碼／重編碼前提下保留
  原始 XML substring；未動 ZIP entry 的解壓內容保持相等。
- **不保證**：修改後的 ZIP 容器位元組、被重生 block 的詞彙形、所有 XML
  part 的全域 byte equality，或 Word render equality。

這與 ooxml-swift 的 dual-track 不同。ooxml-swift 把 raw channel 當全 part-set
的 byte-equal floor；只有 typed operations 從受控基線重放後也能逐位元組重建
該 part，才讓它通過 trial-rebuild gate 升級到 DSL channel。兩者都保守，但
genoffice 的保守單位是「原始 substring／entry」，ooxml-swift 的保守單位是
「raw part／通過證明的 typed part」。

## 分析範圍與證據

本次閱讀下列 pinned snapshot 檔案：

| 檔案 | 本文件使用的證據 |
|---|---|
| `packages/docx-engine/src/scan.ts` | `<w:body>` 直屬元素的原始字串範圍 |
| `packages/docx-engine/src/parse.ts` | `originalBytes`、`documentXml`、`bodyInnerStart/End`、`docxIndex` 與 Block tree |
| `packages/docx-engine/src/patch.ts` | `SaveBlock`、無修改快速路徑、substring splice、part 搬運與 JSZip 重組 |
| `packages/docx-engine/src/text-patch.ts` | comment／footnote／endnote 的 paragraph／`w:t` 窄幅文字修補與 self-check |
| `packages/docx-engine/src/generate.ts` | 被改 block 的 OOXML 重生、raw pPr/rPr 合併與 schema order |
| `packages/docx-engine/src/xml-utils.ts` | parse-tree fragment 是 semantic fidelity，不是 byte fidelity |
| `packages/docx-engine/tests/roundtrip.test.ts` | 無修改全檔相等、其他 entry 與未動 block 相等、重讀成功 |
| `packages/docx-engine/tests/text-patch.test.ts` | 未動 paragraph/run 格式保留、跨 run 修補與無安全錨點時拒絕 |
| `packages/docx-engine/tests/raw-rpr.test.ts` | 未建模 rPr token 保留與 modeled group 局部重建 |
| `packages/docx-engine/tests/schema-order.test.ts` | 重建後 CT_PPr／CT_RPr 子元素順序 |
| `packages/docx-engine/tests/mce-namespace.test.ts` | 新增 MCE 內容的 `Requires` prefix 可解析性 |

所有 genoffice 路徑均相對於 `reference/genoffice/`。該目錄是只讀 shallow clone，
不進 macdoc 版控；要重現請先依 [reference index](../reference/README.md) clone，
並 checkout 上述 commit。python-docx 對照則固定在 v1.2.0 snapshot
`e45454602b53e8e572b179ccf1c91093ec9f4ed7`。

## 完整資料流

### 1. Parse：同時建立可編輯模型與原始範圍

`parseDocx(bytes)` 先讓 JSZip 讀 package，再把 `word/document.xml` 讀成字串。
`scanBody(documentXml)` 不重建 XML tree；它以可容忍 quoted `>` 的 tag scanner，
找出 `<w:body>` 每個直屬元素的 `[start, end)`。每個區段都記錄：

- `docxIndex`：原始 body 直屬元素的序號；
- `originalXml`：該元素的原始字串 slice；
- `id: b<index>`：editor session 內的 bookkeeping ID。

parser 仍會把 paragraph、table、image、field 等投影成 Block tree，供 UI 顯示與
編輯；但這棵 tree **不是 untouched serialization 的來源**。真正的保真來源是
`ParsedDoc.internal` 內的：

- `originalBytes`
- `documentXml`
- `bodyInnerStart`
- `bodyInnerEnd`
- `extras.elements[]` 的原始範圍

這是整個策略最重要的分層：semantic model 可以不完整，只要未碰到的內容仍能
以 `docxIndex` 回到原始 slice，就不需要懂它也能保留它。

SDT 是一個值得注意的特例。parser 可把 `w:sdtContent` 中的 paragraph/table
投影成可編輯 block，同時保存 shell 的 open/close XML；重生內層內容時再包回
原 shell。這比單純丟掉未知 wrapper 更保守，但一旦進入重生路徑，內層仍受
generator 詞彙能力限制。

### 2. Editor boundary：`SaveBlock` 明說每個 block 的來源

儲存輸入不是一棵要整體 serialize 的 tree，而是一列 `SaveBlock`：

| kind | 行為 |
|---|---|
| `original` | 依 `docxIndex` 擷取原始 `document.xml` substring |
| `generated` | 將 editor 的 `GeneratedBlock` 重生為新 paragraph XML |
| `xml` | 插入 caller 提供的自含 OOXML fragment；可帶原 block index |
| `image` | 產生 drawing、media entry 與 relationship |
| `chart` | 產生 chart part、workbook 與 relationship |

刪除就是不把原 block 放進 `finalBlocks`；搬動就是調整 `original` block 的順序；
插入則加入 `generated`／`xml`／media block。`docxIndex` 是對原始 snapshot 的位置
錨點，不是跨儲存、跨 Word session 的 stable element identity。

### 3. Save：原始 slice 與重生 fragment 拼接

`saveDocx` 先做完整的 no-change 判斷。block 順序、revision 與所有 `SaveOptions`
都沒有異動時，它直接 `return originalBytes`。測試用 reference identity
`expect(saved).toBe(bytes)` 鎖住這條路徑，因此不是「解壓後內容一樣」，而是
連同 ZIP metadata、壓縮結果在內的同一份輸入 bytes。

有任何修改時，資料流如下：

1. 重新從 `originalBytes` 開啟 JSZip。
2. `original` block 執行 `documentXml.slice(start, end)`。
3. `generated` block 走 `generateParagraphXml`；`xml` 直接插入；media 類型配置
   新 relationship 與 part。
4. trailing hidden `w:sectPr` 預設仍取原始 slice；只有 page/section options
   明確要求時才做局部字串修補。
5. 組成：`原 document.xml body 前綴 + blocks.join('') + 原 body 後綴`。
6. 依 options 窄幅修改 rels、content types、settings、styles、comments、notes、
   header/footer、theme 等指定 parts。
7. 對其他 entry 讀出 `uint8array` 後放入新 JSZip，保留 entry date，最後以
   DEFLATE level 6 產生新容器。

因此，修改後「其他 zip entry 逐 byte 複製」指的是 **entry payload 解壓後的
bytes**，不是原壓縮 stream、central-directory 順序或整個 `.docx` 檔案 bytes。
另外 `docProps/core.xml` 若含 `dcterms:modified`／`cp:revision`，一般儲存會更新
時間與 revision；round-trip test 也明確把它列為例外。

### 4. `text-patch.ts`：比 block 更窄的文字修補

`patchParagraphTexts` 主要服務 comment、footnote、endnote 等 rich-text entry：

1. depth-aware 找出每個 paragraph slice；
2. 將各 paragraph 的 `w:t` 串成 plain text；
3. paragraph 沒變就直接沿用原 slice；
4. paragraph 有變就算 common prefix/suffix，只替換碰到變更區間的 `w:t`；
5. 其他 run、hyperlink、image、field 與格式 shell 保留；
6. 重新抽出文字做 postcondition；不等於目標文字就回傳 `null`。

paragraph 數量改變或找不到安全的 `w:t` 錨點時，它不猜測，直接回傳 `null`，
由 caller 決定是否整段重建。這個「窄幅嘗試 + 可驗證 postcondition + 明確
放棄」的模式，比其 regex 實作細節更值得借鏡。

## Byte 保證的精確邊界

| 情境 | 實際保證 | 不保證 |
|---|---|---|
| 無任何修改 | 回傳原 `Uint8Array`；整個 DOCX byte-identical | 無 |
| 有修改、未動 ZIP entry | 解壓後 entry payload 相等，entry date 被帶入新容器 | 原 compressed bytes、ZIP entry order、central directory、整檔 bytes |
| `original` body block | 原 `document.xml` substring；UTF-8 round-trip 下詞彙形保留 | 非 UTF-8 XML 宣告、編碼層完全不變 |
| `generated` body block | generator 支援的語意、schema order 與保留的 raw fragments | 原 `<w:p>` attrs、所有原 run/text 詞彙形、block byte equality |
| `text-patch` touched paragraph | 未動 paragraph/run shell 保留，文字 postcondition 通過 | 被碰到的 `w:t` opening tag 與 entity／`xml:space` 詞彙形 |
| 指定 part option | 只改該 helper 處理的區域，部分 helper 會保留其他 substring | helper 未建模卻落在重建範圍內的內容必然保留 |

`scan.ts` 的註解很準確：parse→serialize 會改變 attribute order、self-closing
form 與 entity form，所以未動內容不走 serializer。但相反命題不成立：**被改
block 不會因為鄰居保留原 bytes，就自動獲得 byte equality**。

### 測試實際證明了什麼

`roundtrip.test.ts` 的三個主要 gate 是：

- no edit 直接比較同一份 `Uint8Array`；
- 編輯一個 paragraph 後，除 `document.xml` 外的 entry payload 逐一比較，且
  `document.xml` 內每個未動 block 都仍包含原 `originalXml`；
- 輸出再交給 `parseDocx`，確認仍能解析。

它沒有宣稱修改後整個 ZIP byte-equal，也沒有用 Microsoft Word 當 parser 或
renderer。`text-patch.test.ts` 主要以原 substring/token 仍存在、格式 shell
仍存在、輸出文字正確來驗收；`raw-rpr.test.ts` 與 `schema-order.test.ts` 驗證
未建模 token 與 CT_RPr／CT_PPr 順序。這些都是有用的結構證據，但不是 render
oracle。

## Word-canonical 邊界：躲掉還是踩到

### Root namespace 雲：多數靠「不碰 root」躲掉

`document.xml` 的 `<w:body>` 前後部分直接取自原字串，所以 root namespace
declarations、`mc:Ignorable`、XML declaration 與 body 外 whitespace 通常不經
serializer。這是 pass-through，不是 typed model 已理解每一個 namespace。

生成 OMML 而原 root 缺 `xmlns:m` 時，`patch.ts` 會以字串方式補宣告；新增
DrawingML/VML MCE 時，builder 在 `mc:AlternateContent` 局部宣告所需 prefix，
`mce-namespace.test.ts` 只驗 `Requires` 所指 prefix 在該 scope 可解析。

判斷：**既有 namespace 雲主要是躲掉重建；新增的已知 namespace 才有專門
builder。**

### `rsid`、`w14:paraId`、`w14:textId`：untouched 保留，generated paragraph 會掉

原 block 整段搬運時，paragraph opening tag 上的 rsid 家族與 w14 IDs 自然保留。
但 `generateParagraphXml` 的 opening tag 固定從 `<w:p>` 開始，Block model 沒有
一般化保存這些 attrs；因此重生 paragraph 會捨棄它們。comment path 對
`w14:paraId` 有局部特例，不等於一般 body paragraph 已完整建模。

判斷：**未動時躲掉；一般 touched block 仍踩到。** 這與 #131 要求 serializer
能逐字拼回 rsid/root attrs 才通過 typed gate，是兩種不同契約。

### `xml:space`：語意保守，但詞彙形會 canonicalize

原 block 的 `xml:space` 原樣保留。新 run 或被 `text-patch` 碰到的 `w:t` 一律
輸出 `xml:space="preserve"`，即使文字不一定需要它。這通常比漏掉前後空白安全，
但不是原詞彙形 byte-equal；原本沒有 attribute 或使用不同 entity form 時會改變。

判斷：**語意上主動保守，byte-level 上仍是重生。**

### `pPr`：文字修改可保存原 slice；格式修改採 group replacement

parser 用 depth-aware scanner 擷取 paragraph 自己的完整 `<w:pPr>` 原字串，
`GeneratedBlock.rawPPr` 可直接放回。純文字修改因此能保留 paragraph property
詞彙形。若 caller 修改段落格式，`mergePPrFormat` 只重建它管理的 property
groups，其餘 child 沿用原 XML，並依 CT_PPr order 合併。

判斷：**比整段重生更細，但保證取決於「變更欄位分組」是否完整。**

### `rPr`：保留長尾，但不是原始 byte slice

run property 的 `rawRPr` 來自 `fast-xml-parser` tree 再經 `serializeXNode` 輸出；
該 helper 的註解明說是 semantic fidelity，不是 byte fidelity。它會維持 parse
order，但會正規化 entity、empty element form 等。`mergeRPrModel` 逐 group
比較 modeled value：相等的 group 沿用這份 reserialized raw XML，變更的 group
重建，未建模 child 保留。

判斷：**它解的是「不丟長尾格式」，不是「touched run 的 rPr 原 bytes」。**

## 三方對照

| 面向 | genoffice | ooxml-swift / macdoc | python-docx |
|---|---|---|---|
| 核心表示 | Block tree + 原字串 range | XmlNode tree + stable ElementID + operation log | lxml tree + typed wrapper |
| 未動保真 floor | top-level substring + entry payload | raw channel／preserved archive，全 part-set Stage B | 沒有 byte floor；XML part 由 lxml serialize |
| touched 內容 | 窄幅 patch 或 fragment 重生 | typed op 套到 tree；只有 trial-rebuild byte-equal 才宣稱 DSL 拼寫能力 | 直接 mutate lxml element 後 serialize |
| 全檔 byte-equal | 只有 no-op 快速路徑 | 比較 XML part set；規格明確排除 ZIP container equality | 無 |
| typed 誠實 gate | 無統一 gate；依 helper 測試與保守 fallback | per-part trial-rebuild byte-equal；失敗留 raw 並記 form-gap | 無；能 serialize 不代表保留原詞彙形 |
| 身分穩定性 | `docxIndex` 只對當次原 snapshot | paraId／bookmark／library UUID 等 stable ID | wrapper 指向當次 lxml node，無持久 stable ID |
| 歷史／重放 | 無 op log | operation log 可持久化、重放、undo/redo、Word import | 無 op log |
| 未知 OOXML | 原 block／entry 未動即可 pass-through | tree/raw channel pass-through；typed 升級需 gate | 常可留在 lxml tree，但所有 XML part 仍重新序列化；typed setter 也可能重建 subtree |
| 測試主張 | substring／entry payload、token、schema order、reparse | Stage A/B byte equality、coverage、form-gap、真實 Word gated probe | 主要驗 typed API 與 XML 語意，不提供原檔 byte contract |
| 維護成本 | 每種 edit helper 都要定義安全邊界；regex/string scan 邊界多 | op taxonomy、reducer、serializer、stable ID、sync 與 gate 成本高 | API 最直接，但無歷史與 byte 證明 |

python-docx 的差異可從其 save path 直接看出：`PackageWriter` 重新產生
`[Content_Types].xml` 與 relationships，XML part 的 `blob` 由
`serialize_part_xml()` 呼叫 `lxml.etree.tostring()`；它沒有原 substring channel。
這不代表每次都會遺失未知元素，而是**沒有承諾保留原始 XML bytes**。

## 哪些做法值得 macdoc 借鏡

### 值得採用的原則

1. **把 source span provenance 當 first-class metadata**：tree node 除了 stable
   identity，也可保留原始 byte range；窄幅 writer 能明確證明哪些 bytes 沒碰。
2. **preservation unit 要可列舉**：genoffice 的 `SaveBlock.kind` 一眼看出原始、
   重生或 media；macdoc 的 certificate／coverage 也應逐 part／node 列出來源。
3. **先窄幅修補，再驗 postcondition**：`patchParagraphTexts` 重新抽文字核對，
   不成立就回傳 `null`。macdoc 的 specialized patch 可採同樣 fail-loud 介面，
   再交由較高層 policy 決定 raw carry、typed rebuild 或拒絕。
4. **no-op 快速路徑直接回原 bytes**：這是最強、最便宜、也最不含糊的
   round-trip 證明。
5. **測試分開鎖 preservation 與 validity**：既比對未動 entry/block，也重新
   parse；macdoc 再加 trial rebuild 與 Word oracle，形成更完整的證據梯。

### 不宜直接移植的部分

1. **`docxIndex` 不能取代 stable ID**：位置只對單次 snapshot 成立，無法支撐
   Word 雙向同步、跨 session op log 或 non-conflicting merge。
2. **regex/string scan 不宜成為通用 OOXML tree**：它很適合範圍清楚的 splice，
   但 namespace lexical scope、MCE、nested revision/table/SDT 的組合會讓每個
   helper 都背負新的 parser 邊界。
3. **「保留鄰居」不能取代 touched-region gate**：被改 block 若重生，仍需
   像 ooxml-swift 一樣對可宣稱的層級做 trial-rebuild／structural diff；否則
   只能說鄰居沒變，不能說目標格式完整。
4. **JS 字串 offset 不適合直接搬到 Swift Data**：TypeScript 的 range 是
   UTF-16 string index；Swift 若要強化 byte 證明，應以原始 `Data` 的 byte range
   或 parser 提供的 source offsets 為準，避免非 ASCII 與編碼轉換造成誤解。
5. **JSZip 重組不是 container preservation**：macdoc 現行 Stage B 明確比較
   part set 而不比較 ZIP 容器，這個契約比含糊說「zip 逐 byte 複製」更準確。

## Render 層：三者都不能只靠 byte 說自己「看懂」

genoffice docx-engine 的測試會重讀輸出、檢查 schema order、relationship、token
與原 substring；本次閱讀未發現以真實 Microsoft Word 渲染後做幾何或像素差異
的 gate。因此它能證明特定結構沒有被意外改寫，不能由此推出「被改內容在 Word
中的排版效果與預測完全一致」。

python-docx 同樣沒有 render oracle。ooxml-swift/macdoc 則把這個問題明確放在
第三層：byte-equal 與 typed trial-rebuild 之外，使用 gated Microsoft Word
render probes、PDF 幾何量測與 effect registry。這個成本較高，但主張也不同：
前兩層說「保留／會拼」，第三層才說「知道設定改變後人會看到什麼」。

所以三方比較的正確結論不是「哪一家保證 Word 看起來一樣」，而是：

- genoffice 以 substring locality 將**未動範圍**的風險壓得很低；
- python-docx 提供便利的 tree mutation，但不建立 byte 證明；
- macdoc 額外付出 op log、trial-rebuild 與 render oracle 成本，換取可重放、
  可量測且能限制主張範圍的證據鏈。

## 最終判斷

genoffice 證明了一件重要的事：對 AI 編輯器而言，不必先完整理解 Word 所有
詞彙，仍可藉由「原始區段是預設，重生是例外」大幅降低格式破壞面。這與
macdoc 的 raw-channel-first 原則方向一致，而且 `text-patch` 的 postcondition
做法值得直接吸收成設計原則。

但它沒有取代 op log 路線。substring splice 不提供跨 session stable identity、
歷史、重放、Word import merge 或 typed 理解度量；touched block 也沒有統一的
byte-equal gate。macdoc 應借鏡它的**局部性與原始範圍 provenance**，不應把
positional anchors 或 regex serializer 當成 op log／XmlNode tree 的替代品。
