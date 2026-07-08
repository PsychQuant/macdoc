# Format-Alignment Coverage Baselines

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
