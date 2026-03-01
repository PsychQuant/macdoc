# Practical Defaults

Fidelity Tier 系統（見 `lossless-conversion.md`）定義了**保留多少資訊**。
但保真度高不等於實用——EMF 圖片保真度 100%，瀏覽器卻打不開。

本文件定義與 Fidelity Tier **正交**的第二個維度：**Practical Mode**。

---

## 1. 問題：Fidelity ≠ Practicality

| 情境 | 保真做法 | 實用做法 |
|------|---------|---------|
| 圖片格式 | 保留 EMF/WMF（原始格式） | 轉 PNG（瀏覽器/app 都能看） |
| 標題偵測 | 只認 Word Heading Style | 統計推斷（字體大小分佈） |
| 字體資訊 | 保留在 metadata | 忽略（Tier 1/2 不需要） |

Fidelity Tier 回答「輸出幾個通道」，Practical Mode 回答「每個通道的輸出是否為人類最佳化」。

```
             Practical Mode
             OFF (Original)          ON (Default)
            ┌──────────────────┬──────────────────┐
Tier 1      │ Style-only       │ + Heuristic      │
(MD)        │ heading          │   heading        │
            ├──────────────────┼──────────────────┤
Tier 2      │ EMF/WMF 原圖     │ PNG 轉檔         │
(MD+Fig)    │ Style-only       │ + Heuristic      │
            ├──────────────────┼──────────────────┤
Tier 3      │ EMF/WMF 原圖     │ PNG 轉檔         │
(Marker)    │ Style-only       │ + Heuristic      │
            │ + Full metadata  │ + Full metadata  │
            └──────────────────┴──────────────────┘
```

**Practical Mode 預設 ON。** 因為 95% 的使用者要的是「能用」，不是「保真」。
需要保真的使用者可以設 `preserveOriginalFormat: true` 取得原始格式。

---

## 2. 圖片格式轉換

### 現狀（Bug）

`FigureExtractor` 直接寫入原始 binary，不做格式轉換：

```swift
// word-to-md-swift/FigureExtractor.swift (現行)
let fileURL = directory.appendingPathComponent(imageRef.fileName)
try imageRef.data.write(to: fileURL)  // EMF → EMF, 沒人能開
```

### 修正方案

```swift
mutating func extract(_ imageRef: ImageReference, preserveOriginal: Bool = false) throws -> String {
    guard !extractedIds.contains(imageRef.id) else {
        return relativePath(for: outputFileName(imageRef, preserveOriginal: preserveOriginal))
    }

    let data: Data
    let fileName: String

    if preserveOriginal || isWebFriendly(imageRef.contentType) {
        // 原始格式（PNG/JPEG 本來就能用，或使用者要求保留原始）
        data = imageRef.data
        fileName = imageRef.fileName
    } else {
        // 非 web-friendly 格式（EMF/WMF/TIFF）→ 轉 PNG
        data = try convertToPNG(imageRef.data)
        fileName = replaceExtension(imageRef.fileName, with: "png")
    }

    let fileURL = directory.appendingPathComponent(fileName)
    try data.write(to: fileURL)
    extractedIds.insert(imageRef.id)

    return relativePath(for: fileName)
}
```

### 格式判定

| 原始格式 | Web-friendly? | Practical Mode 行為 |
|---------|:------------:|-------------------|
| PNG     | ✅ | 保持不變 |
| JPEG    | ✅ | 保持不變 |
| GIF     | ✅ | 保持不變 |
| SVG     | ✅ | 保持不變 |
| TIFF    | ❌ | → PNG |
| EMF     | ❌ | → PNG |
| WMF     | ❌ | → PNG |
| BMP     | ❌ | → PNG |

### macOS 轉換實作

macOS 原生支援 EMF/WMF 渲染，可用 `NSImage` 轉換：

```swift
#if canImport(AppKit)
import AppKit

func convertToPNG(_ data: Data) throws -> Data {
    guard let image = NSImage(data: data) else {
        throw ConversionError.unsupportedImageFormat
    }
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw ConversionError.imageConversionFailed
    }
    return pngData
}
#endif
```

> **注意**：這限制了 EMF→PNG 轉換只能在 macOS 上執行。
> Linux/Windows 環境需要替代方案（如 librsvg、ImageMagick），或 fallback 到保留原始格式。
> 但 macdoc 本身就是 macOS-only（使用 EventKit、AppKit 等），所以這不是問題。

---

## 3. Heading Heuristic（統計推斷）

### 現狀（Missing Feature）

`WordConverter` 只檢查 `paragraph.properties.style` 是否為 heading style：

```swift
// word-to-md-swift/WordConverter.swift (現行)
if let styleName = paragraph.properties.style,
   let headingLevel = detectHeadingLevel(styleName: styleName, styles: context.styles) {
    // 有 heading style → 轉為 # heading
}
// 沒有 heading style → 當作普通段落
```

許多 .docx 文件（尤其是非專業使用者建立的）不使用 Word Heading Style，
而是用「Normal + 粗體 + 放大字體」來當標題。這些文件轉出來完全沒有結構。

### 統計推斷演算法

不用寫死 threshold（如「≥16pt = H1」），而是掃描全文 font size 分佈，自動分群。

