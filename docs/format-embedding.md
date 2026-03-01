# Format Information Embedding Theory

定義格式之間的資訊包含關係，以及為什麼 macdoc 選擇兩兩直接轉換。

---

## 1. 定義：Information Embedding

> 若存在轉換 f: A→B 和 g: B→A 使得 **g(f(a)) = a** 對所有 a ∈ A，
> 則稱 **A 的資訊可以 embed 在 B 中**，記作 **A ⊆ᵢ B**。

等價地：f 是 injection（單射）— A 的每個狀態在 B 中都有唯一的對應，不會 collapse。

**注意**：這裡的 `=` 可以是 byte-identical（嚴格）或 semantic-identical（寬鬆），
取決於應用需求。與 `lossless-conversion.md` 的 §0 保持一致時，使用 byte-identical。

---

## 2. 已知格式的 Embedding 關係

| 關係 | 成立？ | 理由 |
|------|:------:|------|
| MD ⊆ᵢ Word | ✅ | MD 的所有元素 Word 都能表達，MD→Word→MD 無損 |
| MD ⊆ᵢ HTML | ✅ | HTML 能表達 MD 的一切 |
| Word ⊆ᵢ HTML | ≈ | HTML+CSS 幾乎能表達 Word 的一切，但「頁」的概念需要 `@page` CSS |
| HTML ⊆ᵢ Word | ❌ | CSS class 語意、互動元素在 Word 中無對應 |
| Word ⊆ᵢ MD | ❌ | 顏色、分頁、批註在 MD 中無對應 |
| HTML ⊆ᵢ MD | ❌ | 同上更嚴重 |

偏序圖：

```
       HTML
      ↗    （Word ≈⊆ᵢ HTML，但不嚴格）
MD ⊆ᵢ Word
      （Word 和 HTML 互不完全包含）
```

MD 是最小的——幾乎可以 embed 在任何格式中。
Word 和 HTML 是各有獨特領域的大格式，交集很大但互不包含。

---

## 3. 對轉換架構的影響

### 3.1 Hub 模式的資訊瓶頸

如果選擇格式 H 做 hub：

```
A →ᶠ H →ᵍ B
```

那麼 A 中「不 embed 在 H 的部分」會在 A→H 階段不可逆地丟失。
即使 A→B 直接轉換本可以保留這些資訊。

**形式化**：
```
Loss(A →hub H → B) = (A \ A∩ᵢH)    — A 中不 embed 在 H 的部分全丟
Loss(A → B)        = (A \ A∩ᵢB)    — 只丟 A 中不 embed 在 B 的部分

若 A∩ᵢB > A∩ᵢH（A 和 B 的交集大於 A 和 hub 的交集），
則直接轉換嚴格優於經 hub。
```

**具體例子**：
- Hub = Markdown：Word→MD→HTML 丟失顏色、分頁、批註
- 直接轉換：Word→HTML 可以保留顏色（`<span style="color:...">`）、批註（`<!-- comment -->`）

### 3.2 直接轉換的資訊保真優勢

對任意格式對 (A, B)，直接轉換的損失 ≤ 經任何 hub 的損失：

```
∀ H:  Loss(A → B) ≤ Loss(A → H → B)
```

等號成立當且僅當 A ⊆ᵢ H（A 完全 embed 在 hub 中，hub 不造成額外損失）。

這就是為什麼 macdoc 選擇兩兩直接轉換——**不存在一個 hub 格式能同時無損承載所有格式的資訊**。

---

## 4. O(n²) 的可行性：AI 改變了等式

### 4.1 歷史背景

n 個格式之間的兩兩轉換需要 n(n-1) 個 converter（雙向）。

| 格式數 | Hub (Pandoc) | 兩兩直接 (macdoc) |
|--------|:------------:|:-----------------:|
| 3 | 4 | 6 |
| 5 | 8 | 20 |
| 10 | 18 | 90 |
| n | 2n | n(n-1) |

在 AI 之前，n(n-1) 個 converter 是不切實際的。
一個人或一個團隊寫不了 90 個轉換器，更別說維護。
Pandoc 的 hub 模式是**人力限制下的務實妥協**——犧牲保真度換取可維護性。

### 4.2 AI 如何改變等式

AI 改變了成本結構的兩端：

**成本下降**：
- 每個 converter 結構相同（實作 `DocumentConverter` protocol），差別在轉換邏輯
- AI 擅長「結構重複、細節不同」的工作——套 template 產出 converter 的邊際成本極低
- 4 層模組化架構讓每個 converter 是獨立 package，可平行開發

**品質不打折**：
- Hub 模式下 Word→HTML 經過 MD，顏色和版面全丟
- 直接轉換每一對都能保留最多資訊
- O(n²) 的複雜度換來的是每條路徑的最優保真度

### 4.3 本質

> **macdoc 的哲學是：用 AI 的生產力換取轉換品質。**
>
> 以前因為人力限制而不得不做的妥協（hub），現在可以消除。
> n(n-1) 個 converter 在 AI 時代不再荒謬——它是正確的架構選擇。

---

## 5. 與其他文檔的關係

| 文檔 | 關聯 |
|------|------|
| `lossless-conversion.md` | §0 的 bijection 定義是 embedding 的特例（A ⊆ᵢ A，自身 embedding） |
| `philosophy.md` | 「為什麼不用 Hub Format」段落的理論基礎 |
| `functional-correspondence.md` | 元素對應表是 embedding 分析的實例化 |
| `modular-architecture.md` | Layer 3 的 converter 數量 = n(n-1) 的實體化 |
