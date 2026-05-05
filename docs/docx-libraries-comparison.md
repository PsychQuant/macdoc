# OOXML 函式庫對照：docx-js / python-docx / pandoc / macdoc

> **macdoc 不是這三個 library 的另一個變體。它是「stable identity + op log + bidirectional Word sync」的第一個實作。**

`reference/` 收三個 docx 領域的代表 library 作為 macdoc 設計的對照組。本文件解釋為什麼選這三個、它們各自代表什麼典範、缺少什麼，以及 macdoc 在這個 design space 的精確位置。

相關文件：
- `swift-as-document-source.md`：macdoc 的 DSL（`.mdocx`）為什麼長那樣
- `structural-editing-paradigm.md`：conversion ≠ editing 的根本區別
- `reference/README.md`：如何 clone 這三個 library 到本機

---

## 1. 三個典範

### 1.1 docx-js — Typed Builder

**Repo**: https://github.com/dolanmiu/docx
**語言**: TypeScript
**Code path**: `reference/docx-js/src/file/`

```typescript
import { Document, Paragraph, TextRun, HeadingLevel } from "docx";

const doc = new Document({
    sections: [{
        children: [
            new Paragraph({
                heading: HeadingLevel.HEADING_1,
                children: [new TextRun("第一章")],
            }),
            new Paragraph({
                children: [
                    new TextRun("本章探討"),
                    new TextRun({ text: "意識本質", bold: true }),
                    new TextRun("的議題。"),
                ],
            }),
        ],
    }],
});
```

**典範特徵**：
- Compose docx by composing typed builder objects
- Strong types, IDE auto-completion, parameter discoverability
- 純「from-scratch」工具——不能 read existing docx
- 沒有 stable identity 機制（builder 不知道自己對應 Word 內哪個 paraId）

**對應 macdoc 哪一層**：
`word-builder-swift` 是其 1:1 Swift 移植，定位是 macdoc 的「便利寫作 API」入口，而**不是** word-aligned 的 source of truth。

### 1.2 python-docx — Tree-Backed Wrapper

**Repo**: https://github.com/python-openxml/python-docx
**語言**: Python + lxml
**Code path**: `reference/python-docx/src/docx/`

```python
from docx import Document

doc = Document("existing.docx")           # 讀進來，包成 lxml tree
para = doc.paragraphs[0]                  # typed wrapper
para.text = "新文字"                       # 直接 mutate 對應 lxml element
para.runs[0].font.bold = True             # 進一步 mutate
doc.save("modified.docx")                 # 序列化 lxml → docx
```

**典範特徵**：
- 每個 `Document` / `Paragraph` / `Run` 包一個 `lxml._Element`
- typed accessor 讀寫該 element（getter delegates to `etree`, setter mutates `etree`）
- 可 read existing docx + mutate
- 沒有 op log——直接改 lxml tree，沒有 history、無法 replay、無法 undo

**對應 macdoc 哪一層**：
`word-aligned-state-sync` Phase 1 的 typed-as-projection 設計**直接對照 python-docx 的 wrapper pattern**。我們的 `Paragraph` / `Run` / `Table` 在 Phase 1 後變成「typed view over XmlNode tree」，跟 python-docx 的「lxml-backed wrapper」是同一個架構模式。**差別**：macdoc 加 op log，每次 mutation emit operation；python-docx 沒做這層。

### 1.3 pandoc — AST Converter

**Repo**: https://github.com/jgm/pandoc
**語言**: Haskell
**Code path**: `reference/pandoc/src/Text/Pandoc/`

```haskell
-- 概念上
docxBytes :: ByteString
ast       :: Pandoc           -- 中介 AST，format-agnostic
markdown  :: Text

ast      = readDocx docxBytes
markdown = writeMarkdown ast
```

