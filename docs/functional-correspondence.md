# Functional Correspondence

一個關於文檔格式轉換的設計論述。

---

## 核心主張

> **不存在中立的中間表示。**
>
> 轉換決策不可避免，但把決策延後到「通用層」會迫使你丟資訊。
> 把決策前移到 extract 階段，等於直接承認這個事實，在工程上反而更誠實。

---

## 1. Target-aware Extraction

### 1.1 傳統 Serialization 的問題

傳統做法假設存在「中立」的序列化：

```
serialize: Document → [Element]
```

但這是一個幻覺。**序列化本身就需要做決策**，而這些決策必然依賴於目標格式。

### 1.2 我們的做法：extract_{s→t}

我們明確承認：extraction 是 **(source, target) pair** 決定的。

```
extract_{s→t}: Source → [Element_t]

extract_{Word→MD} ≠ extract_{Word→HTML}
```

這不是 serialize，而是 **Target-aware Extraction**——針對目標格式做投影。

### 1.3 範例：Word 註解的投影

Word 的註解是**附著在文字範圍**上的：

```
Word 內部結構：
  Paragraph: "這是一段文字"
      ↑
      Comment(range: 2..5, text: "這裡需要修改")
```

不同的目標需要不同的投影：

```
extract_{Word→MD}:
  → [Paragraph("這是[^1]一段文字"), Footnote(1, "這裡需要修改")]
  -- 用腳註表示註解

extract_{Word→HTML}:
  → [Paragraph("這是<abbr title='這裡需要修改'>一</abbr>段文字")]
  -- 用 inline 元素表示註解
```

**同樣的 Word 文件，不同的 extract！** 因為目標格式的表達能力不同。

### 1.4 為什麼叫 extract 而不是 serialize？

| 術語 | 語意 | 決策點 |
|------|------|--------|
| serialize | 中立的「讀取」 | 假裝沒有決策 |
| extract_{s→t} | 針對目標的「投影」 | 明確在此做決策 |

**extract 編碼了轉換決策**，而不只是「讀取 source」。

---

## 2. 為什麼不用通用 AST？資訊瓶頸的形式化

### 2.1 傳統做法

```
A (Source) ──π──→ B (AST) ──τ──→ C (Target)
```

### 2.2 問題的形式化：Non-injective Projection

設 π: A → B 為 Source 到 AST 的投影。

若 **π 不是 injective**（非單射），則：

```
∃ a, a' ∈ A: a ≠ a' ∧ π(a) = π(a')
```

一旦這種 **collapse** 發生，無論後續 τ: B → C 如何精巧，**都無法恢復 a 與 a' 的差異**。

### 2.3 視覺化

```
A (Source)        B (AST)         C (Target)
    │                │                │
    a₁ ────┐         │                │
           ├────→   b₁  ────────→    c₁
    a₂ ────┘         │                │
                     │                │
    (a₁ ≠ a₂)     (collapsed)     (無法區分)
```

### 2.4 範例：Word 段落屬性的 Collapse

```
Word 段落 a₁:                    Word 段落 a₂:
  - style: "Heading1"              - style: "Heading1"
  - outlineLevel: 1                - outlineLevel: 1
  - keepWithNext: true         ←→  - keepWithNext: false
  - pageBreakBefore: false         - pageBreakBefore: true

        ↓ π (投影到通用 AST)            ↓ π

通用 AST:                        通用 AST:
  - type: "heading"                - type: "heading"
  - level: 1                       - level: 1
  # keepWithNext? 丟失             # keepWithNext? 丟失
  # pageBreakBefore? 丟失          # pageBreakBefore? 丟失

            ↘                    ↙
               π(a₁) = π(a₂) = b
                      ↓
               Collapsed！

        ↓ τ (轉成 Markdown)

Markdown:
  # 標題

  即使 Markdown 有辦法表達（如 HTML 註釋、特殊語法），
  資訊已經在 AST 層丟失，τ 無能為力。
```

### 2.5 定理（非正式）

> **瓶頸定理**：若 π: A → B 存在 collapse（非 injective），
> 則對於任何 τ: B → C，組合 τ ∘ π 必然丟失資訊。

這不是關於「集合大小」（|B| < |A| 只是直覺），而是關於 **語意保真的不可逆性**。

---

## 3. Functional Correspondence 的解法

### 3.1 核心公式

```
convert(A) = map(f, extract_{A→T}(A))
```

其中：

