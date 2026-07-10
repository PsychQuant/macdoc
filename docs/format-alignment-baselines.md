# Format-Alignment Coverage Baselines

> 方法學（三層階梯：複製 → 合法序列化 → 渲染理解）見
> [word-imitation-methodology.md](word-imitation-methodology.md)；本文件只記量測值。

format-alignment-engine（#130）的 dual-track 驗收基線紀錄（Decision 2：raw
channel 是 byte-equal floor，DSL coverage 是 imitation-ability score；
Decision 5：真實 template 走 `MACDOC_TEMPLATE_DIR` env-gate，一個合成
template 進版控）。

量測工具：`macdoc word reverse --coverage`（CLI）與
`FormatAlignmentAcceptanceTests`（ooxml-swift，含 env-gated real-template
案例）。**Coverage % = 經 typed DSL channel 重建且 byte-equal 證明過的
bytes ÷ 全部 XML bytes**（Q1 working answer：分母為所有 XML parts、
headline 為 aggregate）。Stage B（全 part-set byte-equal)自 Phase A 起在
所有 fixture 上恆綠 — coverage 反映的是「理解了多少」，不是「對不對」。

## Form-gap survey（2026-07-09，word-canonical-forms task 1.2）

`WordCanonicalMeasurementTests`（env-gated）對真實文件做 document.xml 全詞彙 survey，比對現行 extractor 支援集，列出「不支援 form」= Phase 2/3 的工作佇列（僅列 form 名稱，不含內容）。升級 gate 是 **per-part 全有全無**：document.xml 只要有一個不支援 form，整個 part 留 raw（0%）。

**90_template_ja.docx**（13 parts / 134,050 bytes / document.xml DSL: false）
- first form-gap：`paragraph-attrs @ w:p[0]/@w14:textId`
- 不支援元素（8）：`bCs, iCs, szCs`（rPr companion，trivial）、`docGrid, type`（sectPr child，trivial）、**`bookmarkStart, bookmarkEnd, proofErr`（inline 交錯標記，結構性）**
- 不支援屬性（52）：root namespace 雲（~30 個 `xmlns:*` + `mc:Ignorable`）、rsid 家族（`w:rsidR/rsidRDefault/rsidRPr/rsidP/rsidSect`）、font theme（`w:asciiTheme/hAnsiTheme/eastAsiaTheme/hint/hAnsi`）、`xml:space`、`w14:textId`、`w:firstLineChars/hangingChars/linePitch/code/id/name`

**thesis-fixture.docx**（39 parts / 1,746,868 bytes / document.xml DSL: false）
- 不支援元素（153）：含 `drawing, oMath, textbox, sdt, AlternateContent, fldChar, hyperlink, pict, graphic` 等——大量結構性複雜內容，**遠超本 change scope，僅作 no-regress sanity**（Non-Goal）

### Phase 2 後（2.1-2.4 落地）的 gap 前移

90_template_ja 的 first form-gap 從 `w:p[0]/@w14:textId`（Phase 1 基線）前移到 `w:p[0]/w:pPr/w:rPr`——段落屬性 / rsid / inline marker 已通過，卡在 **pPr 內嵌的段落標記 rPr**（paragraph-mark run properties）。3.1 長尾接手：pPr/rPr 結構 + 它連帶要求的 run-property 詞彙（bCs/iCs/szCs、rFonts asciiTheme/hAnsiTheme/eastAsiaTheme/hint/hAnsi、ind firstLineChars/hangingChars）。thesis-fixture 前移到 `w:pPr/w:snapToGrid`（同屬 pPr 長尾，但其 document 另有大量 out-of-scope 結構）。

## 量測值（2026-07-08，Phase A→D 實測）

| Fixture | 性質 | XML parts | XML bytes | Phase A | Phase B–D | Raw classes（殘留） |
|---------|------|-----------|-----------|---------|-----------|---------------------|
| synthetic five-layer | authoring-built（自家 writer 形；run rPr + paragraph pPr + 兩節 + 表格全開） | 4 | 2,134 | 0.0% | **57.5%** | sibling-part |
| synthetic CJK template | `CJKTemplateFixtureGenerator`（手寫 XML 形，兩節 + `w:cols num="2"` + eastAsia 字型 + 9 styles） | 6 | 6,919 | 0.0% | 0.0% | sibling-part, unsupported-form |
| `90_template_ja.docx` | 真實日文學術 template（env-gated；Word-authored，96 段落、兩節、16 styles） | 13 | 134,050 | 0.0% | 0.0% | sibling-part, unsupported-form |
| `thesis-fixture.docx` | 真實論文（che-word-mcp test-files；Word-authored，含 comments/headers/footers/numbering） | 39 | 1,746,868 | 0.0% | 0.0% | sibling-part（CLI 量測） |

