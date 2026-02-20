# 語義標註系統實作對話記錄

**日期**: 2026-01-14
**專案**: macdoc / ooxml-swift
**主題**: Word 文件語義標註系統

---

## 目標

在 Word 文件解析階段加入完整語義標註，讓後續轉換器可以直接使用標註，不需要再推斷元素類型。

## 實作內容

### 1. 新建檔案

| 檔案 | 路徑 |
|------|------|
| `SemanticAnnotation.swift` | `ooxml-swift/Sources/OOXMLSwift/Models/SemanticAnnotation.swift` |

定義的語義類型：
- `SemanticElementType`: heading, paragraph, title, subtitle, bulletListItem, numberedListItem, formula, image, pageBreak, etc.
- `FormulaType`: omml, mathType, latex, imageFormula, unknown
- `ImageClassification`: regular, photo, diagram, screenshot, formulaImage, unknown
- `AnnotationSource`: parsed, inferred, classified, pending

### 2. 修改檔案

| 檔案 | 修改內容 |
|------|----------|
| `Paragraph.swift` | 加入 `public var semantic: SemanticAnnotation?` |
| `Run.swift` | 加入 `public var semantic: SemanticAnnotation?` |
| `DocxReader.swift` | 解析時產生語義標註 |
| `MarkerWordConverter.swift` | 使用語義標註決定輸出格式 |

### 3. DocxReader.swift 主要修改

- 重新排序解析流程：styles 和 numbering 先解析，再解析 body
- 新增 `parseNumbering()`: 解析 numbering.xml
- 新增 `detectParagraphSemantic()`: 偵測段落語義類型
- 新增 `detectHeadingLevel()`: 從樣式名稱偵測標題層級
- 新增 `isBulletList()`: 判斷是否為項目符號清單
- 修改 `parseParagraphProperties()`: 加入 numbering 屬性解析
- 修改 `parseRun()`: 加入圖片和 OMML 公式的語義標註
- 修改表格解析函數：傳遞 styles 和 numbering 參數

### 4. MarkerWordConverter.swift 修改

使用語義標註來決定輸出格式：
```swift
if let semantic = paragraph.semantic {
    switch semantic.type {
    case .heading(let level):
        try writer.heading(text, level: level)
    case .bulletListItem(let level):
        try writer.bulletItem(text, level: level)
    // ...
    }
}
```

## Git 提交

### ooxml-swift
```
commit 3ae0584
feat: add semantic annotation system for Word document parsing

- Add SemanticAnnotation.swift with types for heading, list, formula, image
- Add semantic property to Paragraph and Run models
- Implement detectParagraphSemantic() in DocxReader
- Parse numbering.xml for list detection
- Annotate headings, bullet/numbered lists, OMML formulas, images during parsing
```

## 額外工作

創建了 `.claude/rules/swift-package-update.md` 規則檔案，說明：
- Swift Package 依賴更新流程
- 本地路徑依賴（`path:`）的處理方式
- macdoc 專案的套件依賴結構

## 測試結果

- ooxml-swift 編譯成功
- macdoc 編譯成功
- 實際文件轉換測試通過（38 張圖片正確提取）

## 架構圖

```
DOCX → DocxReader (解析 + 標註) → WordDocument → MarkerWordConverter → MD + JSON + images/
         ↓
    semantic: .heading(1)
    semantic: .bulletListItem(0)
    semantic: .image(.unknown)
    semantic: .formula(.omml)
```

## 後續可擴展

1. 實作 ImageClassifier 處理 `.image(.unknown)` 標註
2. 實作 OMML 到 LaTeX 轉換處理 `.formula(.omml)` 標註
3. 加入更多語義類型（codeBlock, blockquote 等）
