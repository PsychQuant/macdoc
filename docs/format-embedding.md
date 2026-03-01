# Format Information Embedding Theory

用 model theory 的框架定義格式之間的資訊包含關係，以及為什麼 macdoc 選擇兩兩直接轉換。

---

## 1. 格式即結構 (Format as Structure)

### 1.1 Signature：格式能表達什麼

每個文件格式定義一個 **signature**（簽名）σ，包含：

- **Sorts**（類型）：格式支援的元素類型
- **Relations**（關係）：元素上的布林屬性
- **Functions**（函數）：元素上的值屬性

```
σ_Word = {
  sorts:     { Text, Heading, Image, Table, Comment, Footnote, PageBreak, ... }
  relations: { bold ⊆ Text, italic ⊆ Text, underline ⊆ Text, strikethrough ⊆ Text, ... }
  functions: { color: Text → RGB, fontSize: Text → HalfPt, font: Text → String,
               level: Heading → {1..6}, src: Image → Bytes, width: Image → EMU, ... }
}

σ_MD = {
  sorts:     { Text, Heading, Image, Table, CodeBlock, Link, ... }
  relations: { bold ⊆ Text, italic ⊆ Text, strikethrough ⊆ Text }
  functions: { level: Heading → {1..6}, src: Image → Path, alt: Image → String }
}

σ_HTML = {
  sorts:     { Text, Heading, Image, Table, Link, Form, Audio, Video, SemanticTag, ... }
  relations: { bold ⊆ Text, italic ⊆ Text, underline ⊆ Text, strikethrough ⊆ Text, ... }
  functions: { color: Text → RGB, fontSize: Text → CSSUnit, font: Text → String,
               class: Text → String, level: Heading → {1..6},
               src: Image → URL, width: Image → CSSUnit, ... }
}

σ_PlainText = {
  sorts:     { Text }
  relations: { }
  functions: { }
}
```

### 1.2 Structure：一份具體的文件

一份具體的文件是 signature 上的一個 **structure**（結構）M：
- 一個 universe（元素集合）
- 對每個 sort 的解釋（哪些元素屬於哪個 sort）
- 對每個 relation/function 的解釋（具體的值）

例如一份 Word 文件 M_Word：
```
universe = { e₁, e₂, e₃, e₄ }
Text = { e₁, e₂ }
Heading = { e₃ }
Image = { e₄ }
bold = { e₁ }              — e₁ 是粗體
italic = { }               — 沒有斜體元素
color(e₁) = #FF0000        — e₁ 是紅色
color(e₂) = #000000        — e₂ 是黑色
level(e₃) = 1              — e₃ 是 H1
src(e₄) = <bytes>          — e₄ 的圖片資料
```

---

## 2. Homomorphism：什麼是「合法的轉換」

### 2.1 定義

函數 f: A → B 是 **homomorphism**（同態射），若它保持結構：

```
對每個 sort S：     a ∈ S^A  ⟹  f(a) ∈ S^B          — sort 對 sort
對每個 relation R： R^A(a)   ⟹  R^B(f(a))            — 關係保持
對每個 function g： f(g^A(a)) = g^B(f(a))             — 函數交換
```

**這就是為什麼 base64 encode 圖片到純文字不是合法轉換**：

```
圖片 e ∈ Image^A
f(e) = "iVBORw0KGgo..." ∈ Text^B    ← sort 不對！Image 映射到了 Text

違反 homomorphism 的第一條：a ∈ Image^A 但 f(a) ∉ Image^B
（σ_PlainText 根本沒有 Image sort）
```

Homomorphism 要求 **sort 對 sort**——不需要額外定義「相同語意」，signature 本身就是語意的定義。

### 2.2 不同強度的映射

| 概念 | 定義 | 文件轉換的意義 |
|------|------|----------------|
| **Homomorphism** | 保持結構（可以多對一） | 有損但合法的轉換 |
| **Embedding** | injective homomorphism | 不失真轉換 |
| **Isomorphism** | bijective embedding | 兩個格式完全等價 |

### 2.3 有損 Homomorphism 的資訊丟失

如果 f 是 homomorphism 但不是 embedding（不是 injective），那麼存在 collapse：

