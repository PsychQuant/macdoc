# Formal Information Theory

用 model theory 的框架定義**結構化資訊**——不同於 Shannon 的量化資訊理論，
本框架刻畫資訊的**結構**（什麼種類的資訊被保留或丟失），而非僅僅資訊的**量**（多少 bits）。

適用於**所有結構化資料的轉換**：文件格式（Word、Markdown、HTML）、資料庫遷移（PostgreSQL → MySQL）、
圖片轉檔（PNG → JPG）、音訊轉碼（WAV → MP3）、序列化格式（JSON → CSV）——
任何有 signature 的資料之間的轉換，都服從同一套定理。

macdoc 是本理論的第一個應用場景：定義格式之間的資訊包含關係，以及為什麼選擇兩兩直接轉換。

---

## 0. 數學背景：從抽象代數到 Model Theory

本文的理論基礎不是新發明——它是 19 世紀以來代數學的直接應用。

### 0.1 推廣脈絡

抽象代數研究特定的代數結構（group 有一個運算，ring 有兩個，field 加上除法⋯）和它們之間的 **homomorphism**（結構保持映射）。Model theory 把這個推廣到**任意 signature**——不限於特定運算，你可以定義任意的 sorts、relations、functions。

```
抽象代數                     Model Theory                 本文的應用
(固定結構)                   (任意 signature)              (資料轉換)
────────────                ─────────────                ──────────

Group (G, ·)                Structure (M, σ)             Word Document (M, σ_Word)
Ring (R, +, ·)              — σ 可以是任意符號集合 —       MD Document (M, σ_MD)
Field (F, +, ·, ⁻¹)                                     HTML Document (M, σ_HTML)

Group homo:                 Homomorphism:                Format conversion:
  f(a·b) = f(a)·f(b)         sort → sort                  Image → Image
                              R(a) ⟹ R(f(a))              bold(a) ⟹ bold(f(a))
                              f(g(a)) = g(f(a))            f(color(a)) = color(f(a))

Subgroup H ≤ G              Substructure A ⊆ B           MD ⊆ᵢ Word
Injective homo              Embedding                    Lossless conversion
Isomorphism                 Isomorphism                  Format equivalence
Quotient G/N                A / ker(f) ≅ Im(f)           Lossy conversion 的 kernel
```

### 0.2 為什麼這個框架適合所有結構化資料

任何有結構的資料都天然具有代數結構：
- **Sorts** = 元素類型（文件的 Text/Heading/Image、資料庫的 Table、圖片的 Pixel/Layer）
- **Relations** = 布林屬性（bold、NOT NULL、hasAlpha）
- **Functions** = 值屬性（color、column value、amplitude）

把資料格式定義為 model theory 的 structure 後，所有代數定理自動適用：

| 代數定理 | 在資料轉換中的意義 |
|---------|-------------------|
| **第一同構定理** A/ker(f) ≅ Im(f) | 轉換的 collapse 可以用 kernel **逐項命名**（不是「丟了 47 bits」，而是「丟了顏色、字體、批註」） |
| **Embedding 構成偏序** | 格式之間的 ⊆ᵢ 關係是偏序（自反、反對稱、遞移） |
| **子結構保持性質** | 經中間格式轉換 = 先投影到子結構再嵌入，資訊 ≤ 直接轉換 |

本文不是發明新理論，而是把成熟的數學工具應用到資料轉換這個 domain。
公理只有三條：資料 = structure，轉換 = homomorphism，損失 = kernel。所有定理由此推出。

---

## 1. 資料格式即結構 (Data Format as Structure)

### 1.1 Signature：格式能表達什麼

每個資料格式定義一個 **signature**（簽名）σ，包含：

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

**同樣的框架適用於所有結構化資料**：

```
σ_PostgreSQL = {
  sorts:     { Row, Table, View, Index, Trigger, Sequence, ... }
  relations: { NOT_NULL ⊆ Column, UNIQUE ⊆ Column, PRIMARY_KEY ⊆ Column, ... }
  functions: { datatype: Column → Type, default: Column → Expr,
               foreign_key: Column → (Table, Column), ... }
}

σ_CSV = {
  sorts:     { Row, Column }
  relations: { }
  functions: { value: (Row, Column) → String }
}

σ_PNG = {
  sorts:     { Pixel, Layer, Metadata }
  relations: { hasAlpha ⊆ Pixel }
  functions: { color: Pixel → RGBA, position: Pixel → (x, y),
               bitDepth: Layer → {8,16}, ... }
}

σ_JPG = {
  sorts:     { Pixel, Metadata }
  relations: { }                               — 沒有 alpha！
  functions: { color: Pixel → RGB, position: Pixel → (x, y),
               quality: Image → {1..100} }
}

σ_MIDI = {
  sorts:     { Note, Track, Instrument, ControlChange, Tempo, TimeSignature }
  relations: { }
  functions: { pitch: Note → {0..127}, velocity: Note → {0..127},
               duration: Note → Ticks, channel: Note → {0..15},
               instrument: Track → GM_Program, tempo: Tempo → BPM }
}

σ_MP3 = {
  sorts:     { Sample, Frame, Channel, Metadata }
  relations: { }
  functions: { amplitude: Sample → Float, time: Sample → Sec,
               spectral: Frame → Coefficients,
               sampleRate: Metadata → Hz, bitRate: Metadata → kbps }
}

σ_WAV = {
  sorts:     { Sample, Channel, Metadata }
  relations: { }
  functions: { amplitude: Sample → Float, time: Sample → Sec,
               sampleRate: Metadata → Hz, bitDepth: Metadata → Int }
}

σ_JSON = {
  sorts:     { Object, Array, String, Number, Boolean, Null }
  relations: { }
  functions: { key: (Object, String) → Value, index: (Array, Int) → Value }
}
```

