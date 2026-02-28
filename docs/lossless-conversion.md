# Lossless Conversion Protocol

完全不失真的文件格式轉換——理論基礎與分層設計。

> **Marker format** = Markdown + Figures + Metadata
>
> 這個 pattern 源自 [Marker](https://github.com/datalab-to/marker)。
>
> 在 Marker 之前，文件轉換工具（Pandoc、pdftotext、Apache Tika）關注的都是
> 「如何轉換」——把 A 格式變成 B 格式，接受資訊損失是理所當然的代價。
> Marker 是第一個把「不失真」當作設計目標的專案。它的三通道輸出
> （Markdown + Figures + Metadata）不只是一種輸出格式，
> 而是一種思維方式：**轉換不應該丟資訊，丟資訊應該是使用者的選擇，不是工具的限制。**
>
> 我們沿用 **Marker** 這個名稱來指稱完整的不失真輸出格式（Tier 3），
> 致敬這個轉檔領域最重要的 paradigm shift。

---

## 1. 問題陳述

### 1.1 Markdown 的表達能力缺口

Markdown 是一個有限的標記語言。以 Word (OOXML) 為例：

```
Word 能表達的資訊集合:  W = {heading, paragraph, bold, italic, underline,
                            color, font, alignment, spacing, images,
                            comments, footnotes, bookmarks, ...}

Markdown 能表達的集合:  M = {heading, paragraph, bold, italic,
                            strikethrough, link, image, code, table, ...}

差集（Markdown 無法表達）: W \ M = {underline, color, font, alignment,
                                    spacing, comments, bookmarks, ...}
```

標準的 Word→Markdown 轉換是一個 **surjection**（滿射）到 M，但不是 **injection**（單射）：

```
convert: W → M

∃ w₁, w₂ ∈ W:  w₁ ≠ w₂  ∧  convert(w₁) = convert(w₂)
```

例如：紅色粗體文字和藍色粗體文字，轉成 Markdown 都是 `**text**`——**collapse 發生了**。

### 1.2 不失真的數學定義

> **定義**：轉換 `convert` 是「完全不失真」的，若且唯若 `convert` 是 **injective**（單射）。
>
> ```
> ∀ w₁, w₂ ∈ W:  convert(w₁) = convert(w₂)  ⟹  w₁ = w₂
> ```

等價地：**不同的輸入永遠產生不同的輸出**。沒有 collapse，沒有資訊損失。

這正是 **bijection**（雙射，在值域上）——轉換函數在其值域上是一一對應的。

---

## 2. 解法：擴展值域

### 2.1 核心觀察

`convert: W → M` 不可能是 injective（因為 |W| >> |M|）。

但如果我們擴展輸出的值域：

```
convert: W → M × F × Meta
```

其中：
- **M** = Markdown 文字
- **F** = Figures（提取的圖片檔案集合）
- **Meta** = Metadata（Markdown 無法表達的所有資訊）

只要 `Meta` 記錄了所有 `M × F` 無法區分的差異，`convert` 就是 injective。

### 2.2 Metadata 作為 Kernel 的補

用線性代數的直覺：

```
W ──convert──→ M × F × Meta
     │              │
     └── π_M ──→    M        (投影到 Markdown，lossy)
     └── π_F ──→    F        (投影到 Figures，部分資訊)
     └── π_Meta ──→ Meta     (捕捉所有被 π_M, π_F collapse 的資訊)
```

`Meta` 的職責是精確補完 `M × F` 的「盲區」。**如果兩份 Word 文件產生相同的 (M, F)，它們在 Meta 中一定不同。**

---

## 3. Fidelity Tiers（保真度層級）

使用者不一定需要完全不失真。提供三個層級，讓使用者選擇：

### 3.1 三個層級

| Tier | 名稱 | 輸出 | Injective? | 適用場景 |
|------|------|------|-----------|---------|
| **Tier 1** | **Markdown** | M | 否（lossy） | 快速預覽、終端顯示、純文字場景 |
| **Tier 2** | **Markdown + Figures** | M × F | 否（less lossy） | 文件、部落格、知識庫匯入 |
| **Tier 3** | **Marker** | M × F × Meta | **是（lossless）** | 歸檔、資料遷移、學術保存 |

### 3.2 形式化

```
Tier 1:  convert₁(w) = π_M(convert(w))         -- 只取 Markdown
Tier 2:  convert₂(w) = π_{M×F}(convert(w))     -- 取 Markdown + Figures
Tier 3:  convert₃(w) = convert(w)              -- 完整輸出（bijective）
```

**只有 Marker（Tier 3）是 injective 的。** Tier 1 和 Tier 2 是刻意選擇丟棄部分資訊——使用者知情的有損壓縮。

### 3.3 設計原則：Marker 驅動設計，Tier 1/2 是投影

```
設計時：  永遠按 Marker（Tier 3）的標準思考（每個元素的完整資訊在哪裡？）
實作時：  Tier 1/2 只是對 Marker 做投影（省略 F 或 Meta 的部分）
```

這確保：
1. 即使只用 Tier 1，設計上也已考慮到完整資訊，未來升級不需重構
2. Tier 間的切換只是「包含/排除」某些輸出通道，邏輯不變

---

## 4. 資訊分類

將所有 OOXML 元素按「Markdown 能否原生表達」分為三類：

### 4.1 Layer A — Markdown 原生表達（Tier 1 可用）

這些元素有直接的 Markdown 對應，不需要額外管道。

| OOXML 元素 | Markdown 映射 | 狀態 |
|-----------|-------------|------|
| Heading (style) | `# ` ~ `###### ` | ✅ 已實作 |
| Paragraph | plain text | ✅ 已實作 |
| Bold | `**text**` | ✅ 已實作 |
| Italic | `*text*` | ✅ 已實作 |
| Strikethrough | `~~text~~` | ✅ 已實作 |
| Bullet list | `- item` | ✅ 已實作 |
| Numbered list | `1. item` | ✅ 已實作 |
| Table | pipe table | ✅ 已實作 |
| Hyperlink (external) | `[text](url)` | TODO |
| Hyperlink (internal) | `[text](#anchor)` | TODO |
| Image (inline) | `![alt](path)` | TODO (Tier 2+) |
| Footnote | `[^id]: text` | TODO |
| Endnote | `[^id]: text` (同 footnote 語法) | TODO |
| Code (style-based) | `` `code` `` | TODO |
| Code block (style-based) | ```` ``` ```` | TODO |
| Blockquote (style-based) | `> text` | TODO |
| Horizontal rule | `---` | TODO |

### 4.2 Layer B — HTML 擴展表達（Tier 1 可選啟用）

Markdown 不能原生表達，但可透過內嵌 HTML 近似表達。

| OOXML 元素 | HTML 擴展 | 說明 |
|-----------|----------|------|
| Underline | `<u>text</u>` | 7 種 underline 類型在 HTML 中只能表達「有/無」 |
| Superscript | `<sup>text</sup>` | |
| Subscript | `<sub>text</sub>` | |
| Highlight | `<mark>text</mark>` | 顏色資訊丟失（16 色→無色） |
| Line break | `<br>` | 段落內換行 |
| Caption | `<figcaption>` | 圖片/表格說明 |

**注意**：Layer B 是 Tier 1 的可選擴展。啟用後 Markdown 可讀性會下降，但資訊保留更多。仍然不是 injective（例如 underline 的 7 種子類型都 collapse 為 `<u>`）。

### 4.3 Layer C — Metadata 專屬（Marker / Tier 3 限定）

只能透過 Metadata 管道保存的資訊。這些是讓 `convert` 成為 injection 的關鍵。

#### 文件層級

| 資訊 | 說明 |
|------|------|
| Document properties | title, creator, subject, description, keywords, category, lastModifiedBy, created, modified, revision |
| Style definitions | 完整的 style 樹（id, name, basedOn, properties） |
| Numbering definitions | abstractNums, levels, formats |
| Section properties | 頁面大小、方向、邊距 |
| Headers / Footers | 頁首頁尾內容（按 section） |
| Default fonts | 文件預設字體設定 |

#### 段落層級

| 資訊 | 說明 |
|------|------|
| Alignment | left, center, right, justify, distribute |
| Spacing | before, after, line spacing (exact values) |
| Indentation | left, right, firstLine, hanging |
| Keep with next | 分頁控制 |
| Keep lines together | 分頁控制 |
| Page break before | 分頁控制 |
| Paragraph border | 框線（style, color, size） |
| Paragraph shading | 底色 |
| Bookmark references | 書籤位置 |
| Comment anchors | 註解附著位置 |

#### Run（文字片段）層級

| 資訊 | 說明 |
|------|------|
| Font name | 字體名稱 |
| Font size | 字體大小（half-points） |
| Text color | RGB 色彩值 |
| Highlight color | 16 種預設螢光筆色 |
| Underline type | single, double, dotted, dashed, wave, thick, dash-long |
| Character spacing | 字元間距 |
| Text effect | 文字動畫效果 |
| Vertical align | superscript, subscript, baseline |

#### 附屬物件

| 資訊 | 說明 |
|------|------|
| Comments | id, author, date, text, initials, replies, done |
| Images (positioning) | inline/anchor, width/height (EMU), wrap style, position |
| Image effects | border, shadow |
| Hyperlink tooltip | 連結的 tooltip 文字 |
| Bookmark range | start/end 位置 |
| Revision tracking | 所有修訂記錄 |

---

## 5. Metadata 格式

### 5.1 設計約束

1. **Streaming 兼容**：metadata 必須能在 streaming 模式中產生（邊讀邊寫）
2. **人類可讀**：以文字格式存儲，不是 binary
3. **結構化**：可程式解析，支援工具處理
4. **與 Markdown 分離**：不污染 Markdown 的可讀性

### 5.2 輸出結構

```
output/
├── document.md              # Tier 1: Pure Markdown
├── figures/                 # Tier 2: 提取的圖片
│   ├── image1.png
│   ├── image2.jpeg
│   └── ...
└── document.meta.yaml       # Tier 3: Metadata sidecar
```

**Tier 1 (Markdown)** 只產生 `document.md`。
**Tier 2 (Markdown + Figures)** 產生 `document.md` + `figures/`。
**Tier 3 (Marker)** 產生全部三者——這就是完整的 Marker format。

### 5.3 Metadata Sidecar 結構

```yaml
# document.meta.yaml
version: "1.0"
source:
  format: "docx"
  file: "original.docx"

document:
  properties:
    title: "..."
    creator: "..."
    # ... 完整的 document properties

  styles:
    - id: "Heading1"
      name: "heading 1"
      basedOn: "Normal"
      properties: { ... }
    # ...

  numbering:
    abstractNums: [...]
    nums: [...]

  sections:
    - pageSize: { width: 12240, height: 15840 }
      orientation: portrait
      margins: { top: 1440, bottom: 1440, left: 1800, right: 1800 }
      header: { ... }
      footer: { ... }

paragraphs:
  - index: 0
    # 只記錄 Markdown 無法表達的屬性
    alignment: center
    spacing: { before: 240, after: 120 }
    runs:
      - range: [0, 5]          # 對應 Markdown 中的字元位置
        font: "Times New Roman"
        fontSize: 24
        color: "#FF0000"
      - range: [5, 10]
        font: "Arial"
        fontSize: 12

  - index: 3
    comments:
      - id: 1
        author: "John"
        date: "2026-01-15T10:30:00Z"
        text: "需要修改這段"
        range: [0, 8]          # Markdown 中的字元位置
        replies:
          - author: "Jane"
            date: "2026-01-15T11:00:00Z"
            text: "已修改"
        done: true

figures:
  - id: "image1"
    file: "figures/image1.png"
    contentType: "image/png"
    placement: anchor           # inline | anchor
    width: 5486400              # EMU
    height: 3657600             # EMU
    position:
      horizontal: { relative: column, align: center }
      vertical: { relative: paragraph, offset: 0 }
    altText: "圖片描述"
    border: { style: single, color: "#000000", width: 1 }
```

### 5.4 Sparse Metadata 原則

> **只記錄 Markdown 無法表達的屬性。**

如果某個資訊已經在 Markdown 中表達了（如 heading level、bold、italic），metadata 不重複記錄。Metadata 是 Markdown 的**補集**，不是**全集**。

```
Meta = W \ M_expressible

而非：
Meta = W     ← 錯誤：這會導致資訊重複
```

這保持 metadata 簡潔，也避免了 Markdown 和 metadata 之間的不一致問題。

---

## 6. 與既有架構的整合

### 6.1 對 Functional Correspondence 的擴展

原始公式：
```
convert(A) = map(f, extract_{A→T}(A))
```

擴展為三通道公式：
```
convert(A) = (
    map(f_md,   extract_{A→MD}(A)),     -- Markdown 通道
    map(f_fig,  extract_{A→Fig}(A)),    -- Figures 通道
    map(f_meta, extract_{A→Meta}(A))    -- Metadata 通道
)
```

三個 extract 共享同一次 source 遍歷（streaming），但各自投影不同的資訊。

### 6.2 Streaming 兼容性

```
for element in source.elements:
    // 三個通道同步 streaming
    emit_md(f_md(element))        // Tier 1: 總是執行
    emit_fig(f_fig(element))      // Tier 2+: 有圖片時執行
    emit_meta(f_meta(element))    // Tier 3: 有 metadata 時執行
```

**Queue size 仍然是 O(1)**——每個元素只被處理一次，三個通道平行輸出。

### 6.3 對 ConversionOptions 的影響

```swift
// doc-converter-swift: ConversionOptions 擴展

public enum FidelityTier: Sendable {
    case markdown           // Tier 1: 純 Markdown
    case markdownWithFigures // Tier 2: + 圖片提取
    case marker             // Tier 3: Marker format（MD + Figures + Meta, bijective）
}

public struct ConversionOptions: Sendable {
    // 既有選項
    public var includeFrontmatter: Bool
    public var hardLineBreaks: Bool
    public var tableStyle: TableStyle
    public var headingStyle: HeadingStyle

    // 新增：保真度層級
    public var fidelity: FidelityTier

    // Tier 1 可選：是否啟用 HTML 擴展（Layer B）
    public var useHTMLExtensions: Bool

    // Tier 2+：圖片輸出目錄
    public var figuresDirectory: URL?

    // Tier 3：metadata 輸出路徑
    public var metadataOutput: URL?
}
```

### 6.4 對 DocumentConverter Protocol 的影響

Protocol 本身不需要修改——`StreamingOutput` 已經足夠處理 Markdown 輸出。Figures 和 Metadata 是獨立的輸出通道，由 converter 內部根據 `ConversionOptions.fidelity` 決定是否啟用。

```swift
// word-to-md-swift: WordConverter 內部

func convert<W: StreamingOutput>(
    document: WordDocument,
    output: inout W,
    options: ConversionOptions
) throws {
    for child in document.body.children {
        // Markdown 通道（永遠執行）
        try emitMarkdown(child, output: &output, options: options)

        // Figures 通道（Tier 2+）
        if options.fidelity >= .markdownWithFigures {
            try extractFigures(child, directory: options.figuresDirectory)
        }

        // Metadata 通道（Marker）
        if options.fidelity == .marker {
            try collectMetadata(child)
        }
    }

    // Marker: streaming 結束後寫出 metadata sidecar
    if options.fidelity == .marker {
        try writeMetadata(to: options.metadataOutput)
    }
}
```

---

## 7. Bijection 的驗證策略

不實作逆向轉換器（MD+Meta→Word），但需要驗證 injective 性質。

### 7.1 Property-Based Testing

```
∀ w ∈ W_test:
    let (md, fig, meta) = convert₃(w)
    assert: meta 包含 w 中所有不在 md 裡的屬性
```

### 7.2 Differential Testing

```
∀ w₁, w₂ ∈ W_test:
    if w₁ ≠ w₂:
        assert: convert₃(w₁) ≠ convert₃(w₂)
```

如果兩份不同的 Word 文件產生了完全相同的 (md, fig, meta)，就是 bug。

### 7.3 Coverage Checklist

為每個 OOXML 元素維護一個 checklist：

| 元素 | Markdown 表達？ | HTML 擴展？ | Metadata？ | 測試？ |
|------|:-------------:|:---------:|:---------:|:-----:|
| heading | ✅ | — | — | |
| bold | ✅ | — | — | |
| underline | — | ✅ | ✅ (子類型) | |
| color | — | — | ✅ | |
| comment | — | — | ✅ | |
| ... | | | | |

**目標**：每個元素至少在一個通道中被保存。Marker（Tier 3）的合集必須覆蓋 100% 的元素。

---

## 8. 總結

### 核心設計

```
不失真 = bijection = injection on 值域
Markdown 本身無法 injection（表達能力不足）
擴展值域: M × F × Meta 使 injection 成為可能
```

### Fidelity Tiers

```
Tier 1 (Markdown):            W → M              快速、有損、可讀
Tier 2 (Markdown + Figures):  W → M × F          含圖、有損、實用
Tier 3 (Marker):              W → M × F × Meta   完整、無損、bijective
```

### 設計原則

1. **Marker 驅動設計** — 所有元素都必須有去處（M 或 Meta）
2. **Sparse Metadata** — 只記錄 Markdown 無法表達的部分
3. **Streaming 兼容** — 三通道平行輸出，O(1) 記憶體
4. **使用者選擇** — 有損是刻意的選擇，不是設計缺陷