#### Phase 1：收集 font size 分佈

```
掃描全文所有段落，記錄每段的 effective font size：
  - 如果有 heading style → 跳過（已由 style 偵測處理）
  - 如果段落只有一個 run 或所有 run 同大小 → 記錄該 font size
  - 如果段落有混合大小 → 記錄最大的 font size（標題段落通常一致）

結果示例（心理統計考題 .docx）：
  12pt: 450 段落（本文）
  14pt:  25 段落（小節標題）
  18pt:  10 段落（章節標題）
```

#### Phase 2：分群（Clustering）

```
1. 找出所有 distinct font sizes，按出現次數排序
2. 出現最多的 size = body text（基準線）
3. 比 body 大的 sizes = heading 候選
4. 按大小排序，對應 heading level：
   - 最大 → H1
   - 第二大 → H2
   - 第三大 → H3
   - ...以此類推（最多到 H6）

額外信號（提高信心）：
  - bold: 標題段落通常是粗體
  - 段落長度短: 標題通常 < 100 字元
  - 獨佔一行: 標題後通常有空行或換段
```

#### Phase 3：套用

```
二次遍歷（或 buffered streaming），對每個段落：
  if 已有 heading style → 用 style（優先）
  else if font size 屬於 heading 群 → 用推斷的 heading level
  else → 普通段落
```

### 與 Streaming 架構的相容性

統計推斷需要**兩次遍歷**（first pass 收集分佈，second pass 套用）。
這與 `philosophy.md` 的 streaming 原則有張力。

解法：

| 方案 | 做法 | 代價 |
|------|------|------|
| **Two-pass** | 第一遍掃描 font sizes，第二遍轉換 | 讀兩次，但 .docx 已在記憶體中（`DocxReader.read()` 已全部載入） |
| **Buffered streaming** | 緩衝 N 段落，動態調整分群 | 開頭幾段可能判斷錯誤 |
| **Pre-scan metadata** | 只掃描 `styles.xml` + `document.xml` 的 `<w:rPr>` 屬性 | 不需要完整 parse |

**推薦 Two-pass**：因為 `DocxReader.read()` 已經把整份文件載入 `WordDocument`，
font size 分佈可以在 `WordConverter.convert()` 開頭用一次快速遍歷收集，
不增加 I/O 成本。

### 實作位置

```swift
// word-to-md-swift/WordConverter.swift

/// 統計推斷 heading level（在沒有 heading style 時使用）
private struct HeadingHeuristic {
    /// font size → heading level 的映射（由 analyze() 建立）
    private var sizeToLevel: [Double: Int] = [:]

    /// 分析全文 font size 分佈，建立映射
    mutating func analyze(paragraphs: [WordParagraph]) {
        // Phase 1: 收集（跳過已有 heading style 的段落）
        // Phase 2: 分群（找出 body size，比 body 大的 → heading 候選）
    }

    /// 推斷段落的 heading level（nil = 普通段落）
    func inferLevel(for paragraph: WordParagraph) -> Int? {
        // Phase 3: 查表
    }
}
```

### 與 Fidelity Tier 的關係

| Tier | Practical OFF | Practical ON |
|------|:------------:|:------------:|
| 1 | Style-only → 純粹、可預測 | + Heuristic → 實用但有誤判風險 |
| 2 | 同上 | 同上 |
| 3 | 同上（metadata 記錄原始 style） | 同上（metadata 額外記錄 `inferred: true`） |

Tier 3 的 metadata 應標註哪些 heading 是推斷的（`inferred: true`），
讓逆轉換器（md-to-word-swift）在 round-trip 時能區分：
- `inferred: false` → 逆轉換時套用 Word Heading Style
- `inferred: true` → 逆轉換時保持 Normal + bold + 大字體（還原原始格式）

---

## 4. ConversionOptions 擴展

```swift
public struct ConversionOptions: Sendable {
    // 既有
    public var fidelity: FidelityTier
    public var includeFrontmatter: Bool
    public var hardLineBreaks: Bool
    public var figuresDirectory: URL?

    // 新增：Practical Mode（預設 ON）
    public var preserveOriginalFormat: Bool = false  // true = 保留 EMF/WMF
    public var headingHeuristic: Bool = true          // true = 統計推斷 fallback
}
```

### 選項交互

```
preserveOriginalFormat = false, headingHeuristic = true   → 預設（最實用）
preserveOriginalFormat = true,  headingHeuristic = false  → 最保真
preserveOriginalFormat = true,  headingHeuristic = true   → 保真圖片 + 實用標題
preserveOriginalFormat = false, headingHeuristic = false  → 實用圖片 + 純粹標題
```

四種組合都是合法的，使用者可以按需求混搭。

---

## 5. 設計原則

1. **預設實用** — `preserveOriginalFormat = false`, `headingHeuristic = true`
2. **保真可選** — 需要原始格式的使用者明確 opt-in
3. **正交可組合** — Practical Mode 的每個選項獨立於 Fidelity Tier
4. **可標註來源** — Tier 3 metadata 標註哪些是推斷的（`inferred: true`），保護 round-trip 完整性
5. **Platform-aware** — EMF→PNG 依賴 macOS AppKit，非 macOS 環境 fallback 到保留原始格式