## 數字解讀

- **57.5%（authoring-built）是升級機制的證明**：document.xml 經
  `ReverseExtractor` 的 trial-rebuild byte-equal gate 升級為 typed ops，
  五層（run rPr / paragraph pPr / sections / canonical tables / text+style）
  全部走 DSL channel 重建且 byte-equal。分母剩餘 42.5% 是 sibling parts
  （[Content_Types].xml、rels）— 它們尚無 typed 表示，於 raw channel 逐字
  搬運。
- **0%（手寫與真實 Word 文件）是誠實而非失敗**：Decision 3 不設
  canonical-form 豁免 — serializer 無法逐字重現的形（Word 的 root 命名空間
  集、rsid 屬性、空白排版）就留在 raw channel。Stage B 仍 byte-equal
  （raw floor 保證），但系統不謊稱「理解」了這些格式。讓真實文件的
  coverage 爬升需要 serializer 對 Word-canonical 形的長尾對齊，屬本
  change 之後的工作。
- **Raw classes 欄**來自 `ReverseExtractor.Result.rawReasons`（spec:
  "records which content classes remain on the raw channel"）：
  `sibling-part` = 非 document.xml 的 parts；`unsupported-form` =
  document.xml 含 typed 詞彙之外的形（foreign root attrs、空白 text
  nodes、未支援元素）；其他可能值如 `table`（非 canonical 形表格）、
  `hyperlink`、`byte-mismatch`（extraction 成功但 trial 重建 bytes 不等）。

## 量測值（2026-07-09，word-canonical-forms #131 完成後）

ooxml-swift v1.4.0 落地 Word-canonical 詞彙（root namespace 雲、rsid 家族、
`xml:space`、inline passthrough markers、pPr/rPr 長尾、docGrid/section-type/
pgSz、CRLF prolog）。真實 Word 文件的 document.xml 首次從 raw floor 升級到
typed DSL channel。

| Fixture | 性質 | document.xml channel | doc.xml per-part | aggregate | 變化 |
|---------|------|----------------------|------------------|-----------|------|
| synthetic five-layer | authoring-built | dsl | — | **57.5%** | 不變（本 change 針對 Word-authored） |
| synthetic CJK template | 手寫 XML fixture | raw | 0% | **0.0%** | 不變（residual：`non-element-content`） |
| `90_template_ja.docx` | 真實日文學術 template（env-gated） | **dsl** | **100.0%** | **53.5%**（71,771 / 134,050） | **0.0% → 53.5%** ✅ |
| `thesis-fixture.docx` | 真實論文（out-of-scope） | raw | 0% | **0.0%** | 不變（no-regress） |

**Headline**：`90_template_ja` 的 document.xml 由 0% → **100%**（aggregate
0% → 53.5%）。document.xml 是最大的單一 part（71,771 bytes），其位元組全部
經 typed DSL channel 重建且 Stage B byte-equal。`--slot` 在此 template 上端到端
可用（op-level slot：raw-form 格式化段落的 `setRuns` run text 可被 call-site 值
替換，其餘位元組不變）。

### 殘留 form-gap（sign-off）

- **`90_template_ja` 的 46.5% raw 餘量 = sibling parts**（`styles.xml` 32,778 B、
  `settings.xml` 7,928 B、`theme1.xml` 7,084 B、`fontTable.xml`、
  `endnotes/footnotes.xml`、`docProps/*`、rels、`[Content_Types].xml`）。這些
  非 document.xml 的 parts 尚無 typed 表示，於 raw channel 逐字搬運
  （`sibling-part` class）。屬本 change scope 之外（#131 只鎖定 document.xml
  的 Word-canonical 詞彙），Stage B 仍恆綠。
- **synthetic CJK template 停在 0%**：residual `non-element-content` —— 手寫
  XML fixture 在 element 之間有 extractor 尚無法逐字重現的 non-element 內容
  （縮排空白），留 raw。honest 0%，非退化。