- **extract_{A→T}(A)** — 針對目標 T 展開 A 成元素序列
- **f: Element → String** — 純函數，將元素格式化為目標字串
- **map** — 對序列中每個元素套用 f

### 3.2 關鍵特性

| 組件 | 職責 | 決策點 |
|------|------|--------|
| extract_{A→T} | 投影（考慮 T 的表達能力）| 轉換邏輯在此 |
| f | 格式化（純機械轉換）| 無決策 |

**f 是「愚笨的」**：它只知道怎麼把 Element 寫成字串。
**extract 是「聰明的」**：它知道目標格式能表達什麼，並據此做投影。

### 3.3 為什麼這樣設計？

```
傳統 AST 模式：
  A ──π──→ B ──τ──→ C
           ↑
      資訊瓶頸
      決策被迫在 τ 做，但資訊已丟失

我們的模式：
  A ──extract_{A→C}──→ [Element_C] ──f──→ C
          ↑
     決策在此做
     資訊還完整
```

**轉換決策前移**：在資訊還完整時就做決策，而不是等到瓶頸之後。

---

## 4. Streaming = Lazy Map

### 4.1 從 Eager 到 Lazy

```
Eager（傳統 AST）:
  elements = extract(A)     -- 全部載入
  results  = map(f, elements) -- 全部轉換
  output   = concat(results)  -- 全部輸出

Lazy（Streaming）:
  for e in extract(A):      -- 邊讀
      emit(f(e))            -- 邊輸出
```

### 4.2 記憶體模型

```
時間 →

t₁: extract(e₁)
t₂: buffer = [e₁]    ← 只有一個
t₃: emit(f(e₁))
t₄: extract(e₂)
t₅: buffer = [e₂]    ← 還是只有一個
t₆: emit(f(e₂))
...
```

**Queue size = 1**：記憶體中只有當前處理的那一個元素。

```
AST 模式:      [e₁, e₂, e₃, ..., eₙ]  ← O(n) 記憶體
Streaming:     [eᵢ]                    ← O(1) 記憶體
```

### 4.3 Markdown 的特殊性

**Markdown 的 serialize ≈ Id（恆等函數）**

```
Markdown 本身就是序列化的形式：
- 一行一行的文字
- 沒有複雜的嵌套結構
- 讀取順序 = 輸出順序
```

因此 `f(e)` 可以直接輸出字串，不需要「建構 Markdown 物件再序列化」。

```
f: Element → String
emit: String → IO ()

f ∘ emit 就是 streaming 輸出
```

---

## 5. 完整架構

### 5.1 圖示

```
Source          extract_{s→t}      f          emit          Target
──────          ─────────────     ───        ─────          ──────
Word        →      [Element]   →  f(e)   →   write    →    Markdown
                       ↓                       ↓
                 考慮 MD 能表達什麼        ≈ Id（直接輸出）
```

### 5.2 三個組件

#### extract_{Word→MD}：產生元素序列

```
extract_{Word→MD}: WordDocument → [Element]

extract(doc) = [
    Paragraph("標題", style: Heading1),
    Paragraph("內文...", style: Normal),
    Table([...]),
    ...
]
```

由 `ooxml-swift` 提供。**已經針對 Markdown 的表達能力做了投影**。

#### f：格式化函數

```
f: Element → String
```

純機械轉換，不做決策：

```swift
f(element) = match element {
    Paragraph(text, style, numbering) →
        | isHeading(style)    → "# " + text
        | isBullet(numbering) → "- " + text
        | otherwise           → text + "\n\n"

    Table(rows) → formatPipeTable(rows)
}
```

由 `markdown-swift` 提供格式化函數（`heading`, `bullet`, `table` 等）。

#### emit：輸出

```
emit: String → IO ()
```

由 `markdown-swift` 的 `StreamingOutput` 處理。

### 5.3 完整轉換

```
convert: WordDocument → IO ()

convert(doc) =
    for e in extract_{Word→MD}(doc):
        emit(f(e))
```

**只有一個 f，沒有中間 AST。**

---

## 6. f 的詳細定義

### 6.1 Pattern Matching

```
f: Element → String

f(e) = match e {
    Paragraph(p) → fParagraph(p)
    Table(t)     → fTable(t)
}
```

### 6.2 fParagraph

