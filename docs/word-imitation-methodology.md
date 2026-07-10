# Word 模仿三層階梯 — 方法學

跨 #130（format-alignment-engine）、#131（word-canonical-forms）、
render-effect-semantics 三個 change 沉澱出的方法學。核心問題是「系統對一份
真實 Word 文件的掌握到什麼程度」——答案不是一個數字，是一座階梯：每一層
是一種**可被 gate 驗證的主張**，爬得越高、主張越強、驗收越貴。

本文件是可移植的方法論；Word 只是第一個實例。套用到新格式（pptx、PDF、
`.note`）時見文末 checklist。

## 三層階梯總覽

| 層 | 主張 | Gate（驗收機制） | 主張強度 | 產物 |
|----|------|------------------|----------|------|
| **1. 複製**（copying） | 「我能一位元組不差地重現這份文件」 | Stage B byte-equal（raw channel carryPart） | 零理解——複製不需要懂 | byte-equal floor，永遠恆綠 |
| **2. 合法序列化**（legitimate serialization） | 「我能用自己的型別化操作語言拼寫出這份文件」 | trial-rebuild byte-equal gate：typed ops 從空文件重放 → 序列化 → 與原文位元組相等才升級 | 結構理解——每個設定有名字、可單獨操作 | DSL coverage %（理解度量尺） |
| **3. 渲染理解**（rendering semantics） | 「我知道這個設定改了會對排版產生什麼效果」 | perturbation probe：預測方向+幅度 → 真實 Word 渲染 → 幾何量測驗證 | 語意理解——可預測後果 | render-effect registry（理解台帳） |

三層是嚴格遞進的：**能複製 ≠ 能拼寫，能拼寫 ≠ 理解效果**。每一層的
gate 都不豁免、不推斷、不假裝——這是整套方法的靈魂。

## 每層的定義

### Layer 1 — 複製是 floor，不是成就

raw channel 逐位元組搬運所有 parts。byte-equal 由此無條件保證，與理解
無關。方法學意義：**正確性（對不對）與理解度（懂多少）分離**——floor
負責正確性，上層的 coverage 才是理解度。任何時候上層失敗，都能誠實退回
floor 而不犧牲正確性。

### Layer 2 — 拼寫要用合法操作，且逐字驗證

一個 content class 要從 raw 升級到 typed DSL channel，唯一的路是
**trial-rebuild byte-equal gate**：extractor 把該形式解析成 typed op，
reducer 重放後序列化，位元組與原文完全相等才算「會拼寫」。

- **per-part 全有全無**：part 裡只要有一個形式拼不出來，整個 part 留 raw。
- **不設 canonical-form 豁免**：serializer 拼不出 Word 的慣用形
  （屬性順序、CRLF prolog、namespace 雲）就是不會拼，不准辯稱「語意等價」。
- **form-gap report 是工作佇列，不是文件**：量測印出「第一個不支援的
  形式在哪」，落地該形式，再量測——迴圈跑到 gap 歸零。#131 靠這個迴圈
  把 90_template_ja 的 document.xml 從 0% 推到 per-part 100%。

### Layer 3 — 理解的操作型定義

> 系統「理解」設定 X，當且僅當它能**預測**改動 X 的可量測渲染後果，
> 且 gated probe 對照**真實 Word 渲染**驗證了這個預測。

- **Registry 是台帳**：每條 entry 記欄位、observable、預測方向、預期
  幅度（含單位換算）、容差、實測證據（值 + 日期 + Word 版本）、probe
  名、狀態。**no probe, no claim**——沒有綠 probe 的 entry 標
  `unverified`，且不准放寬容差硬轉綠。
- **Probe 協定**：typed ops 建 baseline，**只擾動一個欄位**建 perturbed，
  兩份都經真實 Word 渲染成 PDF，用 PDFKit 幾何量測（行框、頁框、中位
  行距）比對。
- **方向嚴格、幅度容差**：方向錯 = 效果模型錯，直接 fail；幅度在
  ±10% 或 ±1pt（取大者）內——渲染有 device-space 捨入，追求精確等值
  只會製造 flaky。

## 橫切的方法學原則

1. **主張必須綁 gate**。「支援 X」「理解 Y」這類話在本專案沒有修辭意義
   ——每個主張對應一個可重跑的驗證機制，gate 沒過就不許說。