**ker(f) 在每個領域都有具體語意**：

| 轉換 | ker(f) | 日常說法 |
|------|--------|---------|
| Word → MD | {color, fontSize, underline, comment, ...} | 「格式丟了」 |
| PostgreSQL → CSV | {foreign_key, index, trigger, view, datatype, ...} | 「schema 沒了」 |
| PNG → JPG | {hasAlpha, bitDepth=16, lossless} | 「透明背景沒了」 |
| WAV → MP3 | {high_freq_samples, phase_precision} | 「音質變差了」 |
| MIDI → MP3 | ∅（固定 synthesizer 下，見 §6） | 「embedding，無損失」 |
| MP3 → MIDI | {timbre, room_acoustics, phase, non-musical_sound, ...} | 「只能 AI 猜音符」 |
| JSON → CSV | {Object_nesting, Array, mixed_types, Null} | 「巢狀結構攤平了」 |

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

### 5.1 同層格式（同一抽象層級）

| 關係 | 成立？ | 理由（interpretation 視角） |
|------|:------:|------|
| MD ⊆ᵢ Word | ✅ | σ_MD 的每個符號在 σ_Word 中都有直接對應 |
| MD ⊆ᵢ HTML | ✅ | 同上 |
| Word ⊆ᵢ HTML | ≈ | 大部分可 interpret（color→CSS, bold→`<b>`），但 PageBreak 需要 `@page` CSS |
| HTML ⊆ᵢ Word | ❌ | SemanticTag、Form、Audio/Video 在 σ_Word 中不可定義 |
| Word ⊆ᵢ MD | ❌ | color、underline、Comment 在 σ_MD 中不可定義 |
| HTML ⊆ᵢ MD | ❌ | 同上更嚴重 |
| JSON ≅ᵢ YAML | ✅ | 互相 embed（signature 幾乎相同） |
| PNG → JPG | 單向 | hasAlpha ∈ ker(f)，JPG 的 signature 沒有 alpha |

同層偏序圖：

```
文件:      PlainText ⊆ᵢ MD ⊆ᵢ Word ≈⊆ᵢ HTML
序列化:    CSV ⊆ᵢ JSON ≅ᵢ YAML ⊆ᵢ XML
圖片:      JPG ⊆ᵢ PNG ⊆ᵢ TIFF
資料庫:    CSV ⊆ᵢ SQLite ⊆ᵢ PostgreSQL
```

### 5.2 跨層格式（不同抽象層級，見 §6 定理）

| 關係 | 成立？ | 提供 interpretation 的理論 |
|------|:------:|------|
| MIDI ⊆ᵢ Audio (MP3/WAV) | ✅ | 聲學：pitch≜基頻, velocity≜amplitude, 疊加原理 |
| Audio ⊆ᵢ MIDI | ❌ | timbre, room acoustics, non-musical sound 不可定義 |
| SVG ⊆ᵢ PNG | ✅ | 幾何學 + 光柵化 |
| PNG ⊆ᵢ SVG | ❌ | sub-pixel detail, anti-aliasing 不可定義 |
| LaTeX ⊆ᵢ PDF | ✅ | 排版理論（TeX engine） |
| PDF ⊆ᵢ LaTeX | ❌ | glyph outline, exact positioning 不可定義 |

跨層偏序圖：

```
符號層 (symbolic)              信號層 (signal)
────────────                  ────────────
MIDI ──────[acoustics]─────→  Audio (WAV/MP3)
SVG ───────[rasterize]─────→  Bitmap (PNG/JPG)
LaTeX ─────[typeset]───────→  PDF
Source ─────[compile]──────→  Binary

方向永遠是 symbolic → signal（§6 Abstraction Embedding Theorem）
```

---

## 6. Abstraction Embedding Theorem

### 6.1 符號層與信號層

資料格式可以按抽象層級分為兩類：

