# Heuristic Output 原則

## 核心理念

每個 converter 都必須有 **heuristic 模式**：輸出要最符合人類閱讀習慣，不能讓源格式的標記語法洩漏到目標格式中。

## 三層分離架構

```
源格式設定層 → 內部樣式模型 → 目標格式設定層
（讀取，不輸出）   （中間表示）    （套用，不暴露來源）
```

### 以 tex-to-docx 為例

```
LaTeX 設定層（preamble + commands.tex）    ← 讀取
├── \definecolor{titleBrown}{HTML}{663300}  → RunProperties.color = "663300"
├── \fontsize{36pt}{44pt}                  → RunProperties.fontSize = 72 (half-pt)
├── \bfseries                              → RunProperties.bold = true
├── \songti (思源宋體)                      → RunProperties.fontName = "Noto Serif TC"
└── \begin{titlepage}...\end{titlepage}    → 封面段落 + page break

內容層                                      ← 轉換
├── 賽斯書輕導讀                             → Run(text: "賽斯書輕導讀", properties: ...)
├── \摘要{文字}                              → bordered paragraph with ◆
└── 正文段落                                 → plain paragraph

Word 設定層                                  ← 輸出
├── DOCX RunProperties（fontSize, color, bold）
├── DOCX ParagraphProperties（border, shading, alignment）
└── DOCX 看不到任何 LaTeX 語法
```

## 規則

### 1. 讀設定，不輸出設定

- **讀取** 源格式的 preamble / 設定區塊（LaTeX `\newcommand`、`\definecolor`、`\fontsize`）
- **映射** 到內部樣式模型（OOXMLSwift 的 `RunProperties`、`ParagraphProperties`）
- **不輸出** 任何源格式語法到目標文件（DOCX 裡不能出現 `\color{}`、`\fontsize{}` 等文字）

### 2. Heuristic 偵測

當源格式的結構標記不是用明確命令（如 `\section{}`），而是用格式暗示時：

| 格式暗示 | Heuristic 判斷 | 目標格式輸出 |
|---------|--------------|------------|
| `\fontsize{36pt}` + `\bfseries` + 位於 titlepage | 封面主標題 | Heading1 + 大字 + page break |
| `\fontsize{24pt}` + 位於 titlepage | 封面副標題 | Heading2 + 中字 |
| `\begin{titlepage}...\end{titlepage}` | 封面區塊 | 置中段落群 + page break after |
| `\color{gray}` + 短文字 + 括號 | 時間碼 | gray colored run |
| `\fcolorbox` + `◆` 前綴 | 摘要框 | bordered paragraph + shading |

### 3. 設定繼承鏈

LaTeX 的設定有繼承關係，converter 應按以下順序解析：

```
documentclass 預設 → preamble.tex → commands.tex → inline 覆寫
```

具體來說：
1. 解析 `\definecolor` → 建立顏色表（名稱 → RGB hex）
2. 解析 `\newcommand` → 建立命令表（命令名 → 參數 + 格式）
3. 解析 `\fontsize`、`\bfseries`、`\color{}` → 映射到 RunProperties
4. 正文中遇到自訂命令時，查命令表取得格式，套用到 DOCX

### 4. 不假設，要解析

不要在 converter 裡硬編碼「摘要是灰框白底」、「篇名是棕色 24pt」。
應該從 `commands.tex` 的 `\newcommand` 定義中解析出格式，這樣當用戶修改設定時，DOCX 輸出會自動跟著變。

### 5. 適用於所有 converter

| Converter | 設定層來源 | 不該出現在輸出的東西 |
|-----------|---------|-------------------|
| tex-to-docx | `\newcommand`, `\definecolor`, `\fontsize` | LaTeX 命令語法 |
| pdf-to-docx | 字型大小、位置、顏色 | PDF 座標資訊 |
| html-to-word | CSS `<style>`, inline styles | HTML 標籤 |
| md-to-word | YAML frontmatter, `#` heading markers | Markdown 語法 |
| srt-to-html | SRT 時間碼格式 `00:01:23,456 --> ...` | 原始 SRT 格式標記 |
