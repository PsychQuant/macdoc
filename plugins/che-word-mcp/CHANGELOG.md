# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> ⚠ This file was bootstrapped by `changelog-tools:changelog-init` from the
> `plugin.json` description field. Section categorization is best-effort —
> review and refine `Added` / `Changed` / `Fixed` etc. as needed.

> **回填說明（2026-08-20）**：以下 4.0.x 條目是**事後從 commit 重建**的，不是當時寫下的。
> 內容來自各次 bump 的 commit message（`ac9ea54` / `7ac1401` / `c30798f` / `b89790c` /
> `7ffc050`），那些訊息本身寫得夠詳細，所以重建的是敘述、不是事實。
>
> **仍然缺的：3.21.0、3.21.1、3.22.0、3.23.0 四個版本沒有條目。** 那四次 bump 只留下
> 一行 commit subject（marketplace sync / script-pipeline tools / binary+shell bump），
> 資訊量不足以寫出對得起「紀錄」二字的條目。刻意留白並在此標明，勝過用 subject 擴寫成
> 看起來完整、實際上是我推測的內容。要查那段請直接看
> `git log -- plugins/che-word-mcp/`。

## [4.0.11] - 2026-09-03

### Changed

- `binary_version` 4.0.8 → **4.0.9**；shell 4.0.10 → 4.0.11。binary 4.0.9 只是把 ooxml-swift 下限升到 3.6.3：
  3.6.2 的 graft 對 root 只宣告 `xmlns:w` 的文件會寫出未宣告前綴的 `document.xml`（Word 拒開，
  PsychQuant/macdoc#175 verify R3 codex F1），3.6.3 在 root 補宣告；另修 `PackageInspector` 巢狀 part 的
  OPC rels 路徑。真實 Word 文件與 `create_document` 產出的文件 root 本來就宣告齊全、不受 3.6.2 影響。

## [4.0.10] - 2026-09-03

### Changed

- `binary_version` 4.0.6 → **4.0.8**；shell 4.0.8 → 4.0.10（4.0.9 未出貨：其三個版本檔在 `26c434f` 被漏出 commit，
  見下方 Fixed 第二項；本條目併入）。
- plugin / marketplace description 不再寫死「Built on ooxml-swift v2.0.1」（已過時三個大版），改為指向 binary repo 的
  `Package.swift`（PsychQuant/macdoc#175 verify R1 表 #14）。

### Fixed

- **submodule pin 指向不存在的 commit**（macdoc#175 R1 表 #1）。4.0.8 的 `7bf161b` 把 `mcp/che-word-mcp` 釘在手打的
  `56ac6c8674…`（真值 `56ac6c8a71…`），`clone --recurse-submodules` 必壞。`26c434f` 以 `rev-parse` 讀真值修正。
- **版本檔漏出 commit**（macdoc#175 R2 表 #1）。`26c434f` 的 commit message 宣稱 shell 4.0.9 / binary 4.0.7，實際只含
  gitlink；remote `binary_version` 停在 4.0.6，wrapper 據此下載帶 R1 四條 blocking 的舊 binary。本 commit 補齊並直接指向 4.0.8。
- binary **4.0.7 + 4.0.8**：image-consistency gate 的 baseline 改 open-time 快照、autosave / shutdown flush / checkpoint
  三側門全部過 gate（checkpoint 顯式路徑一律過、含 `allow_orphan_images` 逃生口）、fail-closed inspection、`.unsaved`
  sidecar 不覆蓋既有檔＋清理、短路改看 header/footer 圖；ooxml-swift **3.6.1 + 3.6.2**：`appendParagraph` 白名單補齊
  Paragraph 與 Run 層、不可投影的 append 改 graft 進 live tree（不再整份 typed 重序列化）、`PackageInspector` per-part
  比對＋註解／`>`／巢狀 parts 三修。細節見各 binary repo CHANGELOG。

## [4.0.8] - 2026-09-01

### Changed

- `binary_version` 4.0.5 → **4.0.6**；shell 4.0.7 → 4.0.8。

### Fixed

- **append 模式插圖不再於存檔時靜默消失**（PsychQuant/macdoc#175）。binary v4.0.6 把
  ooxml-swift 依賴下限升到 3.6.0（ooxml-swift#128：`appendParagraph` 快路徑以正面白名單
  `isOpPayloadRepresentable` 把關，含 `<w:drawing>` 的段落一律走 typed fallback）。實際
  事故：7 張圖的交付文件少了 4 張，插入／列表／存檔全程回報成功。

### Added

- **存檔前 image-consistency gate**（`E_IMAGE_CONSISTENCY`）。`save_document` /
  `finalize_document` 寫檔前先序列化檢查：若會寫出本 session 新產生的孤兒 image
  relationship（#175 簽名），拒絕寫檔並回報孤兒 rId 與三計數；開檔時既有的孤兒以
  open-baseline diff 放行；新參數 `allow_orphan_images: true` 供刻意刪圖段落的情境放行。
  拒絕發生在任何磁碟寫入之前，session 存活。autosave / shutdown-flush 刻意不設 gate。

## [4.0.7] - 2026-08-20

### Changed

- `binary_version` 4.0.4 → **4.0.5**；shell 4.0.6 → 4.0.7。

- **五個文件保護工具改為誠實失敗**（binary #172）。`protect_document` /
  `unprotect_document` / `set_document_password` / `remove_document_password` /
  `restrict_editing_region` 過去都回報成功卻什麼都沒寫；現在會失敗，並在訊息中指名缺少的
  OOXML。

  **這是刻意讓功能「變得不可用」**，因為它本來就不可用——差別只在使用者是否被告知。一位
  在寄出前把文件設成唯讀保護的人，過去拿到的是一份未受保護的文件**外加一句成功訊息**；
  他會從收件人口中發現。錯誤讓他多繞一步，假的成功讓他失去他正想保護的東西。

  `set_document_password` 尤其值得提：它過去把**密碼長度**回傳出來，讀起來像密碼已被接收
  並套用。

### 驗證

對**下載回來的 release binary** 實測：`protect_document` 與 `set_document_password`
皆回 `isError: true`，訊息分別指名 `<w:documentProtection …/>` 與「整個 .docx 容器的
OLE Compound Document 加密（非 OOXML part）」。sha256 相符、Gatekeeper 通過、tag 指向的
commit 與推送的 HEAD 一致。

## [4.0.6] - 2026-08-20

### Changed