**典範特徵**：
- 雙向轉換：每個 format 都有 `Reader: Format → AST` + `Writer: AST → Format`
- AST（`Pandoc` data type）是 format-agnostic 中介層
- AST 表達不出來的東西全部 lossy（VML shape、custom XML、Word 特有的 sectPr 變化）
- 沒有 stable identity；每次轉換產生新元素

**對應 macdoc 哪一層**：
不對應任何 macdoc 層級。pandoc 解的是「跨 format 互轉」問題，macdoc 解的是「跟 Word 同檔協作」問題。兩者問題範疇不同。
但 pandoc 是 **「複雜 format 邊界 case」的黃金對照**——遇到 Word 詭異輸入時丟同一份檔案給 pandoc 看它怎麼處理，是判斷 macdoc converter 應否跟進的快速 reference。

---

## 2. 三個典範在 design space 的座標

```
                  Build docx
                  from scratch
                       │
                  docx-js（typed builder）
                  word-builder-swift（同模式，Swift 版）
                       │
       ┌───────────────┼────────────────┐
       │               │                │
   Read & edit         │           Convert to/from
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

|軸|docx-js|python-docx|pandoc|word-builder-swift|**macdoc (ooxml-swift Phase 1+)**|
|---|---|---|---|---|---|
|Build docx from scratch|✓|✓ (clumsy)|✓ (markdown→docx)|✓|✓|
|Read existing docx|✗|✓|✓ (lossy)|—|✓|
|Mutate existing docx|✗|✓ (manual)|✗|—|✓|
|**Stable element ID**|✗|✗|✗|✗|**✓**|
|**Op log persistence**|✗|✗|✗|✗|**✓**|
|**Word import as ops**|✗|✗|✗|✗|**✓**|
|Byte-equal round-trip|N/A|✗|✗|—|**✓**|
|Replayable history|✗|✗|✗|✗|**✓**|
|跨 format 互轉|✗|✗|**✓**|✗|partial（macdoc CLI converters）|

macdoc 在 op log + stable ID + sync 三個面向是這四個 library 中**唯一全備的**。
這個 differentiator 不是行銷話術，是來自一個非常具體的工作流需求：作者想在 Swift 跟 Word 兩邊同時寫，且不互相蓋。

---

## 3. 為什麼選這三個對照（而不是另外的）

OOXML 領域還有不少 library——為什麼 reference/ 只 clone 這三個？

| 候選 library | 為什麼**沒**選 |
|---|---|
| **docx4j** (Java) | 跟 docx-js 同類型 (typed builder + manipulator)，沒提供新 design point；Java mental model 對 Swift 借鑑度低於 TypeScript |
| **Apache POI** (Java) | 同上；且 POI 是「Office 全家桶」覆蓋 .xlsx / .pptx，docx 部分相對單薄 |
| **officegen** (Node) | 跟 dolanmiu/docx 同生態位，邊界處理略強但典範重複 |
| **docx-rs** (Rust) | 新；典範跟 docx-js 接近 |
| **OpenXmlSDK** (.NET / C#) | Microsoft 官方；但是 C# OOP 風格對 Swift design 不直接借鑑；schema browser 比 docx-js 完整，但已在「外部官方規範連結」段列為線上 reference |
| **pandoc-types** | 是 pandoc 的 AST 定義，不是獨立 library |

選三個的理由：**一個 design point 配一個 library**——builder / wrapper / converter，剛好覆蓋 docx 操作的三個基本範式。多 library 同範式不會增加新 insight，只增加維護負擔。

未來若出現新範式（例如「event-sourced docx」「CRDT docx」）才會考慮 clone 第四個。截至 2026-05-05 沒有。

---

## 4. 在不同階段，從哪個 library 學什麼

### Phase 0（v0.30.0，已完成）— XmlNode tree foundation

**主要對照**：python-docx 的 `oxml/parser.py` + `oxml/ns.py`
- 怎麼處理 namespace registration
- 怎麼把 raw XML element 包成 typed wrapper 的 base class
- 哪些 OOXML element 必須 first-class、哪些可以 fallback to generic

`reference/python-docx/src/docx/oxml/parser.py` 的 `register_element_cls()` pattern 跟我們的 `XmlNode.stableID` derivation 解的是同類問題。

### Phase 1 — Typed views as tree projections

**主要對照**：python-docx 的 `text/paragraph.py` + `table/_cell.py`

```python
# python-docx 的 Paragraph.text getter
@property
def text(self) -> str:
    return "".join(run.text for run in self.runs)

