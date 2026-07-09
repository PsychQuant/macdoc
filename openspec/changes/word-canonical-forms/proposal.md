## Why

format-alignment-engine（#130，已歸檔）交付了 dual-track pipeline 的第一步「複製」：真實 Word 文件 reverse → script → rebuild 全部 Stage B byte-equal。但第二步「用合法 typed operations 序列化」對 Word-authored 文件是 0% DSL coverage（自家 writer 產物 57.5%）——`ReverseExtractor` 在 Word 的 XML forms（rsid 屬性群、多命名空間 root、`xml:space`、rPr/pPr 長尾元素）上誠實 bail 到 raw channel。這使 `--slot` 對真實 template 不可用：slots 只能指定 DSL-spellable 段落，而真實文件的段落全在 raw channel。使用者的實用目標（拿日本心理學會 template 填新內容產生投稿文件）因此被擋住（#131）。

## What Changes

沿既有 trial-rebuild byte-equal gate（Decision 3，機制不變），擴充 extraction/serialization 詞彙讓真實 Word 文件的 document.xml 通過 gate 升級 DSL channel：

1. **Form-gap 量測**：`ReverseExtractor` 的 bail 點從粗分類（`rawReasons` class tag）細化為具體位置報告（元素/屬性/首個 bail 路徑），輸出 per-document gap 清單——後續詞彙擴充的優先序依據。
2. **Document root 參數化**：`emptyAuthoringDocument` 的根元素目前固定 `xmlns:w` + `xmlns:w14`；新增 typed 通道讓 reverse 抽取 reference 的 root attributes（全部 xmlns 宣告 + `mc:Ignorable`）並在 rebuild 時原樣重建。
3. **rsid 屬性群**：`ParagraphPayload` / `RunPayload` additive 擴充 revision-session-id 欄位（`w:rsidR` / `w:rsidRDefault` / `w:rsidP` / `w:rsidRPr` 等），reducer stamping 按 Word 的屬性順序。
4. **`xml:space="preserve"`**：`RunPayload` 加 flag，`<w:t>` 帶前後空白時 Word 會標注此屬性。
5. **rPr/pPr/sectPr 長尾詞彙**：由 form-gap 報告驅動的增量擴充（szCs/bCs/iCs、rFonts 的 hint/hAnsi/theme、docGrid、ind firstLineChars/hangingChars 等），以「90_template_ja 的 document.xml 完整升級」為完成判準——它需要哪些 forms 就做哪些。
5.5. **Inline-passthrough 標記**（task 1.2 量測後、經使用者 scope 決定加入，design Decision 6）：段落 inline content 擴充為有序序列，每項是 run 或「不透明 inline passthrough」逐字搬運標記元素（`bookmarkStart`/`bookmarkEnd`/`proofErr` 等）。這是有界的單一機制、非逐標記語意建模；byte-equal 靠原樣搬運保證。因升級 gate 是 per-part 全有全無，90_template_ja 的 document.xml 沒這塊就停在 0%。
6. **真實 template slot 驗收**：升級後 `--slot` 對 90_template_ja 指定 title/body、填新內容產生格式完整的新 docx（`template-content-slots` 的 title-and-body scenario 在真實 template fixture 上成立，env-gated）。

驗收（解 #131 Clarity Surface row 1）採雙軌：(a) 功能性——90_template_ja document.xml 升級 DSL 且 slot 可用；(b) 數值——該 part 的 per-part coverage 達 100% DSL（aggregate 隨之 = document.xml bytes ÷ 全部 XML bytes，誠實反映 sibling parts 仍 raw）。Stage A/B 恆綠由既有 UpgradeClassGuardTests + FormatAlignmentAcceptanceTests 機制保護。

Corpus 範圍（解 #131 Clarity Surface row 2）：MVP corpus = 兩個 env-gated 真實文件（90_template_ja 為完成判準、thesis-fixture 為獨立來源 sanity check——不同作者與 Word 版本，防詞彙過擬合單一 template）+ 合成 CJK fixture（CI 恆跑）。擴大 corpus 蒐集為 non-goal。

## Non-Goals

- **thesis-fixture 的完整升級**：它含 comments / bookmarks / headers-footers 參照等複雜結構，僅作 form-gap 量測與「升級不 regress」的 sanity 對象，不承諾 document.xml 升級。
- **Sibling parts 的 typed 化**（styles.xml / settings.xml / numbering.xml 等）：分母大宗但屬後續 phase（#131 已註記），本 change 它們留在 raw channel。
- **Word 版本相容矩陣**：不建多版本 Word 產物的 corpus；MVP 以現有兩個真實文件為準。
- **結構性角色推斷**：維持 strict mode（`template-content-slots` 既有 requirement），不做 slot 自動推斷。
- **非 leaf/paired 的 inline 結構**：inline-passthrough（5.5）只涵蓋自足的 leaf/paired 標記（bookmark、proofErr、未來 commentRange 等）。`hyperlink`（包住 runs）、`drawing`/`oMath`/`fldChar`/`sdt`（thesis-fixture 的結構）仍 out of scope。
- **coverage 數值上限追求**：aggregate 數字由 document.xml 佔比自然決定，不為衝高數字把未證明 byte-equal 的內容硬升級（Decision 3 不動搖）。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `ooxml-script-transcode`: 新增 Word-canonical form 詞彙 requirement（root 參數化、rsid、xml:space、長尾）與 form-gap 量測 requirement；Reverse extraction requirement 的涵蓋範圍從「自家 writer forms」擴至「量測驅動的 Word-canonical forms」。
- `ooxml-operation-log`: payload additive 擴充第二輪（rsid 欄位群、xml:space flag、document root attributes 通道），沿 #128 additive-only wire 紀律。

## Impact

- Affected specs: `ooxml-script-transcode`（modified）、`ooxml-operation-log`（modified）
- Affected code:
  - New: packages/ooxml-swift/Sources/OOXMLSwift/Transcode/FormGapReport.swift、packages/ooxml-swift/Tests/OOXMLSwiftTests/FormGapReportTests.swift、packages/ooxml-swift/Tests/OOXMLSwiftTests/RealTemplateUpgradeTests.swift
  - Modified: packages/ooxml-swift/Sources/OOXMLSwift/Transcode/ReverseExtractor.swift、packages/ooxml-swift/Sources/OOXMLSwift/OpLog/Operation.swift、packages/ooxml-swift/Sources/OOXMLSwift/OpLog/OperationLog+JSONL.swift、packages/ooxml-swift/Sources/OOXMLSwift/OpLog/OperationReducer.swift、packages/ooxml-swift/Sources/OOXMLSwift/OpLog/WordDocument+Authoring.swift、packages/ooxml-swift/Tests/OOXMLSwiftTests/UpgradeClassGuardTests.swift、packages/ooxml-swift/Tests/OOXMLSwiftTests/FormatAlignmentAcceptanceTests.swift、docs/format-alignment-baselines.md、CLAUDE.md
  - Removed: (none)