- `binary_version` 4.0.3 → **4.0.4**；shell 4.0.5 → 4.0.6。

  與 4.0.5 那次不同，**這一版對使用者有實際行為改變**：

  - **新建文件不再以「追蹤修訂模式 ON」出貨**（binary #170）。`create_document`
    產出的文件不再在 `settings.xml` 帶 `<w:trackChanges/>`，收件人在 Word 打開時
    「追蹤修訂」按鈕不再是亮的。建檔後第一件事做 `disable_track_changes` 的習慣可以
    停了。要追蹤修訂改為明確傳 `track_changes: true`。
  - **四個工具不再截斷沒人要求截斷的文字**（binary #178）。`get_paragraphs` /
    `list_footnotes` / `list_endnotes` 預設回傳完整文字，且**不再對沒被截斷的內容
    附加省略號**——內容只有 `Hi` 的段落不會再印成 `Hi...`。`list_all_formatted_text`
    的 60 字上限一併移除。四者都接受 `summarize`。
  - **欄間距不再被改寫**（binary 帶 ooxml-swift 3.4.0，#176）。A4 表單只做
    `update_cell` / `replace_text` 這類非版面編輯後存檔，`<w:cols w:space>` 保持原值。

### 驗證

對**下載回來的 release binary** 實測（非本機建置）：`create_document` 回報
`Track changes disabled`、存出的 `settings.xml` 無 `<w:trackChanges/>`、
`get_paragraphs` 對兩字段落輸出 `[0] (Normal) Hi` 而非 `Hi...`。sha256 相符、
Developer ID 簽章與 notarization 通過、tag 指向的 commit 與推送的 HEAD 一致。

## [4.0.5] - 2026-08-20

### Changed

- `binary_version` 4.0.2 → **4.0.3**（帶進 ooxml-swift 3.3.0）；shell 4.0.4 → 4.0.5。
- README 修正兩處過期宣稱（見下方 Fixed）。
- 本 CHANGELOG 回填 4.0.x 全線（見開頭回填說明）。

### Fixed

- **README「版本」段整段過期，且與自己矛盾**。相鄰兩行同時錯：`Plugin shell: v3.20.2`
  （實際 4.0.4）與 `Binary: v3.20.0（CheWordMCP，242 tools）`（實際 4.0.2 / 245）。
  後者還與本文第 3 行的「245 個工具」直接打架——使用者信哪個數字，取決於他從哪裡開始讀。

  改法不是把數字換新，而是**移除寫死的版號**，改指向 `plugin.json` 的 `version` /
  `binary_version`。理由與 4.0.3 移除 ooxml-swift 版號那次相同：每次 bump 都要記得回來
  改的東西，遲早不會被改到——上面那兩行就是證據。

  順帶記錄一個檢查缺口：plugin-update 的 README staleness 六信號抓到了 binary 那行
  （靠工具數比對），但**沒抓到 shell 版號那行**，因為沒有任何信號在比那個字串。

### 誠實邊界：binary 4.0.3 對現有工具表面沒有行為改變

上游 ooxml-swift#106 修的是 **typed view**（`body.children`），不是位元組。本 server
觸及該修法的唯一路徑是 `execute_script`，而它只回傳 `written` / `verified` /
`broken_parts`，從不讀 `body.children`。所以這一版是乾淨的依賴前移，**不是**把某個修法
送到使用者手上。價值在於下一個真正的修法不必同時扛一次未經測試的依賴跳版。

## [4.0.4] - 2026-08-19

### Changed

- `binary_version` → **4.0.2**，帶進 ooxml-swift 3.2.0：cell inside borders 在 mutation
  後存活，`tcBorders` 子元素依 schema sequence 輸出（PsychQuant/ooxml-swift#99）。

Shell 之所以也跟著動到 4.0.4，是因為**只改 `binary_version` 不會觸發 `plugin update`**；
不動 shell 版號，修正就停在一個沒人拉取的 release 裡。

## [4.0.3] - 2026-08-19

### Fixed

- **CLAUDE.md 不再寫死 ooxml-swift 版號**。收尾的 doc-sync 掃描第三次抓到這行過期——它
  點名一個上游版本，所以每次 ooxml-swift 發版都會讓它失效，再修一次只是預約第四次。改成
  指向 binary repo 的 `Package.swift`，那才是真正的 source of truth。

`binary_version` 維持 4.0.1（binary 未變）。

## [4.0.2] - 2026-08-19

### Changed

- `binary_version` → **4.0.1**，帶進 ooxml-swift 3.1.0 的目錄保護修法
  （PsychQuant/ooxml-swift#109）。

Shell 到 4.0.2 而 binary 到 4.0.1：兩者刻意解耦，而這次必須分開動——binary 發版了但
shell 本身沒有改動。不動 shell 版號，`plugin update` 就看不到新東西、wrapper 也不會
重新檢查。

## [4.0.1] - 2026-08-19

### Fixed

- CLAUDE.md 的更正在 shell 標成 4.0.0 之後才落地，已經更新過的人不會再拉到。

`binary_version` 維持 4.0.0——binary 沒變，這兩個欄位刻意解耦。

## [4.0.0] - 2026-08-19

### Changed

- 指向已簽章 + notarized 的 che-word-mcp **4.0.0** binary。沒有這一步，binary 存在但
  沒有任何安裝器搆得到它，release 等於只做了一半。

### Note

同一次改動也在 macdoc 的兩份 skill 標註了相反方向的問題：那兩份文件描述了 overwrite gate
與「失敗不破壞」，但**帶著這些行為的 macdoc CLI 當時尚未發布**（最新 tag 仍是 v0.6.0）。
出貨的文件承諾多於出貨的二進位——這正是 #180 / #181 在講的缺陷本身。當時的處置是在文件裡
明寫版本需求與「0.6.0 使用者實際會得到什麼」，而不是安靜放著。

## [3.20.2] - 2026-07-02

### Fixed

- 文件一致性 refresh（PsychQuant/macdoc#118）：tool count 統一為 **242**（binary v3.20.0 `tools/list` 實測；原散落 145/218+/235）、ooxml-swift 版本對齊 v0.24.0、`~/bin` 路徑宣稱改 `.bin-cache`（接 #117）、README 版本區塊對齊 shell 3.20.2 / binary 3.20.0；`.mcp.json` / `plugin.json` / marketplace description 縮為短摘要（release history 移交 CHANGELOG）。

### Changed

- **Plugin-scoped 安裝目錄（PsychQuant/macdoc#117）**：binary 與 sidecar 從共享 `~/bin/` 遷至 **plugin 層級**的 `.bin-cache/`（`<marketplace>/<plugin>/.bin-cache/`，即 version 目錄的上一層）— 跨 marketplace / 跨 plugin 碰撞 by construction 不可能，且跨 shell 版本持久（保留 #116 sidecar 短路，shell-only bump 不重下載；binary_version 變更才重下載）。舊 `~/bin` 副本不主動刪除（可能為使用者手動安裝），首次啟動 stderr 註記一次。

## [3.20.1] - 2026-07-02

### Security

- Wrapper 改用硬化模板（同 che-pdf-mcp / che-pptx-mcp v0.1.0）：強制 sha256 + requirement-based codesign（Team OU 6W377FS7BS）+ exec-time 重驗 + pinned version 不 fallback latest（PsychQuant/macdoc#112 verify R1/R2）。