- **符號層（symbolic）**：描述「是什麼」——MIDI（音符）、SVG（幾何圖形）、LaTeX（排版指令）、source code
- **信號層（signal）**：描述「怎麼呈現」——Audio/MP3（波形）、Bitmap/PNG（像素）、PDF（渲染結果）、binary

### 6.2 定理：跨層 Embedding 的方向性

> 設 A 為符號層格式，B 為信號層格式，
> 且存在一個物理/數學理論 P 提供 σ_A 在 σ_B 中的 interpretation。
>
> 則：
> 1. **A ⊆ᵢ B**（符號層 embeds 在信號層中）
> 2. **B ⊄ᵢ A**（信號層不能 embed 在符號層中）
>
> **證明**：
>
> (1) P 為 σ_A 的每個符號提供了 σ_B 中的定義（例：pitch ≜ 基頻）。
> Interpretation 存在 ⟹ embedding 存在。
> 且因為 B 的表達能力嚴格大於 A 所需，映射是 injective。∎
>
> (2) σ_B 包含 σ_A 中不可定義的符號（信號層的實現細節）。
> ∃s ∈ σ_B 使得 s 不能用 σ_A 的 formulas 定義。
> ∴ interpretation σ_B → σ_A 不完備 ⟹ embedding 不存在。∎

### 6.3 實例

| Symbolic (A) | Signal (B) | 提供 interpretation 的理論 P | A ⊆ᵢ B | B ⊄ᵢ A 的原因（ker） |
|---|---|---|:---:|---|
| MIDI | Audio (WAV/MP3) | 聲學 — pitch≜基頻, velocity≜amplitude, 疊加原理 | ✓ | timbre detail, room acoustics, phase |
| SVG | Bitmap (PNG) | 幾何學 + 光柵化 — circle≜像素集合 | ✓ | anti-aliasing, sub-pixel rendering |
| LaTeX | PDF | 排版理論 — `\frac{1}{2}`≜分數線座標 | ✓ | glyph outline, exact kerning |
| Source code | Binary | 編譯理論 — function≜machine code block | ✓ | register allocation, instruction scheduling |
| Sheet music | Audio | 演奏理論 — ♩≜波形 | ✓ | 演奏者表情、觸鍵、呼吸 |

### 6.4 為什麼方向是 symbolic → signal

```
符號層描述 "what"：       「彈 C4」「畫圓」「1/2」
信號層描述 "how"：        具體的波形、像素、座標

任何 "how" 都必然實現了某個 "what"
  → "what" 的資訊保留在 "how" 中
  → symbolic ⊆ᵢ signal

但 "how" 包含 "what" 沒有命名的實現細節
  → "how" 的資訊不能完整還原為 "what"
  → signal ⊄ᵢ symbolic
```

### 6.5 疊加原理作為 Embedding 機制

以 MIDI → Audio 為例，波的疊加（superposition）是 embedding 的物理機制：

```
MIDI:   Note₁(C4) + Note₂(E4) + Note₃(G4)
         ↓ synthesize
Audio:  wave₁(t)  + wave₂(t)  + wave₃(t) = wave_total(t)
```

不同的 MIDI 音符對應不同的頻譜成分，疊加後仍可分離（Fourier 分析）。
這不是 base64 式的任意編碼——而是物理上有意義的結構保持映射。

### 6.6 Case Study：MIDI ↔ MP3 的完整分析

MIDI 和 MP3 是展示 Abstraction Embedding Theorem 的最佳案例，
因為它們描述同一個現象（音樂）但在完全不同的抽象層級。

#### 6.6.1 兩個 Signature 的對比

```
σ_MIDI（符號層）                     σ_MP3（信號層）
────────────────                    ────────────────
sorts:                              sorts:
  Note        — 一個音符               Sample    — 一個取樣點
  Track       — 一個音軌               Frame     — 一個壓縮幀
  Instrument  — 一個樂器設定            Channel   — 一個聲道
  Tempo       — 速度標記               Metadata  — 檔案資訊

functions:                           functions:
  pitch: Note → {0..127}              amplitude: Sample → Float
  velocity: Note → {0..127}           time: Sample → Sec
  duration: Note → Ticks              spectral: Frame → Coefficients
  channel: Note → {0..15}             sampleRate: Metadata → Hz
  instrument: Track → GM_Program      bitRate: Metadata → kbps
  tempo: Tempo → BPM
```

**原始符號完全不同**——MIDI 的世界沒有 Sample，MP3 的世界沒有 Note。
但這不代表不能 embed（見下）。

#### 6.6.2 聲學提供 Interpretation

聲學物理為 σ_MIDI 的每個符號提供了 σ_Audio 中的定義：