```
fParagraph: Paragraph → String

fParagraph(p) = match (style(p), numbering(p)) {
    (Heading(n), _)      → repeat("#", n) + " " + text(p) + "\n\n"
    (_, Bullet(level))   → indent(level) + "- " + text(p) + "\n"
    (_, Number(level))   → indent(level) + "1. " + text(p) + "\n"
    (_, _)               → text(p) + "\n\n"
}
```

### 6.3 fTable

```
fTable: Table → String

fTable(t) =
    let header = "| " + t.rows[0].map(text).join(" | ") + " |"
    let sep    = "|" + repeat("---|", t.cols)
    let body   = t.rows[1:].map(row → "| " + row.map(text).join(" | ") + " |")
    join("\n", [header, sep] + body) + "\n\n"
```

### 6.4 text（Run 格式化）

```
text: Paragraph → String
text(p) = p.runs.map(fRun).join("")

fRun: Run → String
fRun(r) = match (r.bold, r.italic, r.strike) {
    (T, T, _) → "***" + r.text + "***"
    (T, F, _) → "**" + r.text + "**"
    (F, T, _) → "_" + r.text + "_"
    (_, _, T) → "~~" + r.text + "~~"
    _         → r.text
}
```

---

## 7. 並行擴展

### 7.1 Profiling 事實：瓶頸在 extract，不在 f

實際 profiling（976K docx, 5367 paragraphs, 11734 runs, M4 Max）顯示：

```
Sample distribution:
  DocxReader.parseBody (extract)     80%   ← 瓶頸
  ZIP + NSXMLDocument (DOM 載入)     15%
  WordConverter (f + emit)           <1%   ← 幾乎免費
```

因此原始的 Producer-Consumer 雙線程模型效果有限——consumer 閒置 99% 的時間。
**真正的加速來自 parallelizing extract itself。**

### 7.2 實作：Parallel Chunked Extract

```
┌────────────────────────────────────────────┐
│  ZIP 解壓 + NSXMLDocument 載入 (serial)     │  15% — DOM 載入無法平行
└────────────────────┬───────────────────────┘
                     ↓
   bodyNodes[0..N] 拆成 M 個 chunk（M = CPU cores, min 64 per chunk）
                     ↓
┌──────────┬──────────┬──────────┬──────────┐
│ Core 1   │ Core 2   │ Core 3   │ Core 4   │  80% ÷ M
│ parse    │ parse    │ parse    │ parse    │
│ chunk 0  │ chunk 1  │ chunk 2  │ chunk 3  │
│ → [E₀]   │ → [E₁]   │ → [E₂]   │ → [E₃]   │
└────┬─────┴────┬─────┴────┬─────┴────┬─────┘
     └──── ordered merge (by chunk index) ────┘
                     ↓
┌────────────────────────────────────────────┐
│  f + emit (serial, in order)               │  <1%
└────────────────────────────────────────────┘
```

Thread safety 保證：
- 每個 chunk 處理 DOM 的**不相交子樹**（disjoint subtrees）
- 共享資料 `relationships`, `styles`, `numbering` 為**唯讀 value types**
- 使用 `DispatchQueue.concurrentPerform`，同步返回，無 async 傳染

### 7.3 chunk size 選擇

```
chunk_count = min(cpu_cores, ceil(N / 64))
chunk_size  = ceil(N / chunk_count)
```

| N (body children) | M4 Max (16 cores) | chunk size | 策略 |
|-------------------|-------------------|------------|------|
| ≤ 200 | — | N/A | **Serial path**（GCD overhead 不划算） |
| 5,367 | 16 | ~335 | Parallel |
| 50,000 | 16 | ~3,125 | Parallel |

### 7.4 Benchmark

976K docx (5367 paragraphs, 110 tables, 11734 runs), M4 Max:

| 版本 | 時間 | 記憶體 | 改善 |
|------|------|--------|------|
| v0.3.0 (XPath) | >30s | 281MB | — |
| v0.4.0 (children traversal) | ~1.8s | 189MB | 17x |
| **v0.5.0 (parallel parse)** | **~0.64s** | **181MB** | **47x (vs v0.3), 2.8x (vs v0.4)** |

user time (0.81s) > real time (0.64s) 確認多核心正在運作。

### 7.5 未來：Streaming Extract Pipeline

目前 `DocxReader.read()` 仍是 eager 全載：先解析完所有 body children，再交給 converter。
若要實現真正的 O(1) streaming（§4 描述的 queue size = 1），需要：

```
未來設計：
  DocxReader.stream(from:) → AsyncStream<BodyChild>
       ↓ (bounded buffer, k = 64)
  WordConverter: for await child in stream { emit(f(child)) }
```

