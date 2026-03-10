# PDF Source Detection

## 概念

不同來源產生的 PDF 有根本性的結構差異。偵測來源格式可以讓 pipeline 選擇最適合的轉換策略。

## 偵測訊號

### Layer 1: Metadata（快速，高可信度）

PDF 的 Document Info Dictionary 包含 `/Creator` 和 `/Producer` 欄位：

| 來源 | Creator 範例 | Producer 範例 |
|------|-------------|--------------|
| pdfTeX | `TeX` | `pdfTeX-1.40.21` |
| XeTeX | `XeTeX` | `xdvipdfmx (0.7.9)` |
| LuaTeX | `LuaTeX` | `LuaHBTeX, Version 1.15.0` |
| Word | `Microsoft Word` | `macOS Version 14.0 (Build 23A344) Quartz PDFContext` |
| Pages | `Pages` | `macOS ... Quartz PDFContext` |
| typst | `typst` | `typst 0.11.0` |
| InDesign | `Adobe InDesign 19.0` | `Adobe PDF Library 17.0` |

注意：有些 PDF 經過後製工具（如 Acrobat Distiller），metadata 會被覆蓋。此時需要依賴 Layer 2。

### Layer 2: 字型分析（可靠，需掃描頁面）

| 字型家族 | 字型名稱前綴 | 來源 |
|---------|------------|------|
| Computer Modern (OT1) | CMR, CMBX, CMTI, CMSL, CMSS, CMTT | LaTeX |
| Computer Modern Math | CMMI, CMSY, CMEX, MSBM, MSAM | LaTeX |
| DC/EC (T1) | DCR, DCBX, DCTI, ECR, ECBX | LaTeX (T1 encoding) |
| cm-super (SF) | SFRM, SFBX, SFTI, SFSL | LaTeX (Type1 T1) |
| Latin Modern | LMROMAN, LMMONO, LMSANS | LaTeX (lmodern) |
| Office 系統字型 | Calibri, Cambria, Arial, Times New Roman | Word/Office |

`PDFMetadataExtractor` 已有完整的字型分類邏輯，`PDFSourceDetector` 重用此基礎。

### Layer 3: 文字層偵測

- 有文字層 → 數位原生 PDF（可提取文字）
- 無文字層 → 掃描件（需 OCR）
- 稀疏文字層 → 可能是 OCR 後的掃描件

## 對 Pipeline 的影響

### AI Prompt 模板

```
source=latex:
  "Reconstruct the original LaTeX. Preserve theorem/proof/lemma
   environments, equation numbering, \ref cross-references."

source=word:
  "Convert to clean LaTeX. Use basic formatting — \textbf for bold,
   \textit for italic. Do not guess custom environments."

source=scanned:
  "OCR quality may vary. Focus on mathematical symbol accuracy.
   Flag uncertain regions in the uncertainties array."
```

### LaTeXNormalizer 行為

| 正規化規則 | LaTeX 來源 | Word 來源 |
|-----------|-----------|----------|
| 符號正規化 | 輕度（保留原始風格） | 重度（統一為標準 LaTeX 慣例） |
| 環境推斷 | 嘗試重建 `\begin{theorem}` 等 | 不推斷，保留純文字格式 |
| 跨頁去重 | 正常 | 可能需要更積極（Word 分頁行為不同） |
| 公式品質預期 | 高（TeX 排版精確） | 中（Equation Editor 排版差異大） |

### PDFComparator 評分基準

- LaTeX 來源：期待高相似度（> 90%），因為應該能精確重建
- Word 來源：容許較低相似度（> 70%），格式轉換本來就有損
- 掃描件：不適用逐頁比對

## 資料模型

```swift
public enum PDFSourceFormat: String, Codable, Sendable {
    case latex, word, typst, designer, scanned, unknown
}

public struct PDFSourceDetection: Codable, Sendable {
    let format: PDFSourceFormat
    let confidence: Double      // 0.0 ~ 1.0
    let engine: LaTeXEngine?    // pdfTeX, xeTeX, luaTeX, dvipdfm
    let creator: String?
    let producer: String?
    let evidence: [String]
}
```

偵測結果儲存在 `structure.json` 中，Phase 2 consolidation 時不需重新偵測。

## CLI

```bash
# 偵測來源格式
macdoc pdf detect-source textbook.pdf
macdoc pdf detect-source textbook.pdf --json

# 手動覆蓋（未來）
macdoc pdf transcribe --project ./book --source word
macdoc pdf consolidate --project ./book --source latex
```

## 設計決策

1. **偵測與轉換分離**：`detect-source` 是獨立命令，不強制綁在 pipeline 中
2. **結果持久化**：存入 `structure.json`，避免重複偵測
3. **手動覆蓋優先**：`--source` flag 覆蓋自動偵測，使用者永遠有最終決定權
4. **重用現有分析**：字型分類邏輯來自 `PDFMetadataExtractor`，不重複實作