```
interpret σ_MIDI in σ_Audio（由聲學提供）:

  Note(x)                 ≜  x 是波形中一個可辨識的獨立頻譜成分
  pitch(x) = 60 (C4)     ≜  x 的基頻（fundamental frequency）= 261.63 Hz
  velocity(x) = 80       ≜  x 的 onset peak amplitude ∝ 80/127
  duration(x) = 480 ticks ≜  x 的 onset 到 offset 時間（取決於 tempo）
  instrument(x) = Piano   ≜  x 的頻譜包絡（spectral envelope）符合鋼琴特徵
  tempo = 120 BPM        ≜  每個 tick = 1/960 sec
```

每個定義都是物理上有意義的——pitch 就是頻率，velocity 就是振幅，instrument 就是音色。
Interpretation 完備 ⟹ MIDI ⊆ᵢ Audio。

#### 6.6.3 疊加原理保證 Injectivity

MIDI 的多個同時發聲的音符如何 embed 到單一波形？波的疊加：

```
MIDI:   Note₁(C4, Piano, v=80) + Note₂(E4, Piano, v=70) + Note₃(G4, Piano, v=75)
         ↓ synthesize            ↓ synthesize            ↓ synthesize
Audio:  wave₁(t)               + wave₂(t)               + wave₃(t)
         ↓ superposition（線性疊加）
        wave_total(t) = wave₁(t) + wave₂(t) + wave₃(t)
```

關鍵性質：
- **可分離性**：不同頻率的波可以用 Fourier 分析分離 → 不同音符仍可辨識
- **Injectivity**：不同 MIDI → 不同波形（固定 synthesizer 下）→ ker = ∅
- **結構保持**：同時發聲 = 波的疊加，音量 = 振幅，音高 = 頻率

這是物理上有意義的 embedding，不是 base64 式的任意編碼。

#### 6.6.4 DAW 的角色：Interpretation Machine

DAW（Digital Audio Workstation）在這個框架中的精確身份：

```
σ_DAW ⊇ σ_MIDI ∪ σ_Audio ∪ σ_bridge

σ_bridge = {
  synthesize: (Note, Instrument) → Waveform,    — 合成
  mix: [Waveform] → Waveform,                   — 混音
  apply_reverb: (Waveform, Room) → Waveform,    — 殘響
  master: Waveform → CompressedAudio             — 母帶處理
}
```

DAW 是 σ_MIDI 和 σ_Audio 的 **join**（上界），加上連接兩個層級的 bridge functions。
不同的 DAW / soundfont 提供不同的 bridge functions → 不同的 interpretation。

**日常語言的精確對應**：

| 音樂用語 | Model Theory 對應 |
|---------|------------------|
| 「詮釋一首曲子」 | interpretation of a theory |
| 「不同指揮有不同詮釋」 | 同一 theory 的多個 model |
| 「忠於原譜」 | interpretation 保持了所有符號 |
| 「過度詮釋」 | interpretation 引入了 source 沒有的結構 |

「Interpret」同時是音樂術語和 model theory 術語——因為它們描述的是同一個數學結構。

#### 6.6.5 Model-Theory Duality：MIDI 檔案的雙重身份

一份 MIDI 檔案在不同的 signature 世界中扮演不同角色：

```
在 σ_MIDI 的世界:
  MIDI Spec (axioms):  pitch ∈ {0..127}, velocity ∈ {0..127}, ...
  song.mid:            model（完全確定——每個音符的 pitch、velocity、timing 都有具體值）

在 σ_Audio 的世界:
  song.mid 誘導出一組 axioms over σ_Audio:
    「t=0.5s 處必須有基頻 261.63Hz 的音」
    「onset amplitude ∝ 80/127」
    ...
  song.mid:            theory（不完備——只約束部分性質，不指定波形細節）
  DAW rendering:       該 theory 的一個 model
```

**同一份檔案，在自己的 signature 裡是 model，在低層的 signature 裡是 theory。**

這就是 **abstraction level 的精確定義**：

> **高抽象層的一個 model = 低抽象層的一個 theory**

| 高層 model | 低層 theory | 低層 model（需要選擇） |
|-----------|-----------|-------------------|
| song.mid | 「必須有這些音」 | DAW rendering.mp3 |
| diagram.svg | 「必須有這些形狀」 | render.png（選擇解析度） |
| paper.tex | 「必須有這些段落」 | output.pdf（選擇字體渲染） |
| main.c | 「必須實現這些函數」 | a.out（選擇最佳化策略） |

#### 6.6.6 反向轉換的不對稱性

| 方向 | 誰提供 interpretation | 品質 | 數學性質 |
|------|---------------------|------|---------|
| MIDI → MP3 | DAW（synthesizer + soundfont） | 確定性、高品質 | injective homomorphism |
| MP3 → MIDI | AI（音訊轉錄模型） | 機率性、有損 | 非唯一的近似逆映射 |

反向轉換困難的原因：