2. **誠實優於體面**。coverage 0% 不是失敗，是誠實；`unverified` 不是
   恥辱，是紀錄。系統不謊稱懂它沒證明過的東西，讀數字的人因此能信任
   每一個非零的數字。
3. **量測即工作佇列**。不寫「未來計畫」文件——量測工具直接指出下一個
   要落地的 gap，落完重測。文件記錄的是**已驗證的過去**，不是希望。
4. **單變因隔離**。perturbation 只能差一個欄位，fixture 要把其他變因
   顯式釘死（如 spacing 全釘 0），否則量到的是交互作用不是效果。
5. **Ground truth 用合成 fixture**。量測工具本身的正確性，要用「已知
   答案」的合成 fixture 驗（CoreText 在精確 baseline 畫的 PDF），不能用
   被測系統的輸出自舉——那是循環論證。
6. **規格是預測來源，實測是裁決**。ECMA-376 給你預測（twips/20），
   Word 的實際渲染才是 oracle。兩者不合時，registry 記錄實測並保留
   預測偏差——那正是最有價值的知識（見下節）。
7. **Oracle 要 gate、缺席要 loud skip**。需要真實 Word 的測試鎖在
   `RUN_WORD_INTEGRATION=1` 後面，真實文件鎖在 `MACDOC_TEMPLATE_DIR`
   後面；缺 gate 就指名跳過，絕不默默 pass 或默默 fail。CI 永遠綠，
   維護者機器才跑全套。
8. **範圍決策升級給人**。量測發現超出提案範圍的形式（如 inline
   markers）時，停下來把 scope 決策交給使用者，不自行擴權。

## 為什麼需要第三層 — probe 賺到的理解

三筆 byte-equal gate **原理上不可能發現**的知識，全部由 probe 的失敗
或量測直接換來（詳見 [render-effect-registry.md](render-effect-registry.md)）：

| 發現 | 怎麼來的 |
|------|----------|
| Word 對相鄰 before/after spacing 取 **max 而非相加** | 第一次 spacing probe 實測 Δ4pt vs 預測 12pt——fixture 沒釘住預設值，暴露了 collapse 行為 |
| docGrid `lines` 絕對行距 ≈ 名目 ×1.16 | 行距 probe 的絕對值系統性偏移，delta 卻精準符合預測 |
| A4 頁框量化為 595.2×841.92pt（非 twips/20 的 595.3×841.9） | 頁框「精確」斷言失敗，換來 Word 內部量化的證據 |

拼寫層看這三個設定，位元組完全正確；只有渲染層知道它們**實際做什麼**。

## 推廣到新格式的 checklist

對任何「模仿一種既有文件格式」的專案（pptx、PDF、`.note`…）：

- [ ] **Layer 1**：建 raw byte-equal floor（逐部件搬運 + 全集比對），
      讓正確性先於理解被鎖死。
- [ ] **Layer 2**:定義 typed op 詞彙 + trial-rebuild byte-equal gate +
      per-part 全有全無升級；建 form-gap 量測，跑 measure→land→re-measure
      迴圈；用真實文件（env-gated）當北極星 fixture。
- [ ] **Layer 3**：找到該格式的 rendering oracle（Word / PowerPoint /
      PDF viewer），建幾何量測工具（先用合成 ground-truth fixture 驗工具
      本身），開 effect registry，一條 entry 一個單變因 probe。
- [ ] 全程套用上面八條橫切原則——特別是「主張綁 gate」與「誠實優於
      體面」，那兩條是其餘一切的前提。

## 文件地圖

| 文件 | 角色 |
|------|------|
| 本文件 | 方法學（為什麼這樣做） |
| [format-alignment-baselines.md](format-alignment-baselines.md) | 量測紀錄（各 fixture 的 coverage 與渲染驗收快照） |
| [render-effect-registry.md](render-effect-registry.md) | Layer 3 理解台帳（entry + 證據） |
| `openspec/specs/format-alignment-pipeline/` | Layer 1–2 規範 |
| `openspec/specs/ooxml-script-transcode/`、`ooxml-operation-log/` | 拼寫層詞彙與轉碼契約 |
| `openspec/specs/docx-render-semantics/`、`docx-visual-diff-testing/` | Layer 3 規範（歸檔後生效） |
