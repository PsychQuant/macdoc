---
description: 規劃新文件格式加入 macdoc 生態系（兩兩直接轉換、package 建立、架構遵循）
argument-hint: <format-name>
allowed-tools: Read, Glob, Grep, Bash(ls:*), Bash(cat:*), Bash(swift:*), AskUserQuestion, Agent, EnterPlanMode, Write, Edit
---

# Add Format — 新增文件格式到 macdoc

將新的文件格式整合進 macdoc 4 層架構。

## 參數

- `$ARGUMENTS` = 格式名稱（如 `html`、`pdf`、`epub`、`latex`）

---

## Phase 0: 讀取現有架構

**必須先讀取以下文件**，理解架構和設計哲學後才能規劃：

```
/Users/che/Developer/macdoc/docs/philosophy.md              — 設計哲學（streaming、兩兩直接轉換）
/Users/che/Developer/macdoc/docs/modular-architecture.md    — 4 層架構、依賴規則、package 分類
/Users/che/Developer/macdoc/docs/functional-correspondence.md — 元素對應表
/Users/che/Developer/macdoc/docs/lossless-conversion.md     — FidelityTier 設計
/Users/che/Developer/macdoc/docs/practical-defaults.md      — Practical Mode（Heading Heuristic、EMF→PNG）
/Users/che/Developer/macdoc/Package.swift                   — 頂層依賴
```

掃描現有 packages：

```bash
ls -d /Users/che/Developer/macdoc/packages/*-swift
ls -d /Users/che/Developer/macdoc/packages/*-to-*-swift 2>/dev/null
```

---

## Phase 1: 確認新格式資訊

用 AskUserQuestion 釐清：

1. **格式名稱**：`$ARGUMENTS`
2. **副檔名**：`.html`、`.htm` 等
3. **讀寫能力**：只讀 / 只寫 / 雙向
4. **已知的 Swift 函式庫**

### 快速參考：Swift 函式庫

| 格式 | 推薦函式庫 | 備註 |
|------|-----------|------|
| HTML | [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML 解析，類似 JSoup |
| PDF | surya-swift（已有） | OCR + layout；寫入可考慮 TPPDF |
| EPUB | [EPUBKit](https://github.com/nicklama/EPUBKit) 或自製 | EPUB 本質是 ZIP + XHTML |
| LaTeX | 自製 parser 或 regex | 結構化文本，可直接解析 |
| RTF | Apple NSAttributedString | macOS 原生 API |
| CSV/TSV | Swift 標準庫 | 主要對應 Table 元素 |

---

## Phase 2: 兩兩轉換路徑規劃

### 核心原則

> **macdoc 不使用 hub format。每組格式之間都建立直接轉換路徑。**
>
> 詳見 `docs/philosophy.md`「為什麼不用 Hub Format」。

將新格式和每個既有格式配對，逐一評估雙向轉換：

| 轉換路徑 | 做 | 不做 | 優先度 | 理由 |
|----------|:--:|:----:|:------:|------|
| `{format}` → 既有格式A | ? | ? | P? | |
| 既有格式A → `{format}` | ? | ? | P? | |
| `{format}` → 既有格式B | ? | ? | P? | |
| ... | | | | |

**不做的合理原因**：
- 只讀格式不能作為 target、只寫格式不能作為 source
- 兩個格式表達能力相差太大，轉換無實用價值
- 優先度太低，日後再做

### 輸出

按優先度排列需要建立的 converter packages。

---

## Phase 3: Package 架構設計

遵循 `docs/modular-architecture.md` 的規則：

### 命名規則

| 類型 | 命名 | 範例 |
|------|------|------|
| Format (Layer 1) | `{format}-swift` | `html-swift` |
| Converter (Layer 3) | `{source}-to-{target}-swift` | `html-to-word-swift` |
| Swift Module | CamelCase | `HTMLSwift`, `HTMLToWordSwift` |

### 依賴規則（不可違反）

- Layer 4 → 3 → 2 → 1，不反向、不跨層
- Converter **不可** import 其他 converter
- Format **不可** import converter
- 每個 Converter 只依賴：source format + target format + `doc-converter-swift`

### 每個 Converter 的結構

```
packages/{source}-to-{target}-swift/
├── Package.swift
├── Sources/{Source}To{Target}Swift/
│   ├── {Source}To{Target}Converter.swift    # 實作 DocumentConverter
│   └── ...
└── Tests/
```

---

## Phase 4: FidelityTier + 元素對應

參考 `docs/functional-correspondence.md` 和 `docs/lossless-conversion.md`。

對每對轉換建立元素對應表，標注資訊損失。

**直接轉換的優勢**：例如 Word→HTML 可以保留顏色、分頁等 Markdown 不支援的元素。如果走 hub（Word→MD→HTML），這些全丟。

---

## Phase 5: 實作順序

使用 EnterPlanMode 輸出完整計畫：

1. **Layer 1**: `{format}-swift`（如需新 Format package）
2. **Layer 3**: 按 Phase 2 優先度逐一實作 converter packages
3. **Layer 4**: CLI 整合（MacDoc.swift 新增 subcommand）
4. **Layer 4**: MCP 整合（如需要）

### 測試策略

- 每個 converter 獨立測試
- Round-trip 測試：A → B → A
- 整合測試：真實文件

---

## Phase 6: 文檔更新

1. `docs/modular-architecture.md` — 新增 package
2. `docs/functional-correspondence.md` — 新增元素對應
3. `/Users/che/Developer/mcp/CLAUDE.md` — 如有新 MCP