```
MP3 → MIDI 需要解決：
  一段波形 → 分離出各個音符        （polyphonic transcription，NP-hard 近似）
  頻譜包絡 → 辨識樂器              （timbre classification）
  連續振幅 → 離散 velocity          （quantization，多對一）
  實際演奏 → 理想化音符             （expression → discrete events）

同一個 MP3 可能對應多個合法的 MIDI 轉錄（逆映射不唯一）
```

理論的預測：σ_Audio 比 σ_MIDI 更大（更多 sorts 和 functions），
所以 Audio → MIDI 是 non-injective homomorphism（多對一），ker 很大。

### 6.7 Case Study：Analog vs Digital——「失真偏好」定理

#### 6.7.1 兩個 Signature

```
σ_Analog = {
  sorts:     { ContinuousSample }
  relations: { }
  functions: { amplitude: ContinuousSample → ℝ,         ← 連續實數，無限精度
               time: ContinuousSample → ℝ }              ← 連續時間
}

σ_Digital (CD) = {
  sorts:     { DiscreteSample }
  relations: { }
  functions: { amplitude: DiscreteSample → {-2¹⁵..2¹⁵-1},   ← 量化，16-bit
               time: DiscreteSample → ℕ × (1/44100) sec }    ← 離散，44.1kHz
}
```

差異在 function 的 codomain：analog 用 ℝ（無限精度），digital 用有限集合（量化）。

#### 6.7.2 Shannon-Nyquist 定理的 Axiom 依賴

Shannon-Nyquist 採樣定理說：band-limited 信號以 2×f_max 取樣可完美重建。

```
加入 axiom:  ∀f > 22050Hz : spectral_energy(f) = 0   ← band-limited 假設

在此 axiom 下:  Digital ≅ᵢ Analog   （isomorphism，ker = ∅）
移除此 axiom:   ker(Analog → Digital) = { above_nyquist, inter_sample, quantization_residual }
```

Shannon-Nyquist 的結論 ker = ∅ **依賴一條理想化的 axiom**。
真實訊號不完美 band-limited ⟹ ker ≠ ∅ ⟹ 數位化確實丟了東西。

但丟的東西（>22kHz 的頻率成分、取樣間的微小行為）是否可被人耳感知，
是目的因（final cause）的問題，不是形式因。理論只負責指出 ker 的內容。

#### 6.7.3 兩條路徑，不同的 Kernel

Analog 播放本身也有損失——物理媒體引入自己的 kernel：

```
ker(Original → CD playback) = {
  above_nyquist_frequencies,      — Nyquist 以上的頻率截斷
  quantization_residual,          — 振幅量化誤差
  inter_sample_behavior           — 取樣點之間的精確波形
}

ker(Original → Vinyl playback) = {
  noise_floor_detail,             — 底噪淹沒的微弱訊號
  wow_and_flutter,                — 轉速不穩定的音高偏移
  physical_degradation,           — 磨損、灰塵、刮痕
  high_freq_rolloff               — 媒體頻率響應的高頻衰減
}
```

**兩邊都丟東西，但丟的東西完全不同。**
Shannon 只能說「都丟了 X bits」；Formal Information Theory 逐項列出 kernel 的內容。

#### 6.7.4 關鍵發現：Analog 不只「丟」——它還「加」

Homomorphism 只能保留或丟失資訊（Im(f) 和 ker(f)）。
但類比媒體做了 homomorphism 不允許的事——**引入了原始訊號中不存在的新結構**：

```
Vinyl 引入:    harmonic distortion（偶次諧波失真）
               RIAA EQ curve（頻率響應曲線）
               surface noise（唱片表面噪聲）

Tape 引入:     tape saturation（磁帶飽和失真）
               hiss（嘶嘶聲）
               head bump（低頻突起）

Tube amp 引入: even-order harmonics（偶次諧波）
               soft clipping（軟截幅）
               sag（電壓下降造成的動態壓縮）
```

這些是 **non-homomorphic component**——它們不保持原始結構，而是變換結構。

形式化：

```
f_vinyl: Original → Vinyl_playback

f_vinyl = h ∘ g    其中:
  g: Original → Original|_reduced    — homomorphic part（丟掉 ker）
  h: Original|_reduced → Vinyl_out   — non-homomorphic part（加入失真）

Vinyl_out ≠ Im(g)   — 輸出包含原始訊號中不存在的頻譜成分
```

#### 6.7.5 定理：失真偏好的統一原理

> **「喜歡黑膠的溫暖」和「喜歡失真吉他的 crunch」是同一個數學現象。**