- **thesis-fixture 停在 0%**：document.xml 含大量 out-of-scope 結構
  （`drawing`/`oMath`/`sdt`/`textbox`/`fldChar`/`hyperlink`/`AlternateContent`
  …），遠超 #131 scope，僅作 no-regress sanity（Non-Goal）。

## Render semantics（2026-07-10，render-effect-semantics 第三層）

第一、二層證明的是**忠實再序列化**（byte-equal），不是**理解渲染效果**。
第三層把「理解設定 X」操作化：能預測改動 X 的可量測渲染後果，且 gated
perturbation probe 對照真實 Word 渲染驗證通過。理解台帳在
[docs/render-effect-registry.md](render-effect-registry.md)（no probe, no
claim；probe 沒過就誠實標 `unverified`，不放寬容差）。

**Registry snapshot（2026-07-10，Word 16.110.3）：7 verified / 0 unverified**

| # | 欄位 | 預測 | 實測 |
|---|------|------|------|
| 1 | `docGridLinePitch` 360→480 | Δpitch +6.0 pt | Δ 6.96 pt（絕對 pitch ≈ 名目 ×1.16）|
| 2 | `spacingBefore` 0→240 | Δgap +12.0 pt | Δ 12.0 pt 精確 |
| 3 | `spacingAfter` 0→240 | Δgap +12.0 pt | Δ 12.0 pt 精確 |
| 4 | `spacingLine` auto 240→360 | pitch ×1.5 | ratio 1.507 |
| 5 | `indentFirstLineChars` 0→100 | 首行右移 ≈ 字級 pt | Δ 10.5 pt 精確 |
| 6 | `sizeHalfPoints` 21→42 | pitch ×2 | ratio 2.0 精確 |
| 7 | margins +567 twips | 頁框不變；首行下移 28.35 pt | 頁框不變；Δy 28.32 pt |

**Probe 賺到的理解**（byte-equal gate 永遠看不到的行為，詳見 registry）：
Word 對相鄰 before/after spacing 取 **max 而非相加**；docGrid `lines` 的
絕對 pitch ≈ 名目 ×1.16；A4 頁框被量化為 595.2×841.92 pt（非 595.3×841.9）。

**Slot 渲染驗收**（scenario (d)，雙 gate `RUN_WORD_INTEGRATION=1` +
`MACDOC_TEMPLATE_DIR`）：90_template_ja 換入等長 sentinel 後——頁數相等、
每頁頁框相等、被替換頁 median line pitch 在容差內、未動頁 pixel ratio
0.00043 ≪ threshold 0.005。投稿文件工作流自此有渲染層保證。

跑法：

```bash
# 幾何量測（無 Word、無 gate）
cd packages/ooxml-swift && swift test --filter RenderGeometryTests

# Perturbation probes（維護者機器）
RUN_WORD_INTEGRATION=1 swift test --filter RenderEffectProbeTests

# Slot 渲染驗收（雙 gate）
RUN_WORD_INTEGRATION=1 MACDOC_TEMPLATE_DIR=<dir> \
  swift test --filter RealTemplateUpgradeTests
```

## Visual diff 實測（2026-07-08，task 4.3 gated harness）

| Scenario | 結果 | 數值 |
|----------|------|------|
| identical documents pass（reference vs byte-equal rebuild）| PASSED | 全頁 pixel ratio = 0.0 |
| layout drift is caught（去掉兩欄 sectPr）| PASSED | page 1 ratio 0.1107 ≫ threshold 0.005，具名頁碼 |

跑法：`RUN_WORD_INTEGRATION=1 swift test --filter VisualDiffTests`（需 Microsoft
Word）。注意 **`~/.cache/ooxml-swift-visual-diff` 目錄不可刪除**——sandbox 版
Word 的資料夾存取授權（Grant Access）綁在這個固定路徑上；刪除重建會重新
觸發阻塞式授權對話框，需再人工按一次「允許」。

## 重現方式

```bash
# CLI（任意 docx）
macdoc word reverse file.docx --to-mdocx /tmp/out.mdocx.swift --coverage

# 合成 fixtures（CI 可跑）
cd packages/ooxml-swift && swift test --filter FormatAlignmentAcceptanceTests

# 真實 template（維護者機器）
MACDOC_TEMPLATE_DIR=~/Academic/projects/active/sample_size_planning/article2_impossibility_of_rule_of_thumb/docs \
  swift test --filter FormatAlignmentAcceptanceTests
```