```
Word→MD 的 homomorphism:

  e₁: bold, color=#FF0000  ──f──→  e₁': bold
  e₂: bold, color=#0000FF  ──f──→  e₂': bold      ← collapse！兩個不同元素映射到相同結果

σ_MD 沒有 color function，所以 f 無法保留顏色差異。
f 仍然是 homomorphism（bold 被保持了），但不是 embedding。
```

---

## 3. Interpretation：跨格式的元素對應

### 3.1 Theory Interpretation

Model theory 的 **interpretation**（詮釋）精確定義了如何用一個格式的語言「說出」另一個格式的概念。

**T₁ 可以 interpret 在 T₂ 中** iff T₁ 的所有 sorts、relations、functions 都可以用 T₂ 的 formulas 定義。

```
interpret σ_MD in σ_Word:
  MD.Text(x)            ≜  Word.Text(x)
  MD.Heading(x)         ≜  Word.Heading(x)
  MD.Image(x)           ≜  Word.Image(x)
  MD.bold(x)            ≜  Word.bold(x)
  MD.italic(x)          ≜  Word.italic(x)
  MD.strikethrough(x)   ≜  Word.strikethrough(x)
  MD.level(x)           ≜  Word.level(x)
  MD.src(x)             ≜  extractPath(Word.src(x))

✅ 所有 σ_MD 的符號都能用 σ_Word 的 formulas 定義 → MD 可以 interpret 在 Word 中
```

```
interpret σ_Word in σ_MD:
  Word.Text(x)          ≜  MD.Text(x)
  Word.bold(x)          ≜  MD.bold(x)
  Word.color(x)         ≜  ???                     ← σ_MD 沒有 color 相關的 formula
  Word.underline(x)     ≜  ???                     ← σ_MD 沒有 underline
  Word.Comment(x)       ≜  ???                     ← σ_MD 沒有 Comment sort

❌ 無法完成 → Word 不能 interpret 在 MD 中
```

### 3.2 Interpretation 就是 functional-correspondence.md

`functional-correspondence.md` 中的元素對應表就是 interpretation 的具體實例：

| σ_Word 符號 | σ_MD 中的 formula | 可定義？ |
|-------------|-------------------|:--------:|
| bold(x) | `**text**` | ✅ |
| italic(x) | `_text_` | ✅ |
| color(x) = c | — | ❌ |
| Heading(x), level(x) = n | `#` × n | ✅ |
| Comment(x) | — | ❌ |
| Image(x), src(x) | `![alt](path)` | ✅ |

**Interpretation 存在 ⟺ embedding 存在。** 這是 model theory 的基本結果。

---

## 4. 定義：Format Embedding

綜合以上，給出 embedding 的正式定義：

> **A ⊆ᵢ B**（A 的資訊可以 embed 在 B 中）iff
> Theory(A) 可以 interpret 在 Theory(B) 中。
>
> 等價條件：
> 1. 存在 injective homomorphism f: A → B
> 2. σ_A 的所有 sorts/relations/functions 都可以用 σ_B 的 formulas 定義
> 3. 存在 g: B → A 使得 g ∘ f = id_A（round-trip 不失真）

三個條件等價。第 3 個是最初的直覺定義，但第 1、2 個排除了 base64 之類的 trick——
因為 homomorphism 和 interpretation 都要求 **結構保持**，不允許跨 sort 的任意編碼。

---

## 5. 已知格式的 Embedding 關係

| 關係 | 成立？ | 理由（interpretation 視角） |
|------|:------:|------|
| MD ⊆ᵢ Word | ✅ | σ_MD 的每個符號在 σ_Word 中都有直接對應 |
| MD ⊆ᵢ HTML | ✅ | 同上 |
| Word ⊆ᵢ HTML | ≈ | 大部分可 interpret（color→CSS, bold→`<b>`），但 PageBreak 需要 `@page` CSS |
| HTML ⊆ᵢ Word | ❌ | SemanticTag、Form、Audio/Video 在 σ_Word 中不可定義 |
| Word ⊆ᵢ MD | ❌ | color、underline、Comment 在 σ_MD 中不可定義 |
| HTML ⊆ᵢ MD | ❌ | 同上更嚴重 |