| 現象 | 原始訊號 | Non-homomorphic mapping | 引入的失真 | 人的偏好 |
|------|---------|----------------------|-----------|---------|
| 黑膠「溫暖」 | 母帶錄音 | Vinyl playback chain | 偶次諧波、RIAA 曲線 | 「聽起來更自然」 |
| 磁帶「飽滿」 | 母帶錄音 | Tape saturation | 軟飽和、高頻壓縮 | 「聽起來更厚實」 |
| 真空管「甜美」 | 吉他乾聲 | Tube amplifier | 偶次諧波、軟截幅 | 「聽起來更有味道」 |
| 失真吉他「crunch」 | 吉他乾聲 | Overdrive/distortion pedal | 諧波失真、壓縮 | 「聽起來更有力量」 |
| 底片「質感」 | 光學影像 | Film chemistry | 顆粒、色偏、動態壓縮 | 「看起來更有感覺」 |
| Instagram 濾鏡 | 數位照片 | Filter algorithm | 色調偏移、暈影、顆粒 | 「看起來更好看」 |

**統一原理**：

> 人類偏好特定的 **non-homomorphic mapping profile**——
> 不是因為它「保留了更多資訊」（ker 可能更大），
> 而是因為它引入的**特定失真模式**被感知為令人愉悅。

這解釋了一個長久以來無法用傳統資訊理論回答的問題：
為什麼人們偏好「客觀上更差」的轉換路徑？

答案：他們偏好的不是「更少的 kernel」，而是「更令人愉悅的 non-homomorphic component」。
傳統框架只能看到 ker（丟了什麼），看不到 non-homomorphic part（加了什麼）。
Formal Information Theory 區分了三件事：

```
任何轉換 f 的完整分解:

  Im(f)                    — 保留了什麼
  ker(f)                   — 丟了什麼
  f(x) - h(x)             — 加了什麼（non-homomorphic residual）

其中 h 是最接近 f 的 homomorphism。
```

#### 6.7.6 為什麼「偶次諧波」被偏好

黑膠、磁帶、真空管共同的物理特性：它們的非線性特性主要產生**偶次諧波**（2nd, 4th, 6th...）。

```
輸入:  sin(ωt)                          — 純音 (fundamental)
輸出:  sin(ωt) + a₂·sin(2ωt) + a₄·sin(4ωt) + ...   — 加入偶次諧波

偶次諧波 = 高八度、高兩個八度... = 和聲上「協和」的音程
```

電晶體和數位截幅主要產生**奇次諧波**（3rd, 5th, 7th...），聽起來「刺耳」。

用 Formal Information Theory 的語言：

```
f_tube(x)   = h(x) + Σ aₙ·harmonics_even(x)     ← 偶次諧波，被感知為「溫暖」
f_digital(x) = h(x) + Σ bₙ·harmonics_odd(x)      ← 奇次諧波，被感知為「刺耳」
```

兩者都是 non-homomorphic，但 **non-homomorphic residual 的頻譜結構不同**，
導致截然不同的主觀感受。

#### 6.7.7 意外的統一：不同音樂文化的共同數學結構

本理論最令人驚訝的結果：**表面上對立的音樂文化，底層是同一個數學函數。**

```
發燒友:    「我追求保真、自然、原汁原味」
吉他手:    「我故意破壞、扭曲、弄髒訊號」

文化上完全對立——一個在 hi-fi 展，一個在搖滾演唱會。
```

但數學說的是：

```
f_vinyl(x)    = h(x) + Σ aₙ · harmonics_even(x)     a₂ ≈ 0.01
f_tube_amp(x) = h(x) + Σ bₙ · harmonics_even(x)     b₂ ≈ 0.3
                       ↑
                  同一個函數，只是係數不同
```

從「溫暖」到「crunch」到「fuzz」是一個連續光譜：

```
係數大小:     0.01        0.05        0.3         0.8
              │           │           │           │
感知:        溫暖        飽滿       crunch       fuzz
場景:        黑膠        磁帶       tube amp     fuzz pedal
文化:        hi-fi       錄音室      搖滾        噪音搖滾
```

**不是四種不同的現象——是同一個函數的四個參數值。**

#### 6.7.8 跨音樂文化的驗證

每個音樂文化都在選擇自己偏好的 non-homomorphic profile：

| 音樂文化 | 偏好的失真來源 | Non-homomorphic residual |
|---------|-------------|----------------------|
| 古典 | 音樂廳殘響 | 空間對聲音的卷積（convolution）|
| 爵士 | Tape recording | Tape saturation + hiss |
| 搖滾 | Tube amp overdrive | 偶次諧波 + 軟截幅 |
| Hip-hop | Vinyl sampling | Crackle + warmth + 頻率著色 |
| Lo-fi | 故意降低品質 | 刻意放大所有 non-homomorphic component |
| 電子音樂 | Bitcrusher / saturation plugin | 數位重建 non-homomorphic residual |

特別值得注意的是 Hip-hop sampling：

```
Producer 的工作流程:
  Digital source → 錄到黑膠 → 從黑膠取樣回數位
                      ↑
              人工引入 vinyl 的 non-homomorphic residual
              純粹為了美學，不為保真

如果用 CD 取樣同一首歌 → 「不對」
因為缺少 vinyl 的 non-homomorphic component
```

