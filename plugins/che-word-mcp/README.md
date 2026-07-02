# che-word-mcp

**Word MCP Server** — Swift 原生 OOXML 操作，**235 個工具**，支援 Dual-Mode 存取 + preserve-by-default round-trip fidelity + programmatic Track Changes 生成 + `document.xml` lossless round-trip。

當前版本：**v3.20.0**（Plugin shell + Binary 同步）— closes [PsychQuant/che-word-mcp#160](https://github.com/PsychQuant/che-word-mcp/issues/160) — 兩個新 MCP tools 暴露 [PsychQuant/ooxml-swift v0.24.0](https://github.com/PsychQuant/ooxml-swift/releases/tag/v0.24.0) 的 `spliceOMath` API 給 MCP callers，跨 document 拷貝 verbatim `<m:oMath>` XML 區塊。

- **`splice_omath_from_source`** — 單一 OMath splice，low-level。Source 用 `source_path`（Direct mode 唯讀）或 `source_doc_id`（Session mode）；target 必須是 session-mode `doc_id`。Position 支援 `atStart` / `atEnd` / `afterText` / `beforeText`（後兩者配合 `anchor` + 可選 `instance`）。`omath_index` 0-based、按 source-document order 跨 carrier 統一排序。`rpr_mode` 控制 source Run rPr 怎麼帶到 target Run（`full` 預設 verbatim / `omathOnly` 白名單 / `discard` 空 rPr）；`namespace_policy` 控制 prefix vs URI 處理（`lenient` 預設接受 `mml:` vs `m:` prefix mismatch / `strict` 任何 prefix 不同就 throw）。回傳 `Spliced 1 OMath block (...)` 或 structured error。
- **`splice_paragraph_omath_from_source`** — paragraph-level batch convenience。把 source paragraph 內所有 OMath 按 source-document order splice 到 target paragraph 對應位置（內部用 ~10 chars source-text-context 自動推 anchor）。回傳 splice 數量或 `contextAnchorNotFound(omath_index, snippet)`（partial-success state 已留在 target）。

**Use case**：unblocks [kiki830621/collaboration_guo_analysis](https://github.com/kiki830621/collaboration_guo_analysis/issues/17) Phase 7 inline-math restoration — 522 inline OMath blocks 從 `_raw.docx` 救回 `碩士論文-rescue-swift-v317.docx`。

**Tests**：8 個新 `Issue160SpliceOMathFromSourceTests` cases（Direct/Session source modes、atEnd/afterText positions、error taxonomy、batch mode、rPr discard）。Full suite: 297 passing, 0 failures, 9 pre-existing skips。Bumps `ooxml-swift` dep `0.21.0` → `0.24.0`。

---

當前版本：**v3.19.0**（Plugin shell + Binary 同步）— closes [PsychQuant/che-word-mcp#105](https://github.com/PsychQuant/che-word-mcp/issues/105) + [#106](https://github.com/PsychQuant/che-word-mcp/issues/106) + [#107](https://github.com/PsychQuant/che-word-mcp/issues/107)（`insert_equation` argument-contract hardening from #98 verify follow-up）。**#106 (P2)** — reject `components`+`latex` 同時呼叫，handler 在解析前回 structured error（之前 silent 用 components、丟 latex 而不警示）。**#107 (P2)** — reject 非 boolean `display_mode`（agent caller 傳 `"false"` string 等），之前 `args["display_mode"]?.boolValue` 回 nil → `?? true` fall-back，inline-intent 呼叫被路由成 display-mode。**#105 (P3)** — `paragraph_index` schema 拆 display-mode（`body.children` 索引）vs inline-mode（top-level paragraph ordinal）；新增 MCP-vs-lib `display_mode` 預設值差異說明（MCP 預設 `true` 對 agent 友好，lib 預設 `false`）；移除 unreachable `inlineModeRequiresParagraphIndex` defensive arm。6 NEW `Issue98InsertEquationLibBypassTests` 釘住 contract（2 runtime errors + 4 source-grep contract tests）。6-AI verify ensemble（5 Claude reviewers + Codex gpt-5.5 xhigh）：PASS with 0 blocking, 5 P2 follow-up, 6 P3 nits。6 follow-up issues opened：[#124](https://github.com/PsychQuant/che-word-mcp/issues/124) sibling fail-open（`paragraph_index` / `text_instance` / `into_table_cell.*` 同類 string-fail-open）/ [#125](https://github.com/PsychQuant/che-word-mcp/issues/125) JSON null vs absent semantics / [#126](https://github.com/PsychQuant/che-word-mcp/issues/126) runtime regression test for #105 with `[paragraph, table/SDT, paragraph]` fixture / [#127](https://github.com/PsychQuant/che-word-mcp/issues/127) `paragraphIndex!` force-unwrap → defensive guard / [#128](https://github.com/PsychQuant/che-word-mcp/issues/128) schema "anchor" phrasing 與 #71 anchor whitelist 對齊 / [#129](https://github.com/PsychQuant/che-word-mcp/issues/129) echo received value in arg-validation errors。Suite: 243 → 249 tests, 0 failures, 9 pre-existing skips。**Backward compatible** — only newly fail 在 caller 傳 `components`+`latex` 同時（之前 silent component-wins）或 string `display_mode`（之前 silent fail-open to true）—— 如果舊 caller 依賴這兩個 silent 行為，那個 call 本來就 buggy。

---

當前版本：**v3.17.8**（Plugin shell + Binary 同步）— closes [PsychQuant/che-word-mcp#98](https://github.com/PsychQuant/che-word-mcp/issues/98)，`insert_equation` MCP handler 跨 3 commits 重構（`91506f8` v1 / `357cbe7` v2 / `339ab77` v3）。Pre-fix 三個 structural defects：(1) **silent-clamp** on out-of-range `paragraph_index`（handler 用 non-throwing `insertParagraph(_:at: Int)` overload，tool 回 success 但插錯位置）；(2) lib `#84`/`#91` 的 `InsertLocation` overload + `InsertLocationError.inlineModeRequiresParagraphIndex` / `.invalidParagraphIndex(Int)` structured errors **從未到達 MCP callers**（handler 自建 OMML 完全 bypass lib）；(3) inline mode（`display_mode: false`）總是建立 NEW `Paragraph(runs: [eqRun])` 而**不是** append OMML run 到既有段落。v1 嘗試委派 lib 但 Codex 6-AI verify 抓到 P1 regression：lib 的 overload 內部用 `@available(*, deprecated, ...)` `MathEquation` flat output（`Field.swift:301`）— `\frac{a}{b}` 被截斷成 `(a)/(b` AND 嵌套 `<w:p><w:p>` invalid OOXML。v2 unified handler — 兩條 path（`latex` + `components`）都用 `MathComponent.toOMML()` 建結構化 OMML；display mode 走 lib 的 throwing `insertParagraph(_:at: InsertLocation)`；inline mode handler-side append OMML run 到既有段落。v3 補回 `eqPara.properties.alignment = .center`（lib display-mode convention，Codex sanity check P2）。**BREAKING for inline mode callers**：pre-fix 插新段落 → post-fix append 到既有段落（matches lib `#84`/`#91` design）；migration 見下方 v3.17.8 區塊。7 NEW `Issue98InsertEquationLibBypassTests` 釘住 contract（5 RED→GREEN scenarios + 2 quality regression tests 含 `unzip -p document.xml` 驗 `<m:f>` 結構 + centering 存活 + deprecated `(a)/(b)` 不出現）。6-AI verify ensemble（5 Claude reviewers + Codex gpt-5.5 xhigh）抓到 v1 兩個 P1 regression；Codex sanity check 抓到 v2 centering P2。6 P2/P3 follow-ups filed [#105](https://github.com/PsychQuant/che-word-mcp/issues/105) [#106](https://github.com/PsychQuant/che-word-mcp/issues/106) [#107](https://github.com/PsychQuant/che-word-mcp/issues/107) [#108](https://github.com/PsychQuant/che-word-mcp/issues/108) [#109](https://github.com/PsychQuant/che-word-mcp/issues/109) [#110](https://github.com/PsychQuant/che-word-mcp/issues/110)。Tests: 236 → 243 passing, 0 failures, 9 pre-existing skips。Backward compatible **except inline-mode BREAKING (documented)**。

**v3.17.8 BREAKING migration guide**

```
// Pre-fix（會插入 NEW paragraph at index 5）
insert_equation(doc_id, latex: "x", display_mode: false, paragraph_index: 5)

// Post-fix（append OMML run 到既有段落 5；matches lib #84/#91 design）
insert_equation(doc_id, latex: "x", display_mode: false, paragraph_index: 5)

// 若舊行為（要 NEW paragraph）：改用 display mode 或拆兩步
insert_equation(doc_id, latex: "x", display_mode: true, paragraph_index: 5)   // 新段落 + 公式
// 或
insert_paragraph(doc_id, paragraph_index: 5)
insert_equation(doc_id, latex: "x", display_mode: false, paragraph_index: 6)
```

Pre-fix 的 silent-clamp + 新段落行為是 **bug**，不是 backward-compat surface — v3.17.8 的 BREAKING 是修復結構錯誤。

---

當前版本：**v3.17.7**（Plugin shell + Binary 同步）— bump `ooxml-swift` dep 0.21.10 → 0.21.11，closes 5-issue cluster [#99](https://github.com/PsychQuant/che-word-mcp/issues/99) + [#100](https://github.com/PsychQuant/che-word-mcp/issues/100) + [#101](https://github.com/PsychQuant/che-word-mcp/issues/101) + [#102](https://github.com/PsychQuant/che-word-mcp/issues/102) + [#103](https://github.com/PsychQuant/che-word-mcp/issues/103). **Bilateral mirror coverage** for direct-child OMML at 4 wrapper positions（`<w:p>` direct child for Pandoc display math / `<w:hyperlink>` direct child / `<mc:Fallback>` direct child / nested wrapper combos）+ 2 NEW library-wide spec capabilities（`ooxml-paragraph-text-mirror` + `ooxml-library-design-principles`）。Pre-fix `Paragraph.flattenedDisplayText` AND `Document.replaceInParagraphSurfaces` 共享 symmetric blind spot：direct-child `<m:oMath>`/`<m:oMathPara>`（沒有 `<w:r>` wrapper）silently dropped → 對含 display math 的 paragraph anchor lookup silently 0-matched。讀側：`flattenedDisplayText` 走訪 4 wrapper positions 的 direct-child OMML，source XML position 排序。寫側：NEW 公開 API `WordDocument.replaceTextWithBoundaryDetection` 回 `ReplaceResult` enum（`.replaced(count:)` / `.refusedDueToOMMLBoundary(occurrences:)` / `.mixed(...)`），cross-OMML mutation 拒絕並回傳 informative `Occurrence(matchSpan:, ommlSpans:)`。Mirror invariant — **asymmetric by design**：reads include OMML visibleText（anchor lookup universe extends to math），writes treat OMML as opaque structural units（refuse cross-OMML mutation rather than silently delete equations）。Principle-driven（`ooxml-library-design-principles` spec）：**Correctness primacy** + **Human-like operations** as foundational normative invariants for all `ooxml-swift` mutators。Decision 4 raw passthrough preserved — round-trip fidelity unaffected。Tests: 236 passing che-word-mcp / 813→829 ooxml-swift (+16 in `Issue99FlattenReplaceOMMLBilateralTests`)。Backward compatible — strict superset of pre-fix behavior。

**v3.17.7 bump `ooxml-swift` dep v0.21.10 → v0.21.11** — Bilateral mirror coverage for direct-child OMML（5-issue cluster #99-#103, Spectra change `flatten-replace-omml-bilateral-coverage`）。Pure transitive, no MCP source changes:

- **Read side**: `flattenedDisplayText` walks direct-child OMML at all 4 wrapper positions
- **Write side**: NEW public API `WordDocument.replaceTextWithBoundaryDetection` returns informative `ReplaceResult` enum
- **Mirror invariant**: same surface coverage, asymmetric on OMML detected (reads include / writes refuse cross)
- **Library principles** (NEW spec capability): Correctness primacy + Human-like operations

---

當前版本：**v3.17.6**（Plugin shell + Binary 同步）— bump `ooxml-swift` dep 0.21.9 → 0.21.10，closes [PsychQuant/che-word-mcp#104](https://github.com/PsychQuant/che-word-mcp/issues/104). **Form-level** FieldParser canonical 5-run fldChar fix（orthogonal to v3.17.5 的 #94 **container-level** fix — 兩者解 independent walker dimensions）。Pre-fix `update_all_fields` 在 docs containing valid SEQ paragraphs at body top level when fldChar block emitted in canonical 5-run form（每個 `<w:fldChar>` / `<w:instrText>` / `<w:t>` 各在獨立 `<w:r>` sibling — DocxReader 後 / native Word emission）回 silent no-op (`"no SEQ fields found"`)。兩個 ooxml-swift commits land via dep bump：`537de62` FieldParser two-phase parse（Phase-1 baked + Phase-2 `parseFiveRunSpan` state machine probing both `Run.rawXML` and `Run.rawElements`）+ `58fe4f9` P1 sub-fix surfaced by 6-AI verify (Logic + Devil's Advocate runtime test): canonical-branch `Run.text` rewrite was silently overridden by `Run.toXML()` rawXML short-circuit; new `rewriteCanonicalCachedText` helper splices new value into embedded `<w:t>` while preserving `<w:rPr>` + `xml:space="preserve"`. **MCP impact**: `update_all_fields` now finds SEQ in canonical 5-run form (post-roundtrip / native Word emission); `list_captions` benefits transitively. Verified 6-AI ensemble (4 PASS / 2 WARN / 0 BLOCK)。5 P3 follow-ups filed in ooxml-swift（#29 SEQ Table coverage / #30 multi-paragraph counter / #31 multi-SEQ same paragraph / #32 DoS hardening / #33 discriminator invariant）。Tests: 236 passing che-word-mcp / 809→813 ooxml-swift (+4 sub-tests in `Issue104FieldParserCanonicalFormTests`)。Backward compatible — strict superset of pre-fix behavior。

**v3.17.6 bump `ooxml-swift` dep v0.21.9 → v0.21.10** — Form-level FieldParser fix closing [PsychQuant/che-word-mcp#104](https://github.com/PsychQuant/che-word-mcp/issues/104). Pure transitive, no MCP source changes:

- **Form-level vs container-level distinction**: 此 fix 是 form-level（baked vs canonical fldChar emission），orthogonal to v3.17.5 的 #94 container-level fix（`.table` / `.contentControl` recursion）。兩者解 independent walker dimensions：v3.17.5 補 container 走訪、v3.17.6 補 fldChar form 偵測。Production reproducer `rescue-swift-v317.docx` 內 19 個 SEQ paragraphs（12 SEQ Figure + 7 SEQ Table）DocxReader 後是 canonical 5-run 形式，pre-v3.17.6 的 FieldParser 只看 baked form（v2.0.0 全 5 個 fldChar 元素塞同一 `Run.rawXML`）→ silent skip 整批。
- **P1 sub-fix surfaced by 6-AI verify**: 第一輪 fix 只 mutate `Run.text`，但 `Run.toXML()` short-circuits on non-nil `rawXML`（`Run.swift:246-248`）— hand-built fixtures / native-Word-emit / 任何 upstream tool preserving raw form 都會 silent-broken。新 `rewriteCanonicalCachedText` helper 解決：splice 新值進 embedded `<w:t>` 同時保留 `<w:rPr>` 跟 `xml:space="preserve"`；`Run.text` 並行同步。
- **5 P3 follow-ups filed (out of scope)**: ooxml-swift [#29](https://github.com/PsychQuant/ooxml-swift/issues/29) (SEQ Table identifier coverage) / [#30](https://github.com/PsychQuant/ooxml-swift/issues/30) (multi-paragraph counter accumulation) / [#31](https://github.com/PsychQuant/ooxml-swift/issues/31) (multiple SEQ in same paragraph) / [#32](https://github.com/PsychQuant/ooxml-swift/issues/32) (DoS hardening) / [#33](https://github.com/PsychQuant/ooxml-swift/issues/33) (discriminator invariant pin)。

**Tests**: 236 passing che-word-mcp / 809 → 813 ooxml-swift（+4 sub-tests）。Backward compatible — strict superset of pre-fix behavior。

**Verification**: 6-AI ensemble (5 Claude reviewers + Codex gpt-5.5 xhigh) — 4 PASS / 2 WARN / 0 BLOCK; production reproducer (rescue-swift-v317.docx via DocxReader path) confirmed working.

---

**v3.17.5 bump `ooxml-swift` dep v0.21.8 → v0.21.9** — triple lib-only patch release covering [PsychQuant/che-word-mcp#87](https://github.com/PsychQuant/che-word-mcp/issues/87) + [#93](https://github.com/PsychQuant/che-word-mcp/issues/93) + [#94](https://github.com/PsychQuant/che-word-mcp/issues/94). Pure transitive, no MCP source changes:

- **#87 `Comment.paragraphIndex` flat-paragraph counter (observable behavior change)** — pre-fix used `body.children.enumerated()` index counting tables/SDTs/markers; post-fix walks flat-paragraph counter mirroring `getParagraphs()` semantics. MCP impact: `list_comments` `paragraph_index` field now consistently 0-indexed against `get_paragraphs()` flat list. **Caller migration**: callers manually compensating with `paragraph_index - 1` (or `- N`) to work around the bug must remove their compensation, will over-correct otherwise.
- **#93 `wrap_caption_seq` SEQ inherits source `position`** — pre-fix caption like 「圖 4-1：xxx」 rendered as 「圖 4-：xxx1」 on real Word docs because SEQ run had `position=nil` while source-loaded preText/postText had `position>0`. Paragraph emit bifurcates by position field — positioned section vs legacy post-content section — so SEQ landed at end. One-line fix `seqRun.position = preRun.position`. **Known incompleteness**: `insert_bookmark=true` × source-loaded paragraph still has same gap on bookmarkStart/End markers (filed [PsychQuant/ooxml-swift#24](https://github.com/PsychQuant/ooxml-swift/issues/24)); default `insert_bookmark=false` unaffected.
- **#94 `update_all_fields` traverses `.table` and `.contentControl` containers** — pre-fix body loop only processed top-level `.paragraph` BodyChild — silently skipped `.table` and `.contentControl(_, children:)`. SEQ fields anchored inside table cells or block-level SDTs were never updated. New `walkAndProcessBodyChildForFields` recursive walker mirrors #68 pattern. Heading-count semantics: only top-level direct `.paragraph` body children count toward chapter-reset (container-nested headings do NOT trigger SEQ resets — conservative thesis-aligned choice). **Known incompleteness** (filed): [ooxml-swift#25](https://github.com/PsychQuant/ooxml-swift/issues/25) header/footer/footnote/endnote SEQ scans still flat `.paragraphs` view; [ooxml-swift#26](https://github.com/PsychQuant/ooxml-swift/issues/26) `FieldParser.parse(paragraph:)` misses inline SDT/hyperlink/fieldSimple/AlternateContent surfaces; [ooxml-swift#27](https://github.com/PsychQuant/ooxml-swift/issues/27) verify-with-user-fixture for real thesis docx roundtrip; plus [ooxml-swift#28](https://github.com/PsychQuant/ooxml-swift/issues/28) refactor candidate (extract `BodyChildVisitor` protocol to dedupe 5+ body-children walkers).

**Tests**: 236 passing che-word-mcp / 805 → 809 ooxml-swift (no new MCP tests, no regressions). Backward compatible **except #87 documented behavior change**.

**Verification**: 6-AI ensemble (5 Claude reviewers: requirements / logic / security / regression / devils-advocate + Codex gpt-5.5 xhigh).

---

**v3.17.4 bump `ooxml-swift` dep v0.21.7 → v0.21.8** — paired patch release covering [PsychQuant/che-word-mcp#91](https://github.com/PsychQuant/che-word-mcp/issues/91) + [#92](https://github.com/PsychQuant/che-word-mcp/issues/92), both lib-only post-#85 verify follow-ups. Pure transitive, no MCP source changes:

- **#91 `insertEquation` inline-mode error semantics** — `InsertLocationError.inlineModeRequiresParagraphIndex` (anchor type other than `.paragraphIndex` with inline math) + `.invalidParagraphIndex(Int)` (negative or `≥ topLevelParagraphCount`). MCP impact: `insert_equation` `paragraph_index` out-of-bounds now returns structured error instead of silent fallthrough.
- **#92 `flattenedDisplayText` OMML wrapper coverage** — extracted `flattenRunsWithOMML(_:)` private static helper; applied uniformly to top-level runs + `hyperlinks[].runs` + `fieldSimples[].runs` + `alternateContents[].fallbackRuns`. `contentControls` path remains separate via `flattenContentControlText` (different recursion strategy, established in #63). MCP impact: anchor lookups (`replace_text` / `insert_paragraph` / `insert_image_from_path` / `insert_caption` `before_text` / `after_text`) against paragraphs containing inline math inside hyperlink / fldSimple / AC fallback wrappers now succeed where they previously silently 0-matched.

**Tests**: 236 passing (no new MCP tests, no regressions). Backward compatible (strict superset of pre-fix lookup behavior).

**Follow-ups filed (out of scope)**: 5 sibling bugs surfaced by devils-advocate verify of #92 — DA-1..DA-4 cover direct-child OMML in `<w:p>` / `<w:hyperlink>` / `<mc:Fallback>` + nested wrapper; DA-5 docstring qualifier. Filed as [#99](https://github.com/PsychQuant/che-word-mcp/issues/99)–[#103](https://github.com/PsychQuant/che-word-mcp/issues/103). NOT regressions introduced by v3.17.4.

---

**v3.17.3 bump `ooxml-swift` dep v0.21.6 → v0.21.7** — patch release exposing public anchor lookup API ([che-word-mcp#86](https://github.com/PsychQuant/che-word-mcp/issues/86)). Pure transitive, no MCP source changes:

- **`WordDocument.findBodyChildContainingText(_:nthInstance:)`** — instance method, was `private`. Walks `body.children` returning the top-level index of the BodyChild whose flattened text contains the needle. `nthInstance` disambiguates among repeats. Traverses `.contentControl(_, children:)` recursively + `.table` cells / `nestedTables` (since #68); skips `bookmarkMarker` / `rawBlockElement`.
- **`WordDocument.bodyChildContainsText(_:needle:)`** — static primitive, was `private static`. Single-child predicate; useful for custom traversal.
- **`WordDocument.tableContainsText(_:needle:)`** — static primitive, was `private static`. Walks all cells + nested tables.

External consumers previously had to reimplement this with diverging semantics — some skipped `.contentControl` recursion, some skipped table cell traversal (pre-#68 default), some used different `nthInstance` counting rules (top-level body child vs flattened paragraph). Now they get *exactly* the canonical behavior `insert_paragraph` etc. tools see.

**Tests**: 236 passing (no regressions). 10 new public-API surface tests in `Issue86PublicAnchorLookupTests` pin the canonical behavior across releases (top-level paragraph match / `nthInstance` disambiguation / invalid input contracts / SDT recursion / table cell traversal / bookmark + raw skip / `bodyChildContainsText` predicate / `tableContainsText` nested-table walk / round-trip parity with `insertParagraph(at: .afterText)`).

**Backward compatibility**: Pure additive (private → public visibility change). No API removals, no behavioral changes for existing callers.

---

**v3.17.2 bump `ooxml-swift` dep v0.21.2 → v0.21.6** — patch release pulling in 4 ooxml-swift releases worth of hardening + new APIs (no MCP source changes, no MCP tool surface change). New typed errors fire only on edge cases (malicious input, dirty fallback edits); deprecation warnings only when callers actively use lossy/legacy APIs. Pure transitive bump:

- **[ooxml-swift#7](https://github.com/PsychQuant/ooxml-swift/issues/7) v0.21.3 XML hardening** — DTD reject + 64KB attribute-value cap + SAX-based root-element attribute parsing + name whitelist on emit. New `XMLHardeningError.{dtdNotAllowed, attributeValueTooLarge, invalidAttributeName}` throws on malicious .docx input.
- **[ooxml-swift#6](https://github.com/PsychQuant/ooxml-swift/issues/6) v0.21.4 roundtrip loud-fail** — `AlternateContent.fallbackRunsModified` dirty flag throws `RoundtripError.unserializedFallbackEdit` when in-memory mutation isn't propagated back to rawXML. `Run.commentIds` `@available(*, deprecated)`; migrate to `commentRangeMarkers`.
- **[che-word-mcp#84 #85](https://github.com/PsychQuant/che-word-mcp/issues/84) v0.21.5 insertEquation flexibility** — new `Document.insertEquation(at: InsertLocation, ...)` overload + `flattenedDisplayText` extension covers OMML so anchor-text resolution traverses display-mode equations.
- **[ooxml-swift#5](https://github.com/PsychQuant/ooxml-swift/issues/5) v0.21.6 mutation surface fix** — `Hyperlink.text` setter `@available(*, deprecated)` (lossy: discards `RunProperties` + `rawElements`); migrate to `.runs` property. Position field cascade `Int = 0` → `Int? = nil` across 13 typed-child models with tri-state semantics. `xml:space="preserve"` autosense in `Run.toXMLThrowing` emit.
- **Plus 3 unreleased docs commits on ooxml-swift main** — [#17](https://github.com/PsychQuant/ooxml-swift/issues/17) bidirectional `needsPPr` ↔ `Issue4PPrRegressionGuardTests` reference; [#15](https://github.com/PsychQuant/ooxml-swift/issues/15) `parseRun` vs `parseParagraph` walker pattern divergence rationale; [#14](https://github.com/PsychQuant/ooxml-swift/issues/14) foreign-namespace pPr asymmetry documentation.

**Tests**: 236 passing (no regressions). Suite breakdown: 0 failures, 9 pre-existing skips. **Backward compatibility**: Deprecation warnings only when callers use `Hyperlink.text` setter / `commentIds`; new typed errors only on edge cases (malicious input, dirty fallback edits) — code that previously silently lost data now throws fail-fast. No API removals (all v0.21.x deprecations queued for v0.22).

**Verification**: 6-AI ensemble verified each ooxml-swift release upstream (5 Claude reviewers + Codex CLI gpt-5.5 xhigh). Three SDD bundles archived: `mutation-surface-fix`, `roundtrip-loud-fail`, `harden-xml-security`.

---

**v3.17.1 bump `ooxml-swift` dep v0.21.0 → v0.21.2** — patch release pulling in upstream test/regression-guard hardening from the post-#56 follow-up bundle. **No public MCP tool change**, no behaviour change for valid input。Pure transitive hardening at the parser invariant layer：

- **[ooxml-swift#4](https://github.com/PsychQuant/ooxml-swift/issues/4)** — `pPr` regression guard. 3-layer defense-in-depth on the v0.19.1 hot-fix invariant：`walkerPreConsumed: Set<String> = ["pPr"]` 在 `parseParagraph` walker loop entry filter；既有 `case "pPr": break` 保留為 belt-and-suspenders；`#if DEBUG assert(name != "pPr", ...)` 在 catch-all default `unrecognizedChildren.append` site 作 dev-time canary。5 regression tests in `Issue4PPrRegressionGuardTests`。
- **[ooxml-swift#13](https://github.com/PsychQuant/ooxml-swift/issues/13)** — empty `<w:pPr/>` self-closing test gap closed。TDD discovered emitter drops empty pPr blocks（`needsPPr` gate at `Paragraph.swift:335,466`）；test name + assertion direction 反映 empirical OOXML-spec behaviour。
- **[ooxml-swift#16](https://github.com/PsychQuant/ooxml-swift/issues/16)** — `countPPrOpenTags` helper regex hardening。Substring `<w:pPr` 替換為 `NSRegularExpression #"<w:pPr[\s/>]"#"` — 排除 `<w:pPrChange>`（Track Changes paragraph-property revision element），先前會虛增計數造成 brittle 假失敗。

ooxml-swift suite 720 → 722（0 fail）。che-word-mcp suite 不變（pure transitive dep bump）。

**Verification**：6-reviewer cross-verification on #4（5 Claude teammates + Codex CLI gpt-5.5 xhigh, all PASS unanimous）；5-reviewer on #13/#16 batch（Codex hung, skipped）。

---

**Pre-v3.17.x architectural milestones**（detail in [CHANGELOG](https://github.com/PsychQuant/che-word-mcp/blob/main/CHANGELOG.md)）：sub-stacks A–E 完整覆蓋 paragraph + run scope（`if not typed, preserve as raw` principle）。Combined preservation gains since v3.14.0：`<w:lang>` 50% → 98.89%；`w14:` 5% → 93.98%；`document.xml` size loss 16.66% → 8.02%。Matrix-pin `testDocumentContentEqualityInvariant` 現在 LOAD-BEARING across 5 preservation classes（rFonts / noProof / lang / kern / w14:）spanning run + paragraph + paragraph-mark scope — 任何一類 regression 都會 trip。

---

Office.js OOXML Roadmap **P0 100% 完成**（Umbrella issue [#43](https://github.com/PsychQuant/che-word-mcp/issues/43)）。Latest milestones：v3.17.4 — bump ooxml-swift dep to v0.21.8（paired #91 insertEquation inline-mode error semantics + #92 flattenedDisplayText OMML wrapper coverage, both lib-only post-#85 verify follow-ups）；v3.17.3 — bump ooxml-swift dep to v0.21.7（exposes public anchor lookup API for external Swift SPM consumers, [che-word-mcp#86](https://github.com/PsychQuant/che-word-mcp/issues/86)）；v3.17.2 — bump ooxml-swift dep to v0.21.6（4-version transitive bump pulling in XML hardening + roundtrip loud-fail + insertEquation InsertLocation overload + mutation surface fix from ooxml-swift#5/#6/#7）；v3.17.1 — bump ooxml-swift dep to v0.21.2（pPr regression-guard hardening from ooxml-swift#4/#13/#16）；v3.17.0 — `wrap_caption_seq` MCP tool（[#62](https://github.com/PsychQuant/che-word-mcp/issues/62)，rescues docs pasted from external sources so `insert_table_of_figures` / `insert_table_of_tables` produce populated TOFs）；v3.16.0 — Bundle B anchor DX consistency（[#70](https://github.com/PsychQuant/che-word-mcp/issues/70) [#71](https://github.com/PsychQuant/che-word-mcp/issues/71) [#72](https://github.com/PsychQuant/che-word-mcp/issues/72)，BREAKING input-validation：conflicting anchors + `text_instance ≤ 0` 改 structured error）。**Architectural extension of 'if not typed, preserve as raw' principle** — 從 sub-stack A (#58 BodyChild) → B (#59 WhitespaceOverlay) → C (#60 RunProperties) → D (#65 ParagraphProperties.markRunProperties) → **E (#66 paragraph w14:* attrs)** 完整覆蓋 paragraph + run scope。

**前次 milestones**：

- **v3.17.4** — bump `ooxml-swift` dep v0.21.7 → v0.21.8（paired #91 + #92 release）。#91 adds `InsertLocationError.inlineModeRequiresParagraphIndex` + `.invalidParagraphIndex(Int)` for `insert_equation` inline-mode anchor type / out-of-bounds `paragraph_index` (was silent fallthrough). #92 extends `flattenedDisplayText` OMML walk via shared `flattenRunsWithOMML(_:)` helper across hyperlink / fldSimple / AC.fallbackRuns wrappers (top-level runs + 3 wrapper paths now uniformly covered; contentControls path remains separate via `flattenContentControlText` per #63). MCP impact: `insert_equation` returns structured errors instead of silent no-op; anchor lookups against wrapper-nested OMML paragraphs now succeed where they previously silently 0-matched. Strict superset of pre-fix lookup behavior. Tests 236 passing. 5 follow-up issues #99-#103 filed for sibling bugs (DA-1..DA-5: direct-child OMML in `<w:p>` / `<w:hyperlink>` / `<mc:Fallback>` + nested wrapper + docstring qualifier).
- **v3.17.3** — bump `ooxml-swift` dep v0.21.6 → v0.21.7（exposes public anchor lookup API: `WordDocument.findBodyChildContainingText` instance method + `bodyChildContainsText` / `tableContainsText` static primitives, all `private → public`）。Pure transitive, no MCP source changes. External Swift SPM consumers can now call canonical anchor-lookup logic directly instead of reimplementing with diverging semantics. 10 new public-API surface tests. Backward compatible (additive visibility change).
- **v3.17.2** — bump `ooxml-swift` dep v0.21.2 → v0.21.6 (4-version transitive bump: v0.21.3 XML hardening + v0.21.4 roundtrip loud-fail + v0.21.5 insertEquation InsertLocation overload + v0.21.6 mutation surface fix + 3 unreleased docs commits on ooxml-swift main)。No MCP tool surface change. Deprecation warnings for `Hyperlink.text` setter / `commentIds` (queued for v0.22 removal). Tests 236 passing.
- **v3.17.1** — bump `ooxml-swift` dep v0.21.0 → v0.21.2 (pPr regression-guard + test infra hardening from upstream #4/#13/#16)。No public MCP tool change。
- **v3.17.0** — `wrap_caption_seq` MCP tool（Refs [#62](https://github.com/PsychQuant/che-word-mcp/issues/62)，Phase 2）：bulk-wraps plain-text caption number portions in SEQ field runs across body paragraphs whose flattened text matches a regex (EXACTLY ONE numeric capture group)。Captured digit becomes SEQ field cachedResult so Word's first-open render preserves user-typed numbering。Idempotent + scope:body-only + bookmark wrap opt-in。Suite 231 → 236 (+5)。Tools 234 → 235。
- **v3.16.2** — pure dep bump `ooxml-swift` v0.20.5 → v0.21.0 (Refs [#62](https://github.com/PsychQuant/che-word-mcp/issues/62) [#68](https://github.com/PsychQuant/che-word-mcp/issues/68))：picks up `InsertLocation.findBodyChildContainingText` recursing into table cells + block-level SDT (#68) + `WordDocument.wrapCaptionSequenceFields` lib API ready for v3.17.0 MCP wrapper (#62)。
- **v3.16.1** — anchor-presence whitelist drift prevention（Refs [#80](https://github.com/PsychQuant/che-word-mcp/issues/80)）：pure refactor，static `toolAnchorWhitelists` dict 替換 4 個分散的 literal anchor arrays。4 invariant tests（4 → 8）防將來新增 anchor 漏接 conflict-detection。No runtime behavior change。
- **v3.16.0** — Bundle B anchor DX consistency（Refs [#70](https://github.com/PsychQuant/che-word-mcp/issues/70) [#71](https://github.com/PsychQuant/che-word-mcp/issues/71) [#72](https://github.com/PsychQuant/che-word-mcp/issues/72)，**BREAKING input validation only**）：(a) conflicting anchors（如 `after_text` + `index`）silent-priority 改成 structured error；(b) explicit `text_instance ≤ 0` 拒絕；(c) 4 個 #61-target tools 統一錯誤格式 `Error: <tool>: <body>` 給 AI-caller 錯誤歸因。Suite 201 → 227 (+26)。
- **v3.15.3** — Bundle A2 polish（Refs [#76](https://github.com/PsychQuant/che-word-mcp/issues/76) [#77](https://github.com/PsychQuant/che-word-mcp/issues/77) [#78](https://github.com/PsychQuant/che-word-mcp/issues/78) [#79](https://github.com/PsychQuant/che-word-mcp/issues/79))：schema description doc rot 修正 + bookmarkMarker / SDT / TOC bookmark / contentControl 的 append-index regression pin。Suite 196 → 201。
- **v3.15.2** — Bundle A polish（Refs [#69](https://github.com/PsychQuant/che-word-mcp/issues/69) [#73](https://github.com/PsychQuant/che-word-mcp/issues/73) [#74](https://github.com/PsychQuant/che-word-mcp/issues/74) [#75](https://github.com/PsychQuant/che-word-mcp/issues/75))：`insert_paragraph` append message 改回 body.children index（pre-fix `getParagraphs().count - 1` 在含 tables/SDTs 文件 mis-report）+ debug log label fixes + equation F5 partial-dict regression pin。Suite 194 → 196。
- **v3.15.1** — Verify findings F1+F2+F3+F5 closed（Refs [#61](https://github.com/PsychQuant/che-word-mcp/issues/61))：`after_image_id` 加到 insert_paragraph + insert_equation (display only) + insert_image_from_path；`into_table_cell` 加到 insert_equation (display only)；equation 成功訊息加 anchor info；malformed `into_table_cell` partial dict 改 structured error。Suite 185 → 194。
- **v3.15.0** — `insert_paragraph` / `insert_equation` accept anchor parameters（Refs [#61](https://github.com/PsychQuant/che-word-mcp/issues/61)）：closes MCP-side wire-up gap，handler dispatch 之前 silently 丟棄 `after_text` / `before_text` / `text_instance` / `into_table_cell`。Anchor priority `into_table_cell > after_text > before_text > index > append`。Inline equation explicitly 拒絕 anchor。Suite 176 → 185。
- **v3.14.5** — `findBodyChildContainingText` 涵蓋所有 editable surfaces（Refs [#63](https://github.com/PsychQuant/che-word-mcp/issues/63) verify F1)：bumps `ooxml-swift` v0.20.4 → v0.20.5。Closes v3.14.4 CHANGELOG over-claim — REPLACE path 已修但 LOOKUP path（`InsertLocation.afterText`）仍只看 `para.runs`。`Paragraph.flattenedDisplayText` 擴充為涵蓋 runs + hyperlinks + fieldSimples + alternateContents + contentControls (recursive into nested SDT)。Suite 174 → 176。
- **v3.14.4** — `replace_text` on inline `<w:sdt>` content controls fix（Refs [#63](https://github.com/PsychQuant/che-word-mcp/issues/63))：`Document.replaceInParagraphSurfaces` 之前覆蓋 runs / hyperlinks / fieldSimples / alternateContents 但 **沒有** contentControls — 包在 inline `<w:sdt>` 裡的文字 silently 0-match。常見於 pandoc / Quarto / LaTeX→docx cross-ref placeholder。bumps `ooxml-swift` v0.20.3 → v0.20.4。Suite 172 → 174。
- **v3.14.3** sub-stack E (#66) — paragraph `w14:paraId` / `w14:textId` round-trip；`w14:` retention 5% → 93.98%；document.xml size loss 16.66% → 8.02%。
- **v3.14.2** sub-stack D (#65) — `ParagraphProperties.markRunProperties` round-trips `<w:rPr>` direct child of `<w:pPr>`（pilcrow ¶ 字符外觀 per ECMA-376 §17.3.1.27）。`<w:lang>` retention 50% → 98.89%。
- **v3.14.1** sub-stack C-CONT — closes triple-confirmed P0 (R2 + R5 + Codex 6-AI verify)：trim `recognizedRprChildren` Set 到 actually-extracted kinds（修了 `<w:spacing>` / `<w:caps>` / `<w:position>` / `<w:shd>` / `<w:em>` 等的 silent drop）。Round-trip size loss 17.75% → 16.66%。
- **v3.14.0** sub-stack C of [#60](https://github.com/PsychQuant/che-word-mcp/issues/60) — `RunProperties` 新增 4-axis rFonts / noProof / kern / 3-axis lang typed fields + rawChildren passthrough（w14:textOutline / textFill / glow 等）。Pre-fix `eastAsia="DFKai-SB"`（繁體中文）會 silently 被 `ascii` 值替換掉；v3.14.0 完整保留 4 個 axis。
- **v3.13.13** CRITICAL HOTFIX (sub-stack B-CONT-2-CONT)；v3.13.12 (DO NOT USE — 刪除 `<w:del>` 內容)；v3.13.11 sub-stack B-CONT；v3.13.10 sub-stack B 初版 (#59 WhitespaceOverlay)；v3.13.9 A-CONT-3 silent correctness regression；v3.13.6-v3.13.8 sub-stack A cycles (#58 BodyChild)；v3.13.5 R5 stack-completion — 詳見 [CHANGELOG](https://github.com/PsychQuant/che-word-mcp/blob/main/CHANGELOG.md)。

## 兩種操作模式

### Direct Mode（`source_path`）— 唯讀，免開啟

傳入檔案路徑直接使用，不需要先 `open_document`。適合快速檢視。

```
list_images:    { "source_path": "/path/to/file.docx" }
search_text:    { "source_path": "/path/to/file.docx", "query": "keyword" }
get_paragraphs: { "source_path": "/path/to/file.docx" }
```

### Session Mode（`doc_id`）— 完整讀寫生命週期

先 `open_document` 取得 `doc_id`，再進行編輯操作。

```
open_document:    { "path": "/path/to/file.docx", "doc_id": "mydoc" }
insert_paragraph: { "doc_id": "mydoc", "text": "Hello World" }
save_document:    { "doc_id": "mydoc", "path": "/path/to/output.docx" }
close_document:   { "doc_id": "mydoc" }
```

v3.0.0+ session state 追蹤：dirty tracking、autosave、`finalize_document`、disk drift 偵測。

## Round-trip Fidelity（v3.5.0 true byte-preservation）

底層 `ooxml-swift v0.19.2` 採用 **preserve-by-default + dirty tracking** 架構：`open_document` 保留原始 archive tempDir；`save_document` overlay 模式透過 `WordDocument.modifiedParts: Set<String>` 精確判斷哪些 part 真正被改動，**未改動的 typed-managed part 完全不重寫**——byte-for-byte 保留 `word/theme/`、`webSettings.xml`、`people.xml`、`commentsExtended/Extensible/Ids`、`glossary/`、`customXml/`、**以及 `word/document.xml`、`styles.xml`、`fontTable.xml`、`header*.xml`、`footer*.xml`、`comments.xml`、`footnotes.xml`、`endnotes.xml`** 等所有 typed parts。v0.19.x 額外解決 #56 P0：`<w:document>` root 34 個 `xmlns:*` declarations 完整保留，`<w:bookmarkStart>` / `<w:hyperlink>` / `<w:fldSimple>` / `<mc:AlternateContent>` 結構化 wrapper 全程 round-trip（pre-v0.19.0 會 silently 丟掉 wrapper 內 354 個 `<w:t>` text nodes）。

NTPU 學位論文模板的中文字體（DFKai-SB / 華康中楷體）no-op `save_document` 後完整保留 13 fontTable + 6 distinct headers + 4 footers + three-segment PAGE field + `<w15:presenceInfo>` identity。

## Track Changes 寫側合約（v3.12.0+）

兩條路徑：**accept/reject 既有修訂** OR **程式化生成新修訂**。

### 程式化生成（v3.12.0 新增）

```
1. enable_track_changes(doc_id, author: "Reviewer A")
2. insert_text_as_revision(doc_id, paragraph_index, position, text)
   delete_text_as_revision(doc_id, paragraph_index, start, end)
   move_text_as_revision(doc_id, source/dest)
   format_text(doc_id, paragraph_index, bold: true, as_revision: true)
   set_paragraph_format(doc_id, paragraph_index, alignment: "center", as_revision: true)
3. save_document(...)
```

**Author resolution 三層 fallback**：explicit `author` arg → `revisions.settings.author`（在 `enable_track_changes` 時設定）→ `"Unknown"`。

**Side-effect 合約**（重要）：`as_revision: true` 要求 track changes 已開啟。Disabled 時呼叫**會拋 `track_changes_not_enabled`**，不會偷偷 auto-enable。設計理由：避免 hidden state mutation。

### Accept / Reject 既有修訂

```
get_revisions / accept_revision / reject_revision / accept_all_revisions / reject_all_revisions
```

## Direct Mode 支援的工具

| 類別 | 工具 |
|------|------|
| 讀取內容 | `get_text`, `get_document_text`, `get_paragraphs`, `get_document_info`, `search_text` |
| 列出元素 | `list_images`, `list_styles`, `get_tables`, `list_comments`, `list_hyperlinks`, `list_bookmarks`, `list_footnotes`, `list_endnotes`, `get_revisions`, `list_content_controls` |
| 屬性 | `get_document_properties`, `get_section_properties`, `get_word_count_by_section` |
| 匯出 | `export_markdown` |

## 工具總覽

### 文件管理 + Session 生命週期（v3.0.0+）

- `create_document`, `open_document`, `save_document`, `close_document`, `finalize_document`
- `list_open_documents`, `get_document_info` ⚡, `get_document_session_state`, `get_session_state`
- `check_disk_drift`, `revert_to_disk`, `reload_from_disk`, `recover_from_autosave`, `checkpoint`

### 內容操作

- `get_text` ⚡, `get_document_text` ⚡, `get_paragraphs` ⚡, `search_text` ⚡, `search_text_batch`
- `insert_paragraph`, `update_paragraph`, `delete_paragraph`
- `replace_text`, `replace_text_batch`, `insert_text`

### 格式設定

- `format_text`（**v3.12.0+ `as_revision: bool`**）, `set_paragraph_format`（**v3.12.0+ `as_revision: bool`**）, `apply_style`
- `set_paragraph_border`, `set_paragraph_shading`, `set_character_spacing`, `set_text_effect`
- `get_paragraph_runs`, `get_text_with_formatting`, `search_by_formatting`, `search_text_with_formatting`, `list_all_formatted_text`

### 樣式管理（v3.10.0+ 強化，#48）

- `list_styles` ⚡, `apply_style`, `create_style`, `update_style`, `delete_style`
- v3.10.0 新增：`get_style_inheritance_chain`（含 cycle detection）, `link_styles`（`<w:link>` 段落+字元 pair）, `set_latent_styles`, `add_style_name_alias`（BCP 47 多語）
- `create_style` / `update_style` 新增 6 個 args：`based_on`, `linked_style_id`, `next_style_id`, `q_format`, `hidden`, `semi_hidden`

### Numbering / 編號清單（v3.10.0+ 完整補完，#46）

- 入門：`insert_bullet_list`, `insert_numbered_list`, `set_list_level`, `set_outline_level`
- 定義管理（v3.10.0 新增 8 個）：`list_numbering_definitions`, `get_numbering_definition`, `create_numbering_definition`（max 9 levels）, `override_numbering_level`, `assign_numbering_to_paragraph`, `continue_list`, `start_new_list`, `gc_orphan_numbering`

### 區段 / 頁面設定（v3.10.0+ 強化，#47）

- 基礎：`set_page_size`, `set_page_margins`, `set_page_orientation`, `set_page_borders`, `set_columns`, `set_line_numbers`, `set_text_direction`
- 區段斷點：`insert_page_break`, `insert_section_break`, `insert_continuous_section_break`, `insert_column_break`
- v3.10.0 新增 7 個：`set_line_numbers_for_section`（legal docs `<w:lnNumType>`）, `set_section_vertical_alignment`（封面置中）, `set_page_number_format`（羅馬數字等）, `set_section_break_type`, `set_title_page_distinct`, `set_section_header_footer_references`, `get_all_sections`

### 表格（v3.11.0+ 強化，#49）

- 基礎：`insert_table`, `get_tables` ⚡, `update_cell`, `delete_table`
- 結構：`merge_cells`, `set_table_style`, `set_table_alignment`
- 行列：`add_row_to_table`, `add_column_to_table`, `delete_row_from_table`, `delete_column_from_table`
- 尺寸：`set_cell_width`, `set_row_height`, `set_cell_vertical_alignment`, `set_header_row`
- v3.11.0 新增 5 個：`set_table_conditional_style`（10 種 region：firstRow / lastRow / bandedRows…），`insert_nested_table`（最深 5 層，超過拋 `nested_too_deep`），`set_table_layout`（fixed/autofit），`set_table_indent`（`<w:tblInd>`）

### 超連結（v3.11.0+ 三種 typed，#50）

- 基礎：`insert_hyperlink`, `update_hyperlink`, `delete_hyperlink`, `list_hyperlinks` ⚡
- 內部連結：`insert_internal_link`, `insert_cross_reference`
- v3.11.0 新增 3 個 typed：`insert_url_hyperlink`（外部 URL + tooltip + history flag），`insert_bookmark_hyperlink`（`w:anchor`，無 rId），`insert_email_hyperlink`（`mailto:` + URL-encoded subject）— 三者自動建 Hyperlink character style

### 頁首頁尾 + 浮水印（v3.3.0+ → v3.11.0+ 強化，#51）

- 寫入：`add_header`, `update_header`, `add_footer`, `update_footer`, `insert_page_number`
- 列舉與讀取：`list_headers`, `get_header`, `list_footers`, `get_footer`
- 刪除：`delete_header`, `delete_footer`
- v3.11.0 新增 4 個：`enable_even_odd_headers`（`<w:evenAndOddHeaders/>`），`link_section_header_to_previous` / `unlink_section_header_from_previous`（Word-compat clone），`get_section_header_map`
- 浮水印：`insert_watermark`, `insert_image_watermark`, `remove_watermark`, `list_watermarks`, `get_watermark`

### Content Controls / SDT（v3.9.0+ 完整 read/write，#44）

- 寫入：`insert_content_control`（12 type discrimination：richText / plainText / picture / date / dropDownList / comboBox / checkBox / bibliography / citation / group / repeatingSection / repeatingSectionItem）
- 讀取：`list_content_controls` ⚡（flat 或 nested tree mode），`get_content_control`（by id / tag / alias，回 metadata + `<w:sdtContent>` XML）
- 修改：`update_content_control_text`（preserves `<w:sdtPr>` byte-identical），`replace_content_control_content`（whitelist validation，拒絕含 `<w:sdt>` / `<w:body>` / `<w:sectPr>` 的 input）
- 刪除：`delete_content_control`（`keep_content: true` 預設 unwrap children）
- Repeating sections：`insert_repeating_section`, `list_repeating_section_items`, `update_repeating_section_item`
- 表單便利：`insert_checkbox`, `insert_dropdown`, `insert_text_field`
- v0.15.0 SDT id allocator 改 max+1 deterministic（取代 random）

### 主題編輯（v3.3.0+，#28）

- `get_theme` — 讀 major/minor 字體 + 色盤
- `update_theme_fonts` — 部分更新字體 slot（latin/ea/cs）。**用於 NTPU 論文中文字體修復**：`update_theme_fonts({ minor: { ea: "DFKai-SB" }})`
- `update_theme_color` — slot-named hex color 更新（accent1-6 / hyperlink / followedHyperlink）
- `set_theme` — 完整 theme XML 覆寫 escape hatch

### 圖片

- `insert_image`, `insert_image_from_path`, `insert_floating_image`
- `update_image`, `delete_image`, `list_images` ⚡, `set_image_style`
- `export_image`, `export_all_images`, `insert_drop_cap`

### 數學公式（v3.2.0+ 完整 LaTeX 子集）

- `insert_equation` — 透過 [`latex-math-swift`](https://github.com/PsychQuant/latex-math-swift)：`\frac`, `\sqrt`, `\hat`/`\bar`/`\tilde`, `\left/\right`, `\sum`/`\int`/`\prod`（with bounds），`\ln`/`\sin`/`\cos`/`\tan`/`\log`/`\exp`/`\max`/`\min`/`\det`，`\sup`/`\inf`/`\lim`，`\text{}`，全部希臘字母（含 `\varepsilon` 變體）+ 常用運算子
- `list_equations`, `get_equation`, `update_equation`, `delete_equation`
- `splice_omath_from_source`, `splice_paragraph_omath_from_source` — 跨 doc verbatim copy `<m:oMath>` XML（v3.20.0+，#160；wraps ooxml-swift v0.24.0 `spliceOMath` API）

### 匯出

- `export_text`, `export_markdown` ⚡, `export_revision_summary_markdown`, `export_comment_threads_markdown`

### 註解（v3.4.0+ thread 管理）

- 寫入：`insert_comment`, `update_comment`, `delete_comment`, `reply_to_comment`, `resolve_comment`
- 讀取：`list_comments` ⚡
- Thread 管理：`list_comment_threads`, `get_comment_thread`, `sync_extended_comments`

### People / Comment Authors（v3.4.0+，v3.5.0 dual identity #34）

- `list_people` — 解析完整 `<w15:presenceInfo>`，回 dual identity：
  - `person_id` (GUID, 來自 `userId="S::email::guid"` 第三段)，rename 跨版本穩定
  - `display_name_id` (= author，v3.4.0 legacy id)
  - `display_name`, `email`, `color`, `provider_id`
- `add_person`, `update_person`, `delete_person` — 接受 GUID **或** legacy author 任一形式

### Track Changes / Revisions（v3.12.0 寫側 #45）

- 既有修訂處理：`enable_track_changes`, `disable_track_changes`, `get_revisions` ⚡, `accept_revision`, `reject_revision`, `accept_all_revisions`, `reject_all_revisions`
- **v3.12.0 程式化生成（NEW）**：
  - `insert_text_as_revision(doc_id, paragraph_index, position, text, author?, date?)` — `<w:ins>` 包覆，跨 run split 處理
  - `delete_text_as_revision(doc_id, paragraph_index, start, end, author?, date?)` — `<w:del>` 標記 + `<w:t>` → `<w:delText>` substitution（單段內，跨段 OOS）
  - `move_text_as_revision(doc_id, from_paragraph_index, from_start, from_end, to_paragraph_index, to_position, author?, date?)` — paired `<w:moveFrom>` / `<w:moveTo>` with adjacent revision ids
  - `format_text` 加 `as_revision: bool` → `<w:rPrChange>`
  - `set_paragraph_format` 加 `as_revision: bool` → `<w:pPrChange>`
- 比對：`compare_documents`, `compare_documents_markdown`

### 註腳與尾注（v3.4.0+ 補完 update）

- 寫入：`insert_footnote`, `delete_footnote`, `insert_endnote`, `delete_endnote`
- 讀取：`list_footnotes` ⚡, `list_endnotes` ⚡
- v3.4.0+：`get_footnote`, `update_footnote`, `get_endnote`, `update_endnote`（in-place 替換、保留 ID）

### 標號與目錄

- `insert_caption`, `list_captions`, `get_caption`, `update_caption`, `delete_caption`（v3.1.0+）
- `insert_table_of_figures`, `insert_index`, `insert_index_entry`, `insert_toc`
- `update_all_fields`（v3.1.0+，#19）— F9 等價，全文 SEQ 重算
- `insert_cross_reference`

### Custom XML / Web Settings

- `list_custom_xml_parts`（v3.9.0+ stub，real impl 待 Change B）
- `get_web_settings`, `update_web_settings`（v3.4.0+，#31）— `relyOnVML` / `optimizeForBrowser` / `allowPNG` / `doNotSaveAsSingleFile`

### 屬性與保護

- `get_document_properties` ⚡, `set_document_properties`
- `get_section_properties` ⚡, `get_word_count_by_section` ⚡
- `protect_document`, `unprotect_document`, `set_document_password`, `remove_document_password`
- `restrict_editing_region`

### 欄位代碼

- `insert_date_field`, `insert_page_field`, `insert_sequence_field`, `insert_merge_field`
- `insert_calculation_field`, `insert_if_field`, `insert_text_field`

### 進階格式 / 排版

- 分欄、tab stops、drop cap、horizontal line、symbol
- `insert_horizontal_line`, `insert_drop_cap`, `insert_symbol`, `insert_column_break`
- `insert_tab_stop`, `clear_tab_stops`
- `set_keep_lines`, `set_keep_with_next`, `set_widow_orphan`, `set_outline_level`, `set_page_break_before`
- 字體和語言：`set_language`

⚡ = 支援 Direct Mode

## 技術細節

- **語言**: Swift（macOS 13.0+）
- **MCP SDK**: swift-sdk 0.12+
- **OOXML 引擎**: [`ooxml-swift v0.19.2`](https://github.com/PsychQuant/ooxml-swift)（preserve-by-default + dirty tracking + revision generation + `document.xml` lossless round-trip）
- **LaTeX parser**: [`latex-math-swift v0.1.0+`](https://github.com/PsychQuant/latex-math-swift)（v3.2.0+）
- **Markdown export**: [`word-to-md-swift`](https://github.com/PsychQuant/word-to-md-swift) + [`markdown-swift`](https://github.com/PsychQuant/markdown-swift)

## 版本

- **Plugin shell**: v3.13.2
- **Binary**: v3.13.2（`CheWordMCP`）
- **GitHub**: https://github.com/PsychQuant/che-word-mcp
- **完整 CHANGELOG**: https://github.com/PsychQuant/che-word-mcp/blob/main/CHANGELOG.md

### Plugin Shell vs Binary 版本

兩者獨立但本次 v3.13.2 同步。Plugin shell（marketplace 端，含 SKILL.md / CLAUDE.md / `.mcp.json` / wrapper）有自己的 minor，反映文件 / skill 變動；Binary（GitHub release 端）有自己的 minor，反映 MCP server 內部新增 tool 或修 bug。Wrapper auto-download 從 release fetch binary 到 `~/bin/CheWordMCP`。

### 重要 milestones

- **v3.13.2** — bump ooxml-swift v0.19.1→v0.19.2，修正 v3.13.1 的 6-AI verification 找到的 4 個 blocking findings（無 source 變更）：F1 `Hyperlink.toXML()` 真正 emit Reader 解出的 runs/rawAttributes/rawChildren（pre-fix 把所有 inner runs 攤平成單一 hardcoded 藍底線 styled run）、F2 `addBookmark`/`deleteBookmark` 同步 `bookmarkMarkers`（pre-fix source-loaded paragraph 的新 bookmark 在 save 時被靜默丟掉、刪除留下 zombie `name=""` markers）、F3 `<w:ins>`/`<w:del>`/`<w:moveFrom>`/`<w:moveTo>` Reader 為 inner runs 設 `position`+`revisionId` + Writer sort path 重新 group runs by revisionId 包回 wrapper（pre-fix wrapper 在 source-load round-trip 後完全消失）、F4 namespace 保留從 `document.xml` 擴展到 header/footer/footnote/endnote 各自的 root（pre-fix NTPU thesis VML watermark headers declaring mc/wp/w14/w15 silently 退化到 hardcoded 5-namespace template）
- **v3.13.1** — `pPr` double-emission silent regression hot-fix（bump ooxml-swift v0.19.0→v0.19.1，無 source 變更）。NTPU thesis 驗證時抓到：v3.13.0 round-trip 後 `<w:pPr>` 被雙重 emit，unrecognized children 從 799→1333（+67%）。1-line `case "pPr": break` 修正
- **v3.13.0** — `document.xml` lossless round-trip + tool-mediated wrapper edits（closes [#56](https://github.com/PsychQuant/che-word-mcp/issues/56) P0）— 完整保留 `<w:document>` root 34 個 `xmlns:*` declarations、`<w:bookmarkStart>` / `<w:hyperlink>` / `<w:fldSimple>` / `<mc:AlternateContent>` 全程 round-trip（pre-v3.13.0 silently 丟掉 32 namespaces / 100% bookmarks / 354 個 `<w:t>` text nodes 在 wrapper 內），`replace_text` 走 wrapper-internal runs（無 silent failure）。Built on ooxml-swift v0.19.x
- **v3.12.0** — Programmatic Track Changes 生成 — 3 新 MCP 工具（insert_text_as_revision / delete_text_as_revision / move_text_as_revision）+ 2 擴充 args（format_text / set_paragraph_format 加 `as_revision: bool`）— closes [#45](https://github.com/PsychQuant/che-word-mcp/issues/45)，**Office.js OOXML Roadmap P0 100% 完成**
- **v3.11.0** — Tables / Hyperlinks / Headers extensions（16 新工具：5 table conditional/nested/layout + 3 typed hyperlinks + 4 header even/odd/link/section-map）— closes [#49](https://github.com/PsychQuant/che-word-mcp/issues/49) [#50](https://github.com/PsychQuant/che-word-mcp/issues/50) [#51](https://github.com/PsychQuant/che-word-mcp/issues/51)
- **v3.10.0** — Styles + Numbering + Sections foundation（19 新工具 + 6 擴充 args：4 style inheritance/link/latent/alias + 8 numbering definition lifecycle + 7 section vertical/break/title-page）— closes [#46](https://github.com/PsychQuant/che-word-mcp/issues/46) [#47](https://github.com/PsychQuant/che-word-mcp/issues/47) [#48](https://github.com/PsychQuant/che-word-mcp/issues/48)
- **v3.9.0** — Content Controls (SDT) 完整 read/write（7 新工具 + 12-type discrimination + nested SDT tree）— closes [#44](https://github.com/PsychQuant/che-word-mcp/issues/44)
- **v3.8.0** — Header/footer raw-element preservation + counter-isolation flag — closes [#52](https://github.com/PsychQuant/che-word-mcp/issues/52)
- **v3.7.0–v3.7.2** — Save durability cycle: path-traversal 修正 / hdr-ftr auto-suffix / `updateAllFields`（#53–#55, #54）
- **v3.6.0** — Save durability + autosave Design B + serial-only OOXML IO — closes #40 #41
- **v3.5.0** — true byte-preservation via dirty tracking — closes #23 round-2 + #32 #33 #34
- **v3.4.0** — Phase 2B+2C: 13 個 comment-thread/people/notes-update/web-settings 工具 — closes #24 #25 #29 #30 #31
- **v3.3.0** — Phase 2A: 12 個 theme/header/footer/watermark 工具 — closes #26 #27 #28
- **v3.2.0** — `insert_equation` LaTeX parser delegated to `latex-math-swift` — closes #22
- **v3.1.0** — 9 個 readback tools（Caption CRUD, update_all_fields, Equation CRUD）— closes #17 #19 #21
- **v3.0.0** — Session state API（dirty tracking, autosave, finalize_document, disk drift detection）— closes #12 #13 #15

### 底層架構里程碑

- **`ooxml-swift v0.19.0–0.19.2`** — `document.xml` lossless round-trip：root namespace preservation（34 `xmlns:*` + `mc:Ignorable`）+ Bookmark Reader parsing + Wrapper hybrid model（`Hyperlink` / `FieldSimple` / `AlternateContent` typed editable surface + raw passthrough）+ sort-by-position Writer emit + 6 raw-carrier types for `<w:p>` schema completeness。v0.19.1 修正 v0.19.0 的 pPr double-emission silent regression。v0.19.2 修正 6-AI verification 找到的 4 個 blocking findings：Hyperlink writer 真正 iterate runs+rawAttributes+rawChildren、bookmark mutation API 同步 markers、ins/del/moveFrom/moveTo wrapper round-trip（Reader 設 position+revisionId、Writer sort path 重新 group by revisionId）、namespace 保留擴展到 header/footer/footnote/endnote（新 `ContainerRootTag` helper）
- **`ooxml-swift v0.18.0`** — Revision generation primitives（6 new WordDocument methods + writer-side `Paragraph.toXML()` revision wrapping + `<w:t>` → `<w:delText>` substitution）
- **`ooxml-swift v0.16.0–0.17.0`** — Styles inheritance / Numbering lifecycle / Section vertical alignment / Table conditional+nested+indent / Typed hyperlinks / Even-odd headers
- **`ooxml-swift v0.15.0–0.15.1`** — `SDTParser` first-class `<w:sdt>` model + `BodyChild.contentControl` + max+1 SDT id allocator
- **`ooxml-swift v0.13.0–0.14.0`** — true byte-preservation via dirty tracking + raw-element preservation
- **`ooxml-swift v0.12.0`** — preserve-by-default 架構（PreservedArchive + RelationshipIdAllocator + ContentTypesOverlay）
- **`ooxml-swift v0.10.0–0.11.0`** — `FieldParser` + `OMMLParser` readback primitives + `MathAccent`

## Office.js OOXML Roadmap P0 Closure Map

| § | Sub-issue | che-word-mcp 版本 |
|---|-----------|-------------------|
| §1 Content Controls (SDT) | [#44](https://github.com/PsychQuant/che-word-mcp/issues/44) | v3.9.0 |
| §2 Track Changes 寫側 | [#45](https://github.com/PsychQuant/che-word-mcp/issues/45) | v3.12.0 |
| §3 Numbering | [#46](https://github.com/PsychQuant/che-word-mcp/issues/46) | v3.10.0 |
| §4 Sections | [#47](https://github.com/PsychQuant/che-word-mcp/issues/47) | v3.10.0 |
| §8 Styles | [#48](https://github.com/PsychQuant/che-word-mcp/issues/48) | v3.10.0 |
| §9 Tables | [#49](https://github.com/PsychQuant/che-word-mcp/issues/49) | v3.11.0 |
| §14 Hyperlinks | [#50](https://github.com/PsychQuant/che-word-mcp/issues/50) | v3.11.0 |
| §16 Headers / Footers | [#51](https://github.com/PsychQuant/che-word-mcp/issues/51) | v3.11.0 |

Umbrella [#43](https://github.com/PsychQuant/che-word-mcp/issues/43) — closed 2026-04-25。