### Changed

- **shell/binary 版本解耦（PsychQuant/macdoc#116）**：新增 `binary_version` 欄位（=3.20.0，binary release tag 來源）；`version` 自此為 shell 版本、可獨立 bump。本版（3.20.1）即吸收 #112 的 wrapper 硬化變更。wrapper 對缺 `binary_version` 的舊 shell fallback 讀 `version`（backward compat）。

## [3.20.0] - 2026-05-04

### Added

- **Cross-document OMath splice MCP tools** ([#160](https://github.com/PsychQuant/che-word-mcp/issues/160)) — two new MCP tools wrapping [PsychQuant/ooxml-swift v0.24.0's `spliceOMath` API](https://github.com/PsychQuant/ooxml-swift/issues/57):
  - `splice_omath_from_source` — single-OMath low-level splice between two documents. Source via `source_path` (Direct mode read-only) or `source_doc_id` (Session); target requires session-mode `doc_id`. Position via `atStart` / `atEnd` / `afterText` / `beforeText` with optional `anchor` + `instance`. `omath_index` 0-based, joint document-order across both source carriers. `rpr_mode`: `full` (default verbatim) / `omathOnly` (whitelist rFonts/sz/lang/bold/italic) / `discard` (empty). `namespace_policy`: `lenient` (default — accepts `mml:` vs `m:` prefix mismatch with same URI per ECMA-376) / `strict` (any mismatch throws).
  - `splice_paragraph_omath_from_source` — paragraph-level batch convenience. Splices all OMath blocks from source paragraph in source-document order via auto-derived ~10-char context anchors. Returns count or `contextAnchorNotFound(omath_index, snippet)` with partial-success state.

### Changed

- Bumps `ooxml-swift` dep `0.21.0` → `0.24.0` (required for `spliceOMath` API).

### Tests

- `Issue160SpliceOMathFromSourceTests` — 8 cases covering Direct/Session source modes, atEnd / afterText positions, error taxonomy, batch mode, rPr discard.
- Full suite: 297 tests, 0 failures, 9 pre-existing skips.

### Use case

Unblocks [kiki830621/collaboration_guo_analysis#17](https://github.com/kiki830621/collaboration_guo_analysis/issues/17) Phase 7 inline-math restoration — 522 inline OMath blocks restored from `_raw.docx` into `碩士論文-rescue-swift-v317.docx` (95.5% paragraph coverage in first pass; 100% after suffix-anchor fallback in [collaboration_guo_analysis@43465a6](https://github.com/kiki830621/collaboration_guo_analysis/commit/43465a6)).

## [3.19.0] - 2026-05-04

### Fixed — `find_inline_math_gaps` caption detection ([#136](https://github.com/PsychQuant/che-word-mcp/issues/136))

Two-layer detection. **Layer 1**: `Paragraph.style?.lowercased().contains("caption")` — Word's canonical OOXML signal. **Layer 2**: 7 English prefixes (Table / Figure / Tab. / Fig. / Listing) + 9 CJK prefixes (incl. U+3000 ideographic space) + CJK no-separator regex `^[表圖图]\d` + label-only `表格`/`图表`. Digit-after-prefix guard rejects body sentences like "Table reservations are required...". `isLikelyTableCaption(_:)` signature changed `String → Paragraph`; private → internal for `@testable`. PR [#157](https://github.com/PsychQuant/che-word-mcp/pull/157), 17 new tests.

### Fixed — `estimate_paragraph_for_page` structural weights v2 ([#142](https://github.com/PsychQuant/che-word-mcp/issues/142))

Walker upgrade: `getParagraphs()` → `collectStructuralBlocks()` returning `[StructuralBlock]` enum (`.paragraph` / `.table` / `.imageOnlyParagraph(drawingCount:)` / `.displayEquationParagraph`). Per-block weights (12pt thesis calibration): table = `tableRows × avgCellChars` (200/row fallback), image = +200 chars/drawing, display eq = 120 chars. New `structural_breakdown` field with 9 sub-fields. `method` field bumped `char_count_heuristic` → `char_count_heuristic_v2`. ~95× thesis figure-counting accuracy improvement. PR [#158](https://github.com/PsychQuant/che-word-mcp/pull/158), 6 new tests + #89 backward-compat (text-only fixtures unchanged).

### Backward compat preserved

- `getParagraphs()` UNCHANGED — 30+ other callers unaffected
- `paragraph_count` semantics: body-paragraph blocks only (paragraph_index math invariant preserved)
- `chars_per_page` override path UNCHANGED
- Existing #89 / #94 tests pass; only `Issue89...Tests:29` `method` literal updated to `_v2`

### Verified

- `swift build`: clean (only pre-existing deprecation warnings)
- `swift test`: 289 pass, 9 pre-existing skips, 0 failures
- 1 P3 follow-up filed: [#159](https://github.com/PsychQuant/che-word-mcp/issues/159) (display-eq fixture limitation, non-blocking)

## [3.17.8] - 2026-05-01

### Changed
- closes PsychQuant/che-word-mcp#98 — insert_equation MCP handler refactored across 3 commits (91506f8/357cbe7/339ab77).
- **BREAKING:** BREAKING for inline mode callers: pre-fix inserted NEW paragraph; post-fix appends OMML run to EXISTING paragraph at paragraph_index.
- Suite: 236 → 243 tests, 0 failures, 9 pre-existing skips.
- **BREAKING:** Backward compatible except inline-mode BREAKING (documented)

### Deprecated
- Pre-fix three structural defects: (1) silent-clamp on out-of-range paragraph_index via non-throwing insertParagraph(_:at: Int) — tool reported success but inserted at wrong location; (2) lib's #84/#91 InsertLocation overload + InsertLocationError.inlineModeRequiresParagraphIndex / .invalidParagraphIndex(Int) structured errors never reached MCP callers (handler self-built OMML and bypassed lib); (3) inline mode (display_mode=false) always created a NEW Paragraph(runs: [eqRun]) instead of appending OMML run to the EXISTING paragraph at paragraph_index. v1 (91506f8) tried delegating to lib but Codex 6-AI verify caught P1 regression: lib's Document.insertEquation overload internally uses @available(*, deprecated, ...) MathEquation flat output (Field.swift:301) — emits truncated '(a)/(b' AND nested <w:p><w:p> invalid OOXML. v2 (357cbe7) unified handler — both latex AND components paths use MathComponent.toOMML() for structurally correct OMML; display mode routes through lib's throwing insertParagraph(_:at: InsertLocation); inline mode handler-side appends OMML run to existing paragraph. v3 (339ab77) restored eqPara.properties.alignment = .center for display mode.
- Migration: use display_mode=true for 'new paragraph with equation' or call insert_paragraph + insert_equation separately. 7 NEW Issue98InsertEquationLibBypassTests pin contracts (5 RED→GREEN scenarios + 2 quality regression tests including unzip -p document.xml verifying <m:f> structure + centering survives + deprecated '(a)/(b)' pattern absent). 6-AI verify ensemble (5 Claude reviewers + Codex gpt-5.5 xhigh) caught both P1 regressions in v1; Codex sanity check on v2 caught the centering P2. 6 P2/P3 follow-up issues filed (#105-#110).

## [3.17.7] - 2026-05-01

### Added
- Bilateral mirror coverage for direct-child OMML at 4 wrapper positions (<w:p> direct child for Pandoc display math / <w:hyperlink> direct child / <mc:Fallback> direct child / nested wrapper combos), plus 2 NEW library-wide spec capabilities.
- Spectra change flatten-replace-omml-bilateral-coverage. 2 NEW spec capabilities promoted to openspec/specs/: ooxml-paragraph-text-mirror (mirror invariant + ReplaceResult informative refusal contract) + ooxml-library-design-principles (Correctness primacy + Human-like operations as foundational normative invariants for all ooxml-swift mutators).
- Write side: NEW public API WordDocument.replaceTextWithBoundaryDetection returns ReplaceResult enum (.replaced(count:) / .refusedDueToOMMLBoundary(occurrences:) / .mixed(replacedCount:, refusedOccurrences:)) with Occurrence(matchSpan:, ommlSpans:) carrying flattened-text coordinates.

### Changed
- ooxml-swift dep bump 0.21.10 → 0.21.11 — closes 5-issue cluster PsychQuant/che-word-mcp #99 + #100 + #101 + #102 + #103.
- Read side: flattenedDisplayText walks direct-child OMML at all 4 wrapper positions with source-XML position ordering.
- Mirror invariant — asymmetric by design: reads include OMML visibleText (anchor lookup universe extends to math); writes treat OMML as opaque structural units (refuse cross-OMML mutation rather than silently delete equations).
- Decision 4 raw passthrough preserved: direct-child OMML stays in Paragraph.unrecognizedChildren / HyperlinkChild.rawXML(_) / AlternateContent.rawXML — no parser change, no writer change, round-trip fidelity unaffected.
- MCP impact: replace_text and other anchor-lookup tools now find paragraphs containing direct-child OMML at all 4 wrapper positions; existing replace_text MCP tool unchanged (backward-compatible).
- Tests: 236 passing che-word-mcp / 813→829 ooxml-swift (+16 in Issue99FlattenReplaceOMMLBilateralTests).

### Fixed
- Pre-fix Paragraph.flattenedDisplayText AND Document.replaceInParagraphSurfaces shared a symmetric blind spot: direct-child <m:oMath>/<m:oMathPara> (not wrapped in <w:r>) was silently dropped → anchor lookups against paragraphs containing display math silently 0-matched.
- Backward compatible — strict superset of pre-fix behavior

## [3.17.6] - 2026-04-30

### Changed
- ooxml-swift dep bump 0.21.9 → 0.21.10 — closes PsychQuant/che-word-mcp#104.
- MCP impact: update_all_fields now finds and updates SEQ fields in canonical 5-run form (post-roundtrip / native Word emission); list_captions benefits transitively via shared FieldParser.
- Verified by 6-AI ensemble (5 Claude reviewers + Codex gpt-5.5 xhigh) — 4 PASS / 2 WARN / 0 BLOCK; production reproducer rescue-swift-v317.docx via DocxReader path confirmed working. 5 P3 follow-ups filed in ooxml-swift (#29 SEQ Table coverage / #30 multi-paragraph counter / #31 multi-SEQ same paragraph / #32 DoS hardening / #33 discriminator invariant).
- Tests: 236 passing che-word-mcp / 809→813 ooxml-swift (+4 sub-tests in Issue104FieldParserCanonicalFormTests).

### Fixed
- Form-level FieldParser canonical 5-run fldChar fix (orthogonal to v3.17.5's #94 container-level fix).
- Pre-fix update_all_fields returned silent no-op ('no SEQ fields found') on docs containing valid SEQ paragraphs at body top level when fldChar block was emitted in canonical 5-run form (each <w:fldChar>/<w:instrText>/<w:t> in its own <w:r> sibling — what DocxReader produces post-roundtrip and what native Word always emits).
- Pre-fix worked only on in-memory wrap_caption_seq output before save.
- Two ooxml-swift commits land via this dep bump: 537de62 FieldParser two-phase parse (Phase-1 baked form + Phase-2 parseFiveRunSpan state machine probing both Run.rawXML and Run.rawElements per recognizedRunChildren = ['rPr','t','drawing','oMath','oMathPara'] allowlist) + 58fe4f9 P1 sub-fix surfaced by 6-AI verify (Logic + Devil's Advocate runtime test): canonical-branch Run.text rewrite was silently overridden by Run.toXML() rawXML short-circuit; new rewriteCanonicalCachedText helper splices new value into embedded <w:t> while preserving <w:rPr> + xml:space=preserve, AND keeps Run.text in sync.
- Backward compatible — strict superset of pre-fix behavior

## [3.17.5] - 2026-04-30

### Changed
- Known incompleteness (3 follow-ups filed): ooxml-swift#25 header/footer/footnote/endnote SEQ scans still flat .paragraphs view; ooxml-swift#26 FieldParser.parse(paragraph:) misses inline SDT/hyperlink/fieldSimple/alternateContent surfaces; ooxml-swift#27 verify-with-user-fixture for real thesis docx roundtrip; plus ooxml-swift#28 refactor candidate (extract BodyChildVisitor protocol).
- Verified by 6-AI ensemble (5 Claude reviewers + Codex gpt-5.5 xhigh).
- Tests: 236 passing che-word-mcp / 805→809 ooxml-swift.
- Backward compatible except #87 documented behavior change

### Removed
- ooxml-swift dep bump 0.21.8 → 0.21.9 — triple #87 + #93 + #94 release. #87 (Comment.paragraphIndex flat-counter, observable behavior change): list_comments paragraph_index now consistently 0-indexed against get_paragraphs() flat list; pre-fix off-by-N for any docx with non-paragraph BodyChild siblings before commented paragraph; callers manually compensating with paragraph_index - 1 must remove compensation. #93 (wrap_caption_seq SEQ inherits source position, caption visual fix): pre-fix 「圖 4-1：xxx」 became 「圖 4-：xxx1」 because new SEQ run had position=nil while source-loaded preText/postText had position>0; one-line fix seqRun.position = preRun.position; insert_bookmark=true × source-loaded paragraph still has same gap (filed PsychQuant/ooxml-swift#24, default insert_bookmark=false unaffected). #94 (update_all_fields traverses .table and .contentControl containers): pre-fix body loop only processed top-level .paragraph BodyChild, silently skipped .table and .contentControl(_, children:) — SEQ fields inside table cells/block-level SDTs never updated, returning 'no SEQ fields found' for thesis docs (caption paragraphs commonly live inside the table they describe); same gap #68 closed for findBodyChildContainingText; new walkAndProcessBodyChildForFields recursive walker mirrors #68 pattern; heading-count semantics: only top-level direct .paragraph body children count toward chapter-reset.

## [3.17.4] - 2026-04-30

### Changed
- paired #91 + #92 release

## [3.17.3] - 2026-04-29

### Added
- Result is exactly what insert_paragraph / insert_image_from_path / insert_caption etc. tools see when resolving after_text / before_text anchors. 10 new public-API surface tests in Issue86PublicAnchorLookupTests pin the canonical behavior across releases.

### Changed
- bump ooxml-swift dep 0.21.6 → 0.21.7 (pure transitive bump, no MCP source changes; exposes public anchor lookup API).
- Three WordDocument APIs upgraded private → public (PsychQuant/che-word-mcp#86): findBodyChildContainingText(_:nthInstance:) instance method + bodyChildContainsText(_:needle:) static + tableContainsText(_:needle:) static.
- External Swift SPM consumers (rescue scripts, dxedit CLI, third-party tooling) can now call canonical anchor-lookup logic directly instead of reimplementing with diverging semantics (some skipped .contentControl recursion, some skipped table cell traversal pre-#68, some used different nthInstance counting rules).
- Backward compatible: pure additive private → public visibility change; no API removals, no behavioral changes for existing callers

## [3.17.2] - 2026-04-29

### Added
- bump ooxml-swift dep 0.21.2 → 0.21.6 (pure transitive bump, no MCP source changes; 4 ooxml-swift releases worth of hardening + new APIs land transparently). v0.21.3 (XML hardening, PsychQuant/ooxml-swift#7): DTD reject + 64KB attr-value cap + SAX-based root-element attribute parsing + name whitelist on emit.
- New XMLHardeningError throws on malicious .docx input. v0.21.4 (roundtrip loud-fail, PsychQuant/ooxml-swift#6): AlternateContent.fallbackRunsModified dirty flag throws RoundtripError.unserializedFallbackEdit on stale fallbackRuns mutation.

### Changed
- Position field cascade Int = 0 → Int? = nil across 13 typed-child models. xml:space=preserve autosense in Run.toXMLThrowing emit.
- Plus 3 unreleased docs commits on ooxml-swift main (PsychQuant/ooxml-swift#14 #15 #17 + corrective cd841e7) covering needsPPr emit-gate ↔ Issue4 lock-in test bidirectional reference, parseRun vs parseParagraph walker pattern divergence rationale, foreign-namespace pPr asymmetry documentation.
- Tests: 236 passing (no regressions).

### Deprecated
- Run.commentIds @available deprecated; migrate to commentRangeMarkers. v0.21.5 (insertEquation flexibility, PsychQuant/che-word-mcp#84 #85): InsertLocation overload for Document.insertEquation + flattenedDisplayText OMML coverage extends anchor lookup beyond plain runs. v0.21.6 (mutation surface, PsychQuant/ooxml-swift#5): Hyperlink.text setter @available deprecated (lossy); migrate to .runs property.
- Backward compatible: deprecation warnings only; no API removals

## [3.17.1] - 2026-04-29

### Changed
- bump ooxml-swift dep to v0.21.2 — pulls in pPr regression-guard + test infrastructure hardening from upstream (ooxml-swift#4 walker whitelist + #if DEBUG assert / ooxml-swift#13 empty <w:pPr/> self-closing test gap / ooxml-swift#16 countPPrOpenTags regex hardening excluding <w:pPrChange>).
- No public MCP tool change

## [3.17.0] - 2026-04-28

### Added
- Tests: 5 new sub-tests in Issue62WrapCaptionSeqTests covering Scenarios 1-5.

### Changed
- wrap_caption_seq MCP tool (Refs #62): Phase 2 of cross-repo work — exposes ooxml-swift v0.21.0 lib API as MCP tool.
- Bulk-wraps plain-text caption number portions in SEQ field runs across body paragraphs whose flattened text matches a regex (EXACTLY ONE numeric capture group).
- Captured digit becomes SEQ field cachedResult so Word's first-open render preserves user-typed numbering before F9.
- Rescues docs pasted from external sources (LaTeX-converted Word, Google Docs, Pandoc) so insert_table_of_figures / insert_table_of_tables produce populated TOFs.
- Idempotent: paragraphs already wrapping a SEQ field for sequence_name reported in skipped, never double-wrapped (detection covers both FieldSimple AND rawXML fldChar emissions).
- Phase 1 ships scope:body only (recurses into table cells + nestedTables + block-level SDT children); scope:all returns Error: scope_not_implemented for now (cross-container path lands in v3.17.x).
- Bookmark wrap opt-in (insert_bookmark + bookmark_template with literal ${number}) so default 23-caption rescue does NOT pollute list_bookmarks.
- Returns JSON: {matched_paragraphs, fields_inserted, paragraphs_modified:[idx,...], skipped:[{paragraph_index, reason},...]}.
- All preconditions checked BEFORE document mutation (regex compile + capture-group count + format/scope enums + bookmark_template invariant + doc_id opened).
- Suite 231 → 236 (+5, 0 fail / 9 skip).
- No ooxml-swift dep bump (still v0.21.0 from v3.16.2)

## [3.16.2] - 2026-04-28

### Changed
- ooxml-swift dep bump 0.20.5 → 0.21.0 (Refs #62 #68): pure dep bump, no MCP source changes.
- MCP impact — insert_paragraph / insert_image_from_path / insert_equation / insert_caption calls using before_text / after_text now succeed when anchor text lives inside a table cell or block-level SDT (common in thesis docs with figure/table captions inside table cells).
- Returned position is top-level body.children index of the containing structure.
- Use into_table_cell for inside-cell inserts.
- Empty-needle guard: passing before_text:'' / after_text:'' now returns textNotFound instead of silently inserting at index 1. #62 (ooxml-swift v0.21.0): WordDocument.wrapCaptionSequenceFields(...) is now linked into the binary.
- Not yet exposed as an MCP tool — the wrap_caption_seq MCP wrapper ships in v3.17.0 (Phase 2 of the cross-repo work).
- Existing MCP tools unaffected.
- Suite: 231 → 231 (0 fail / 9 skip)

### Fixed
- Picks up two ooxml-swift fixes that surface transparently via existing tool dispatch. #68 (ooxml-swift v0.20.6): InsertLocation.findBodyChildContainingText now traverses .table (rows × cells × paragraphs + nestedTables) and .contentControl(_, children:) (recursive).

## [3.16.1] - 2026-04-28

### Added
- New static toolAnchorWhitelists dict (single source of truth, keyed by MCP tool name → accepted anchor list) + new detectPresentAnchors(_:tool:) overload. 4 conflict-detection call sites switched from literal anchor arrays to (tool:) lookup. 4 new invariant/parity tests.

### Changed
- anchorPresence whitelist drift prevention (Refs #80): pure refactor, no runtime behavior change.
- Suite 227 → 231 (+4).
- Old (args, anchors:) overload preserved.
- Out-of-scope follow-ups: schema descriptions + dispatcher if-else chains still hardcode anchor names (pre-existing surfaces, not introduced by this PR)

## [3.16.0] - 2026-04-28

### Added
- Specify exactly one.' New static helper detectPresentAnchors with per-anchor type-aware predicates (null and wrong-type values do NOT count). #72 (validation) explicit text_instance ≤ 0 rejected — 'Error: <tool>: text_instance must be ≥ 1, got <N>.' Omitted text_instance still defaults to 1. #70 (DX) all 32 'return Error:' lines in 4 #61-target tools rewritten as 'Error: <tool>: <body>' for AI-caller error attribution. throw WordError.* paths unchanged.

### Changed
- **BREAKING:** Bundle B anchor DX consistency (Refs #70 #71 #72): BREAKING (input validation only) — three coordinated MCP-layer changes across the 4 #61-target tools. #71 (behavior) silent priority on conflicting anchors → structured error: insert_paragraph(after_text + index) was previously silent-priority; now returns 'Error: insert_paragraph: received conflicting anchors: after_text + index.
- Scope deliberately limited to 4 tools; remaining 41 return Error lines elsewhere deferred to error-prefix-sweep follow-up.
- Tests: 201 → 227 (+26 sub-tests, 0 fail / 9 skip).
- No ooxml-swift dep bump (still v0.20.5)

### Removed
- SemVer rationale (minor not major): no schema break, no tool removal, restricting previously-undefined behavior.

## [3.15.3] - 2026-04-28

### Added
- Bundle A2 polish from v3.15.2 verify R3-R6 follow-ups (Refs #76 #77 #78 #79): #76 (docs) insert_caption description corrected from '三種 anchor' to enumerate all 5 (paragraph_index / after_image_id / after_table_index / after_text / before_text); insert_equation paragraph_index description clarified that the int is body.children-indexed (cross-references PsychQuant/ooxml-swift#10 for the lib-layer convention split). #77 (docs) insert_caption anchor set wording precision in CHANGELOG / manifest / marketplace.json / plugin.json — was 'its own anchor set including after_table_index' (implies disjoint), now 'shares after_image_id / after_text / before_text / paragraph_index, adds after_table_index + position, lacks into_table_cell' (explicit shared/adds/lacks). #78 (test) extends #69 append-index regression pin to bookmarkMarker / rawBlockElement / block-level contentControl body-children — the table case alone wouldn't catch a regression to getParagraphs().count - 1 that breaks for SDT / TOC bookmark / vendor extensions. #79 (test) adds round-trip depth: testInsertParagraphAppendIndexRoundTripsForInsertCalls demonstrates insert-family round-trip works (append + insert(N+1) + verify ordering); testInsertParagraphAppendIndexCannotRoundTripToUpdate pins the cross-family trade-off (update_paragraph(index=N) throws WordError.invalidIndex).

### Changed
- Tests: 196 → 201 (+5 sub-tests, 0 fail / 9 skip).
- No production code change.
- No ooxml-swift dep bump (still v0.20.5)

## [3.15.2] - 2026-04-28

### Changed
- Tests: 194 → 196 (0 fail / 9 skip).
- No behavior change in normal call paths.
- No ooxml-swift dep bump (still v0.20.5).

### Removed
- Word MCP Server - Swift 原生 OOXML 操作，233 個工具。v3.15.1 closes verify findings F1+F2+F3+F5 from v3.15.0 6-AI ensemble (5 Claude reviewers + Codex gpt-5.5 xhigh)：F1 (P1) `after_image_id` anchor 加到 insert_paragraph + insert_equation (display only) + insert_image_from_path — lib InsertLocation.afterImageId 從 #44 起就 ready 但只有 insert_caption 暴露 MCP-layer；v3.15.0 inherited 這個 gap，本 release 補齊。F2 (P1) `into_table_cell` 加到 insert_equation (display only) — display equation 是新建 paragraph，cell 放置 well-defined；inline mode 拒絕。F3 (P2) equation 成功訊息加 anchor info（'Inserted equation (display mode: true, after text X (instance N))' 等）— 關閉同 v3.14.4 LOOKUP 的 over-claim 模式（caller 之前無法區分 anchor 命中 vs append fallthrough）。F5 (P2) malformed `into_table_cell` partial dict（傳 `{table_index: 0}` 缺 row + col）silent fallthrough → 走 next anchor / append → 結果在錯位置且 caller 不知。改回 structured 'Error: into_table_cell requires all three fields'，3 #61-target tools 同步修（cross-cutting consistency）。Anchor priority unified across all 3 #61-target insert tools (`insert_paragraph` / `insert_equation` / `insert_image_from_path`; `insert_caption` has its own anchor set)：into_table_cell > after_image_id > after_text > before_text > index > append。Inline equation 拒絕擴大 — 現在拒絕所有 4 個 anchor params（before/after_text + after_image_id + into_table_cell），不只 v3.15.0 的 2 個。Tests: Issue61V315PointReleaseTests (9 sub-tests cross 3 tools)。Suite 185 → 194 (0 fail / 9 pre-existing skips)。**No ooxml-swift dep bump** — 仍 v0.20.5（lib 從 #44 起就 ready）。Follow-up issues 另開：F4 inline equation 更通用設計 (e.g. into_paragraph_with_text) / F6 text anchor 擴及 table-cell paragraphs 與 block-level SDT / F7 getParagraphs().count - 1 message 在 doc 含 tables/SDTs 時 mis-report (pre-existing) / F8 error message 加 tool-prefix / F9 multiple anchor params 同時傳入 silent priority winner / F10 text_instance≤0 normalize。Backward compatible — schema additions optional，既有 v3.15.0 callers 不變；只有 malformed into_table_cell 從 silent fallthrough 改成 structured error（會被 buggy caller 注意到）+ equation message 加 suffix（substring 'Inserted equation' 仍存在）。v3.15.0 closes #61 — insert_paragraph 與 insert_equation 現在接受跟 insert_image_from_path 一致的 anchor 參數（after_text / before_text / text_instance / into_table_cell — into_table_cell 僅 insert_paragraph）。Pre-fix MCP 層 silently drop 這些參數 — JSON schema 接受但 handler dispatch 忽略，呼叫 fall through 到 legacy paragraph_index path 或 append at end。Lib API Document.insertParagraph(_: at: InsertLocation) 從 #44 起就支援所有六種 anchor cases（paragraphIndex / afterImageId / afterTableIndex / intoTableCell / afterText / beforeText），本 release 補齊 MCP 側 wire-up gap，無需 ooxml-swift dep bump（v0.20.5 已足夠）。Anchor priority mirror insert_image_from_path：into_table_cell > after_text > before_text > index > append。Errors（textNotFound / tableIndexOutOfRange / tableCellOutOfRange）回 structured 訊息而非 silent fallthrough — AI caller 能 surface failure 而非拿到位置錯誤的 misleading 'success'。**Inline equation explicit rejection**：insert_equation 在 display_mode=false（inline）時 explicitly 拒絕 after_text / before_text，回 structured error — 語意模糊（'append OMML run into existing para containing this text' vs 'insert new para before/after target para'），inline placement 仍用 paragraph_index。Display-mode equation 建新 paragraph，anchor 語意明確。Tests: Issue61InsertParagraphAnchorsSmokeTests（5 sub-tests：after_text resolution / before_text resolution / text_instance disambiguation / into_table_cell append / textNotFound error）+ Issue61InsertEquationAnchorsSmokeTests（4 sub-tests：after_text + before_text in display mode / inline mode rejection / textNotFound error）。Suite 176 → 185 (0 fail / 9 pre-existing skips)。**No ooxml-swift dep bump** — v0.20.5 已有所有需要的 lib API。Backward compatible — anchor params 全 optional；既有 index / paragraph_index callers 不變；無 schema removal、無既有行為改動。**Real-world impact**：thesis-rescue / template-population workflow 不再需要 fall back 到「append at end + 手動 cut/paste in Word UI」或 binary-search 猜 paragraph_index，AI caller 對 3 #61-target insert tools（insert_image_from_path / insert_paragraph / insert_equation）對稱地用 surrounding context 定位 anchor。v3.14.5 closes Refs #63 verify F1 P1：擴充 findBodyChildContainingText 涵蓋所有 editable surfaces，補上 v3.14.4 CHANGELOG over-claim 的 insert anchor lookup gap。Pre-fix v3.14.4 只修了 REPLACE path（replace_text → Document.replaceInParagraphSurfaces 走 contentControls / hyperlinks / fieldSimples / alternateContents）但 LOOKUP path（findBodyChildContainingText 用於 InsertLocation.afterText / .beforeText 解析）只看 para.runs，所以 insert_image_from_path / insert_paragraph / insert_caption before_text/after_text 對 SDT-wrapped anchor 仍丟 textNotFound。Verify ensemble（5 Claude reviewers + Codex）的 requirements F1 P1 finding 抓到 CHANGELOG over-claim — 用戶選擇 Option B 擴充修而非縮 scope。ooxml-swift v0.20.5 新增 TextReplacementEngine.flatTextOfContentXML（read-only XML walker mirror replaceInContentXML flattening rules，跳過 <w:delText> / <w:instrText> / nested <w:sdt> subtrees）+ Paragraph.flattenedDisplayText 擴充 method 涵蓋 runs + hyperlinks + fieldSimples + alternateContents + contentControls（recursive into nested SDT children）。findBodyChildContainingText 改用 flattenedDisplayText 取代原本的 para.runs.map { $0.text }.joined()。新增 Issue63InsertAnchorInlineSDTTests（lib，3 wrappers × afterText/beforeText/insertImage = 3 sub-tests / 5 assertions）+ Issue63InsertAnchorInlineSDTSmokeTests（MCP，2 sub-tests pin lib-layer fix）。Suite 693 → 696 ooxml-swift / 174 → 176 che-word-mcp（0 fail）。基於 ooxml-swift v0.20.5。Backward compatible — strict superset of pre-fix lookup behavior（找到更多 anchors，既有 plain runs anchor 仍照常運作）。**Insert anchor lookup gap 此 release 完整補齊**，所有 inline wrappers 在 REPLACE + LOOKUP 兩個 path 都對稱覆蓋。v3.14.4 修 replace_text 對 inline `<w:sdt>` content control 的 wrapper coverage gap（Refs #63）：Document.replaceInParagraphSurfaces 之前覆蓋 paragraph.runs / hyperlinks / fieldSimples / alternateContents 但 **沒有** paragraph.contentControls — 包在 inline `<w:sdt>` 裡的文字 silently 0-match。外部 converter（pandoc / Quarto / LaTeX→docx）習慣把 cross-ref placeholder（[tab:foo] / [fig:bar] / [Smith 2020]）包成 inline SDT，所以症狀跟 bracketed text 高度相關，但其實 **brackets 是 coincidence** — bracket-free needle 在 inline SDT 裡也 fail。Issue title「literal `[ ]` brackets」是誤導，差別測試（fldChar / fldSimple / hyperlink / inlineSDT 四個 inline wrapper × 四種 needle）證實只有 inline SDT case 失敗，其他三個 wrapper 從 v0.19.0+ #56 Phase 5 起就 typed-runs 覆蓋好了。Surgical fix architecture：ooxml-swift v0.20.4 新增 TextReplacementEngine.replaceInContentXML（XML DOM walker，wrap ContentControl.content 在 synthetic root xmlns:w，遍歷所有 `<w:t>` descendants 在 document order，build flat string + offset map mirror flattenRuns invariant，run same literal/regex find logic，splice replacements 回 `<w:t>` element string content；re-serialize wrapper children 去掉 wrapper tag）+ Document.replaceInContentControl（recursive helper 涵蓋 cc.content + cc.children 處理 nested SDT）。Wired 進 Document.replaceInParagraphSurfaces 接在 alternateContents loop 之後。設計上跳過：`<w:delText>`（TC deletion text，不顯示）、`<w:instrText>`（field instruction code，不顯示）、nested `<w:sdt>` subtrees（typed cc.children 由外層 recursion 處理避免 double-replacement）。Round-trip discipline：只 mutate `<w:t>` element 的 string content；xml:space="preserve" 與其他 attribute 完整保留（attribute set 從不被 touch）。新增 Issue63InlineSDTReplaceTests（4 個 wrapper × 4 個 needle 的 differential test + nested SDT recursion + round-trip wrapper preservation = 3 sub-tests / 18 assertions）+ MCP-layer Issue63ReplaceTextInlineSDTSmokeTests（2 sub-tests pin lib-layer fix）。Suite 690 → 693 ooxml-swift / 172 → 174 che-word-mcp（0 fail）。基於 ooxml-swift v0.20.4。Backward compatible — surgical fix 只新增 code path，沒改任何既有行為（runs/hyperlinks/fieldSimples/alternateContents replacement path 不動，ContentControl model 維持 raw XML storage 不重構）。Out-of-scope（separate follow-up）：ContentControl 從 content:String 升級為 typed Run 列表（SDD-warranted refactor）；smartTags / bidiOverrides / customXmlBlocks / unrecognizedChildren 維持 raw-carrier passthrough。v3.14.3 sub-stack E of paragraph-level content-equality (closes #66)：Paragraph 新增 w14ParaId / w14TextId 欄位，提取並 round-trip <w:p> opening tag 上的 w14:* 屬性（Word 用於 collaborative editing 和 comment threading 的 revision-tracking GUIDs）。Plain attribute passthrough，String? typing — Word 的 GUIDs 是 8-char hex tokens（NOT RFC 4122 UUIDs），所以 opaque-string round-trip 是正確選擇。Pre-fix v3.14.2 silently dropped 兩個 attributes — 佔了 NTPU 論文 fixture w14:* token loss 的 ~95%（2214 / 2359 lost tokens 是這兩個 attrs）。Post-E 量測：w14: 保留率 10.55% → 93.98%；document.xml 流失 10.95% → 8.02%。Combined with sub-stack D (#65), total impact since v3.14.1：<w:lang> 50% → 98.89% (D)、w14:* 5% → 93.98% (E)、document.xml 流失 16.66% → 8.02% (D+E, -8.64 pp)。Matrix-pin testDocumentContentEqualityInvariant 同步抬升 floor（w14: 0.04→0.90、sizeLossRatio 上限 0.12→0.10）— matrix-pin 現在 LOAD-BEARING across **5 preservation classes**（rFonts/noProof/lang/kern/w14:）spanning run-level + paragraph-level + paragraph-mark scope。Defensive design (R2 review fixes)：openingPTag() routes attributes through escapeXMLAttribute；parseParagraph rejects schema-invalid empty-string GUIDs。基於 ooxml-swift v0.20.3。Backward compatible（兩個 fields 都 optional、default nil；openingPTag empty-attrs gate 防止 synthetic emit）。剩餘 8% 流失主要是其他 w14:* attribute classes（如 w14:* on <w:r>）— tracked as separate follow-up SDD。v3.14.2 sub-stack D of paragraph-level content-equality (closes #65)：ParagraphProperties 新增 markRunProperties 欄位，提取並 round-trip <w:rPr> direct child of <w:pPr> — paragraph-mark formatting per ECMA-376 §17.3.1.27 CT_PPrBase（控制 pilcrow ¶ 字符外觀的字型/顏色/語言/字距）。Reuses parseRunProperties verbatim — schema 跟 run-level CT_RPr 一致，所以 sub-stack C 的 typed extraction（rFonts 4-axis / noProof / kern / lang 3-axis）和 rawChildren passthrough（w14:* 效果）全部免費繼承。NTPU 論文 fixture 量測影響：<w:lang> 保留率 50% → 98.89%；<w:rFonts> 88% → 98.77%；<w:noProof> 92% → 100%；<w:kern> 84% → 99.93%；document.xml 大小流失 16.66% → 10.95%。Matrix-pin testDocumentContentEqualityInvariant 同步抬升 floor（lang 0.45→0.95、rFonts/noProof/kern 0.95、sizeLossRatio 上限 0.175→0.12）。Sub-stack E (#66 w14:paraId/textId) 接著 ship 到 v3.14.3，把流失壓到 < 5%，達成「edit 一個字 → document.xml shrinks <1%」strong demo。基於 ooxml-swift v0.20.2。Backward compatible（markRunProperties optional、default nil、writer empty-gate 防止 synthetic empty <w:rPr/>）。v3.14.1 sub-stack C-CONT closes triple-confirmed P0 (R2 + R5 + Codex 6-AI verify)：recognizedRprChildren Set 列了 ~16+ rPr child kinds 為 'recognized' 但 parseRunProperties 沒有 typed extraction → silent drop。受影響的常見元素：<w:spacing>（character spacing）、<w:caps>/<w:smallCaps>、<w:position>、<w:shd>（run shading）、<w:bdr>、<w:em>（CJK emphasis marks）、<w:effect>、<w:vanish>/<w:specVanish>/<w:webHidden>、<w:outline>/<w:shadow>/<w:emboss>/<w:imprint>、<w:bCs>/<w:iCs>/<w:dstrike>。Fix：trim Set 到 ONLY actually-typed-extracted-or-emitted kinds。Round-trip size loss: pre-fix v3.13.x 32% → v3.14.0 17.75% → v3.14.1 16.66%。Methodology lesson (6th)：P2 from one reviewer can become P0 when another applies real-world impact lens

### Fixed
- closes Bundle A polish from #61 R2 verify (Refs #69 #73 #74 #75): #69 (bug) insert_paragraph append message reports body.children index instead of getParagraphs().count - 1 (mis-reported in docs with tables/SDTs by skipping table children); #74 (bug) insert_image_from_path debug log labels after_image_id correctly (was silently labeled 'index' since v3.15.1); #73 (test) regression pin for equation F5 partial-dict guard (existed since v3.15.1 but was untested); #75 (docs) clarifies '3 insert tools' wording — scope is the 3 #61-target tools (insert_paragraph / insert_equation / insert_image_from_path); insert_caption is a 4th insert tool with a partially-overlapping anchor set (shares after_image_id / after_text / before_text / paragraph_index, adds after_table_index + position, lacks into_table_cell), intentionally outside this unification scope.

## [3.14.0] - 2026-04-27

### Fixed
- closes #60（sub-stack C of #58/#59/#60）— RunProperties field-loss audit。Bump ooxml-swift v0.19.13→v0.20.0。新增 typed fields：4-axis rFonts (ascii/hAnsi/eastAsia/cs/hint — 之前被收斂成單一值)、noProof、kern、3-axis lang (val/eastAsia/bidi)，加上 rawChildren passthrough 處理 unrecognized rPr children（如 w14:textOutline / w14:textFill / w14:glow）。**Pre-fix MCP 用戶看到 eastAsia/cs 字型（如 DFKai-SB 用於繁體中文）在 round-trip 時 silently 被替換成 ascii 值；v3.14.0 完整保留 4 個 axis**。Matrix-pin testDocumentContentEqualityInvariant 加上 preservation-class-3 ratio-floor assertions，現在 LOAD-BEARING — 任何未來 RunProperties regression 都會被 matrix-pin 抓到。Thesis fixture document.xml round-trip 大小：pre-fix 32% 損失 → post-sub-stack-C 17.75% 損失（改善 14.25 percentage points）。剩餘 17.75% 是 paragraph-mark rPr + w14:paraId/textId drops（separate out-of-scope follow-up SDD）。**'if not typed, preserve as raw' 原則架構性完成** — 從 sub-stack A (#58 BodyChild)、B (#59 WhitespaceOverlay) 一路發展到 C (#60 RunProperties)。Backward compatible — 保留 fontName field，mirror rFonts.ascii。v3.13.13 CRITICAL HOTFIX (sub-stack B-CONT-2-CONT) reverted v3.13.12 的 TIER-0 over-fix。v3.13.12 (DO NOT USE — 刪除 <w:del> 內容)。v3.13.11 sub-stack B-CONT。基於 ooxml-swift v0.20.0。