這在音樂產業每天發生。Analog modeling plugin 的整個產業（Waves、UAD、FabFilter）
本質上是在做一件事：**在 homomorphic（數位）路徑上人工注入 non-homomorphic residual。**

如果「溫暖」真的來自更高的保真度（更小的 ker），
那數位模擬失真不可能重現它。但事實上可以——
這反過來證明了「溫暖」來自失真，不來自保真度。

---

## 7. 對轉換架構的影響

### 7.1 Hub 模式的資訊瓶頸

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

### 7.2 定理：直接轉換最優

> 對任意格式 A, B 和任意 hub H：
>
> **Loss(A → B) ≤ Loss(A → H → B)**
>
> 等號成立 iff A ⊆ᵢ H（A 完全 embed 在 hub 中）。

**不存在一個 hub 格式能同時滿足所有格式對的等號條件**——
因為不存在一個 σ_H 同時是所有 σ 的 superset（格式們互不包含）。

這就是為什麼 macdoc 選擇兩兩直接轉換。

---

## 8. O(n²) 的可行性：AI 改變了等式

### 8.1 歷史背景

n 個格式之間的兩兩轉換需要 n(n-1) 個 converter（雙向）。

| 格式數 | Hub (2n) | 兩兩直接 (n(n-1)) |
|--------|:--------:|:-----------------:|
| 3 | 4 | 6 |
| 5 | 8 | 20 |
| 10 | 18 | 90 |

在 AI 之前，n(n-1) 個 converter 是不切實際的。
Pandoc 的 hub 模式是**人力限制下的務實妥協**——犧牲保真度換取可維護性。

### 8.2 AI 改變了成本結構

| | Hub 時代（人力限制） | 直接轉換時代（AI 輔助） |
|---|---|---|
| **Converter 數量** | 2n（可管理） | n(n-1)（以前不可管理） |
| **每個 converter 的開發成本** | 高（人工逐行寫） | 低（結構相同，AI 套 template） |
| **每條路徑的保真度** | ≤ hub 的表達能力 | = 格式對的最大交集 |
| **總開發成本** | 2n × 高 | n(n-1) × 低 |
| **總保真度** | 受 hub 限制 | 最優 |

### 8.3 本質

> **macdoc 的哲學是：用 AI 的生產力換取轉換品質。**
>
> n(n-1) 個 converter 在 AI 時代不再荒謬——它是**定理 7.2 的正確實現**。
> 以前因為人力限制而不得不做的妥協（hub），現在可以消除。

---

## 9. 與 Shannon Information Theory 的關係

### 9.1 兩種「資訊」的定義

Shannon (1948) 定義資訊為**消除不確定性的量**，單位是 bit。
本文定義資訊為**結構中的可區分性**，由 signature 的符號刻畫。

| | Shannon Information Theory | Formal Information Theory |
|---|---|---|
| **問的問題** | 這個訊號源有多少資訊？ | 這個格式能區分哪些文件？ |
| **衡量什麼** | 資訊的**量**（bits） | 資訊的**結構**（sorts, relations, functions） |
| **損失的描述** | H(X) - H(X\|Y) bits | ker(f) = {color, fontSize, underline, ...} |
| **資訊是否可替換** | 是——1 bit 顏色 = 1 bit 字體 | 否——不同符號是不同維度 |
| **核心工具** | 熵 H(X)、互資訊 I(X;Y)、channel capacity | Signature σ、homomorphism、kernel、interpretation |

### 9.2 Shannon 的盲點

Shannon 理論把資訊當成**不透明的 bits**。在文件轉換的語境下：

```
Shannon:   Loss(Word→MD) = 47.3 bits per document
           → 「丟了 47.3 bits」

Formal: ker(Word→MD) = { color, fontSize, font, underline,
                              alignment, spacing, pageBreak,
                              comment, bookmark, ... }
           → 「丟了顏色、字體大小、對齊方式、批註…」
```

使用者在意的是「我的標題還在嗎？我的圖片還在嗎？」——不是「我丟了多少 bits」。
Shannon 的框架無法區分「丟了顏色」和「丟了標題」，因為它不為資訊的各個分量命名。

### 9.3 結構化損失分解

兩個框架可以結合。每個符號 s ∈ σ 都有自己的 Shannon 熵 H(s)：

```
Shannon 總損失 = Σ_{s ∈ ker(f)} H(s)

Word→MD 的損失分解：
  H(color)     = 8.2 bits   （RGB 256³ 種可能）
  H(fontSize)  = 4.5 bits   （常見字體大小約 20 種）
  H(font)      = 6.1 bits   （常見字體約 70 種）
  H(underline) = 2.8 bits   （7 種 underline 類型）
  H(alignment) = 2.0 bits   （4 種對齊方式）
  H(comment)   = ?  bits    （結構化文字，熵不固定）
  ...
  ─────────────────────────
  總損失 ≈ 23.6+ bits/element
```