這需要將 XML 解析改為 SAX-style（`XMLParser`）或將 DOM 遍歷包裝為 `AsyncSequence`。
目前 parallel chunked parse 已經足夠快，streaming 改造的優先級較低。

---

## 8. 對應表速查

| OOXML | 條件 | Markdown |
|-------|------|----------|
| `Paragraph` | style ∈ Heading{1-6} | `# ` ~ `###### ` |
| `Paragraph` | style = Title | `# ` |
| `Paragraph` | style = Subtitle | `## ` |
| `Paragraph` | numbering.numFmt = bullet | `- ` (支援巢狀 indent) |
| `Paragraph` | numbering.numFmt = decimal | `1. ` (支援巢狀 indent) |
| `Paragraph` | style ∈ Code/Source/Listing | ```` ``` ```` (fenced code block) |
| `Paragraph` | style ∈ Quote/Block Text | `> ` (blockquote) |
| `Paragraph` | hasPageBreak | `---` (horizontal rule) |
| `Paragraph` | otherwise | plain text + blank line |
| `Run` | bold = true | `**text**` |
| `Run` | italic = true | `_text_` |
| `Run` | bold ∧ italic | `***text***` |
| `Run` | strikethrough = true | `~~text~~` |
| `Run` | semantic = codeBlock | `` `text` `` (inline code) |
| `Run` | underline (HTML ext) | `<u>text</u>` |
| `Run` | superscript (HTML ext) | `<sup>text</sup>` |
| `Run` | subscript (HTML ext) | `<sub>text</sub>` |
| `Run` | highlight (HTML ext) | `<mark>text</mark>` |
| `Hyperlink` | external | `[text](url)` |
| `Hyperlink` | internal (bookmark) | `[text](#anchor)` |
| `Drawing` | inline/anchor image | `![alt](path)` |
| `Footnote` | reference + definition | `[^id]` + `[^id]: text` |
| `Endnote` | mapped to footnote | `[^enId]` + `[^enId]: text` |
| `Table` | — | pipe table |
| `TableCell` | contains `\|` | escape to `\|` |

---

## 9. 總結

### 我們反對 AST 的真正理由

> **不是討厭結構，而是討厭「假裝有中立結構」。**

通用 AST 假裝可以「先讀取、再決定」，但這會導致：
1. 資訊在非 injective 的投影中丟失
2. 後續轉換無法恢復

### 我們的設計選擇

1. **Target-aware Extraction**：在資訊完整時做決策
2. **Streaming = Lazy Map**：邊讀邊輸出，O(1) 記憶體
3. **f 是純函數**：只做格式化，不做決策

```
轉換決策前移 + Streaming 輸出 = 誠實且高效的文檔轉換
```

---

## 實作狀態

### 已實作映射（word-to-md-swift）

| OOXML | Markdown | 實作位置 |
|-------|----------|---------|
| `Hyperlink` (external) | `[text](url)` | `formatHyperlink` |
| `Hyperlink` (internal) | `[text](#anchor)` | `formatHyperlink` |
| `Image` / `Drawing` | `![alt](path)` | `formatDrawing` |
| `Footnote` | `[^1]` + definition | `emitFootnoteDefinitions` |
| `Endnote` | `[^en1]` (mapped to footnote) | `emitFootnoteDefinitions` |
| `Code` (style detection) | `` `code` `` | `formatRun` (semantic) |
| `CodeBlock` (style detection) | ```` ``` ```` | `processParagraph` |
| `Blockquote` (style detection) | `> ` | `processParagraph` |
| `PageBreak` | `---` | `processParagraph` |
| `Superscript` | `<sup>` (HTML ext) | `formatRun` |
| `Subscript` | `<sub>` (HTML ext) | `formatRun` |
| `Underline` | `<u>` (HTML ext) | `formatRun` |
| `Highlight` | `<mark>` (HTML ext) | `formatRun` |

### 並行化狀態

| 階段 | 實作 | 版本 |
|------|------|------|
| Parallel parseBody (chunked extract) | `DispatchQueue.concurrentPerform` | ooxml-swift v0.5.0 |
| Streaming extract (AsyncSequence) | 未實作 | — |
| Parallel f (多核 formatting) | 不需要（f < 1% 時間） | — |

完整的元素映射分類（含 Markdown 無法表達的部分）見 [`lossless-conversion.md`](lossless-conversion.md)。