偏序圖：

```
             HTML
           ↗     （Word ≈⊆ᵢ HTML，大部分成立）
PlainText ⊆ᵢ MD ⊆ᵢ Word
                     （Word 和 HTML 互不完全包含，交集很大）
```

---

## 6. 對轉換架構的影響

### 6.1 Hub 模式的資訊瓶頸

如果選擇格式 H 做 hub，轉換路徑 A → H → B：

```
f: A → H   （homomorphism，可能有損）
g: H → B   （homomorphism）
```

A 中不可 interpret 在 σ_H 中的符號，在 f 階段就不可逆地丟失了。
即使 σ_B 能表達這些符號，g 也無法恢復 f 丟掉的資訊。

**形式化**：

```
可保留的符號集合：
  直接轉換 A → B：  σ_A ∩ σ_B           — A 和 B 共有的符號
  經 hub A → H → B：σ_A ∩ σ_H ∩ σ_B    — 三者共有的符號

因為 (σ_A ∩ σ_H ∩ σ_B) ⊆ (σ_A ∩ σ_B)，
經 hub 的資訊保留永遠 ≤ 直接轉換。
```

**具體例子**：

```
σ_Word ∩ σ_HTML = { Text, Heading, Image, Table, bold, italic, underline,
                    color, fontSize, font, ... }                        — 交集很大

σ_Word ∩ σ_MD   = { Text, Heading, Image, Table, bold, italic,
                    strikethrough, level, src }                         — 交集小得多

Word→HTML 直接轉換保留 color、underline、font 等
Word→MD→HTML 丟失 color、underline、font（σ_MD 沒有這些符號）
```

### 6.2 定理：直接轉換最優

> 對任意格式 A, B 和任意 hub H：
>
> **Loss(A → B) ≤ Loss(A → H → B)**
>
> 等號成立 iff A ⊆ᵢ H（A 完全 embed 在 hub 中）。

**不存在一個 hub 格式能同時滿足所有格式對的等號條件**——
因為不存在一個 σ_H 同時是所有 σ 的 superset（格式們互不包含）。

這就是為什麼 macdoc 選擇兩兩直接轉換。

---

## 7. O(n²) 的可行性：AI 改變了等式

### 7.1 歷史背景

n 個格式之間的兩兩轉換需要 n(n-1) 個 converter（雙向）。

| 格式數 | Hub (2n) | 兩兩直接 (n(n-1)) |
|--------|:--------:|:-----------------:|
| 3 | 4 | 6 |
| 5 | 8 | 20 |
| 10 | 18 | 90 |

在 AI 之前，n(n-1) 個 converter 是不切實際的。
Pandoc 的 hub 模式是**人力限制下的務實妥協**——犧牲保真度換取可維護性。

### 7.2 AI 改變了成本結構

| | Hub 時代（人力限制） | 直接轉換時代（AI 輔助） |
|---|---|---|
| **Converter 數量** | 2n（可管理） | n(n-1)（以前不可管理） |
| **每個 converter 的開發成本** | 高（人工逐行寫） | 低（結構相同，AI 套 template） |
| **每條路徑的保真度** | ≤ hub 的表達能力 | = 格式對的最大交集 |
| **總開發成本** | 2n × 高 | n(n-1) × 低 |
| **總保真度** | 受 hub 限制 | 最優 |

### 7.3 本質

> **macdoc 的哲學是：用 AI 的生產力換取轉換品質。**
>
> n(n-1) 個 converter 在 AI 時代不再荒謬——它是**定理 6.2 的正確實現**。
> 以前因為人力限制而不得不做的妥協（hub），現在可以消除。

---

## 8. 與其他文檔的關係

| 文檔 | 關聯 |
|------|------|
| `lossless-conversion.md` | §0 的 bijection = embedding 的特例（A ⊆ᵢ A + metadata = isomorphism） |
| `philosophy.md` | 「為什麼不用 Hub Format」段落的理論基礎 |
| `functional-correspondence.md` | 即 §3 的 interpretation 實例——跨格式的符號對應表 |
| `modular-architecture.md` | Layer 3 的 converter 數量 = n(n-1) 的實體化 |