**這個分解是 Shannon 框架做不到的**——它只能給你總數。
Formal Information Theory 識別出 ker(f) 的每個分量，
然後 Shannon 可以量化每個分量的熵。兩者結合才是完整的圖像。

### 9.4 為什麼叫「Formal」——亞里斯多德的形式因

命名來自亞里斯多德的四因說（Four Causes）。Shannon 回答的是**質料因**（causa materialis）的問題——
資訊由多少 bits 構成。本框架回答的是**形式因**（causa formalis）的問題——資訊具有什麼形式與結構。

| 亞里斯多德的因 | 在資訊理論中的對應 |
|--------------|-------------------|
| **質料因** (Material) — 由什麼構成 | Shannon — 資訊由多少 bits 構成 |
| **形式因** (Formal) — 具有什麼形式 | 本框架 — 資訊具有什麼 signature（sorts, relations, functions） |
| **動力因** (Efficient) — 由什麼產生 | 轉換器 — homomorphism 如何實作 |
| **目的因** (Final) — 為了什麼目的 | 使用者需求 — 為什麼要轉換、要保留什麼 |

Shannon 的理論有時被稱為 **Quantitative Information Theory**——它量化資訊。
本框架是 **Formal Information Theory**——它刻畫資訊的形式。

| 比喻 | Shannon | Formal |
|------|---------|------------|
| 描述一個形狀 | 「面積是 12 cm²」 | 「4 條邊、直角、邊長相等 → 正方形」 |
| 描述一份文件 | 「38.7 KB」 | 「有標題、有表格、有圖片、有批註」 |
| 描述轉換損失 | 「丟了 47.3 bits」 | 「丟了 {color, fontSize, comment}」 |

兩者正交、互補：
- **Formal** 回答「丟了什麼？」（定性）
- **Shannon** 回答「丟了多少？」（定量）
- **結合** 回答「每種東西各丟了多少？」（定性 + 定量）

### 9.5 更深層的差異：資訊的本體論

Shannon 的資訊是**統計性質**——它描述的是隨機變數的分佈，不是任何具體的「東西」。
Formal information 是**代數性質**——它描述的是結構中符號的存在與否。

```
Shannon:      H(X) = -Σ p(x) log p(x)
              → 資訊是分佈的函數，跟具體內容無關
              → 兩個完全不同的文件可以有相同的熵

Formal:   σ_A = { sorts: ..., relations: ..., functions: ... }
              → 資訊是結構的函數，跟能區分什麼有關
              → 兩個不同的格式有不同的 signature（即使 Shannon 熵相同）
```

一個格式的「資訊容量」不是用 bits 衡量，而是用它的 signature 能區分多少不同的文件——
這就是 injection 的定義：**f 是 injective iff 不同的輸入產生不同的輸出**。

Shannon 不關心「區分什麼」，只關心「能區分多少」。
Formal Information Theory 精確刻畫了「什麼被區分、什麼被 collapse」。

---

## 10. 理論的適用範圍

本理論的三條公理（資料 = structure，轉換 = homomorphism，損失 = kernel）
適用於所有結構化資料的轉換。不同領域長久以來各自發明的詞彙，在這個框架下統一：

| 領域 | 他們的說法 | 統一的說法 |
|------|----------|-----------|
| 文件轉換 | "fidelity loss" | ker(f) |
| 資料庫遷移 | "schema incompatibility" | σ_A ∖ σ_B |
| 音訊轉碼 | "lossy compression" | ker(f) ≠ ∅ |
| 圖片轉檔 | "alpha channel lost" | hasAlpha ∈ ker(f) |
| 序列化 | "data doesn't round-trip" | ¬∃g: g∘f = id |
| 型別系統 | "narrowing conversion" | non-injective homomorphism |
| ETL pipeline | "data cleaning drops fields" | explicit kernel choice |

### 相關學術框架

| 框架 | 作者 | 與本理論的關係 |
|------|------|-------------|
| Channel Theory | Barwise & Seligman (1997) | 用 classification + infomorphism 描述資訊流——概念最接近，但不使用 signature |
| Functorial Data Migration | Spivak (2010s) | 用 category theory 處理 database schema 遷移——是本框架在 database 領域的 special case |
| Institution Theory | Goguen & Burstall (1992) | 泛化邏輯系統之間的翻譯——本框架的 interpretation 是其特例 |

---

## 11. 與 macdoc 文檔的關係

| 文檔 | 關聯 |
|------|------|
| `lossless-conversion.md` | §0 的 bijection = embedding 的特例（A ⊆ᵢ A + metadata = isomorphism） |
| `philosophy.md` | 「為什麼不用 Hub Format」段落的理論基礎 |
| `functional-correspondence.md` | 即 §3 的 interpretation 實例——跨格式的符號對應表 |
| `modular-architecture.md` | Layer 3 的 converter 數量 = n(n-1) 的實體化 |