# Setter mutates lxml tree
@text.setter
def text(self, text: str):
    self.clear()
    self.add_run(text)
```

我們的 Phase 1 `Paragraph.text` 會走同樣的 getter pattern，但 setter 改成 emit `{op: "SetRuns", id: self.stableID, runs: [{text}]}`，由 reducer 套用到 tree。

### Phase 7 — DSL（`.mdocx`）

**主要對照**：docx-js 的 `src/file/document/document.ts`
- declarative `Document({ sections: [...] })` syntax 拆解
- 怎麼從 nested config object 推 typed builder hierarchy
- option object 跟 child array 的 boundary

我們的 DSL 用 Swift result builder 比 docx-js 的 plain object literal 更 ergonomic，但 sections / paragraphs / runs 的 hierarchical thinking 來自 docx-js。

### CLI converters（已存在於 macdoc）

**主要對照**：pandoc 的 `Readers/Docx.hs` + `Writers/Markdown.hs`
- 跨 format 邊界 case 怎麼判斷哪些 attribute 該保、哪些該丟
- 不同 markdown flavor 的對應（GFM vs CommonMark vs pandoc-flavored）

`heuristic-output.md` 規則寫的「源格式設定層 → 內部樣式模型 → 目標格式設定層」設計受 pandoc Reader/Writer 啟發。

---

## 5. 拒絕的 design choice 跟對應 library

|拒絕的 design|理由|哪個 library 走這條（或沒走）|
|---|---|---|
|純 typed builder（不可 read existing）|無法 align Word 編輯|docx-js / docx4j / Apache POI 都這樣|
|純 lxml-style wrapper（沒 op log）|無法 reconcile Swift 編輯 vs Word 編輯|python-docx|
|AST intermediary（lossy by design）|byte-equal round-trip 做不到|pandoc|
|CRDT 在 docx 內部（custom XML part）|Word 自動 strip 不認得的 attribute / part|沒人走（Word 強制限制）|
|Two-actor live editing|Word 鎖檔機制不支援|沒人走（OS 限制）|

每個拒絕的 design 在某個 library 裡是現役產品，但都不能滿足 macdoc 的 alignment 需求。所以 macdoc 必須是新組合，不能是現有 library 的 fork。

---

## 6. 對 reference clone 的維護期望

|library|更新頻率|為什麼還留|
|---|---|---|
|`docx-js`| 一季 pull 一次 | `word-builder-swift` 1:1 mirror，要追上游 API 變動 |
|`python-docx`| 一季 pull 一次 | `ooxml-swift` Phase 1-3 設計時持續對照；Phase 完成後降低頻率 |
|`pandoc`| 半年 pull 一次 | 邊界 case reference,主要看穩定 release 版本而非 main |

不需要追每個 commit。reference 是「需要時拿出來查」的鏡子，不是 dependency。

---

## 7. 小結

|要解的問題|看哪個|
|---|---|
|寫新 builder API 的命名 / 簽名|docx-js|
|讓 typed model 變成 tree projection|python-docx|
|處理跨 format 轉換的詭異 case|pandoc|
|想知道 macdoc 為什麼跟它們都不一樣|本文件 §2 對照表|

**macdoc 的 design space 位置**：在「能 read + mutate existing docx + bidirectional Word sync + replayable history」這個四維交集裡，目前是唯一一個。
這個位置是要付代價的（事件溯源架構複雜度）；但這個代價是「能跟 Word 並行寫一份檔案」這個工作流的入場費，沒有捷徑。
