# macdoc 設計哲學

## 核心理念：Streaming Architecture

### 為什麼不用 AST？

傳統文件轉換工具通常會：
1. 讀取整份文件
2. 建立抽象語法樹 (AST)
3. 遍歷 AST 輸出目標格式

macdoc 選擇 **Streaming 模式**，原因是：

### Streaming 如同人類閱讀

```
眼睛看到 → 大腦理解 → 立即反應
   ↓           ↓           ↓
讀到標題   辨識是標題   輸出 "# 標題"
讀到段落   辨識是段落   輸出文字
讀到表格   辨識是表格   輸出 pipe table
```

人不會把整本書讀進腦子裡再開始理解，而是**邊讀邊處理**。
Streaming 架構模擬這個過程：處理完一段就輸出，不需要等整份文件都處理完。

### 優勢

| 特性 | Streaming | AST |
|------|-----------|-----|
| 記憶體 | 只需當前元素 | 需要整份文件 |
| 延遲 | 立即開始輸出 | 等全部解析完 |
| 大檔案 | 適合 | 可能 OOM |
| 實作複雜度 | 低 | 高 |

### 適用場景

Streaming 適合**順序轉換**任務，如：
- Word → Markdown
- HTML → Markdown
- PDF → Markdown

若需要**非順序操作**（如重排章節、交叉引用解析），AST 可能更適合。

---

## 模組化設計

### 分離關注點

```
ooxml-swift           → 讀取 Office 格式（OOXML 解析）     Layer 1: Format
markdown-swift        → 生成 Markdown（格式化、跳脫）       Layer 1: Format
doc-converter-swift   → 轉換器協議（DocumentConverter 等）  Layer 2: Protocol
word-to-md-swift      → Word → Markdown 轉換邏輯           Layer 3: Converter
macdoc / MCP          → 組裝 packages，提供使用者介面       Layer 4: Consumer
```

每個 package 專注單一職責，可獨立開發、測試、重用。
Package 不屬於任何消費者——CLI、MCP、App 是不同的消費者，組合需要的 package。

詳見 [`modular-architecture.md`](modular-architecture.md)。

### 依賴方向

```
Layer 4:  macdoc CLI ──────┬──→ word-to-md-swift ──┬──→ doc-converter-swift
          che-word-mcp ────┘                       ├──→ ooxml-swift
            └──→ ooxml-swift (直接讀寫)             └──→ markdown-swift
```

依賴永遠是 Layer 4 → 3 → 2 → 1，不反向、不跨層。

---

## Markdown 生成哲學

### 為什麼需要 markdown-swift？

Markdown 看似簡單，但細節很多：
- 特殊字符跳脫（`*`, `_`, `|`, `` ` ``, `[`, `]`）
- 表格格式化（對齊、分隔線）
- 清單縮進（巢狀層級）
- 空行規則（段落、標題前後）

集中處理這些規則，避免在每個轉換器中重複實作。

### Streaming-friendly API

```swift
let writer = MarkdownWriter(output: &output)
writer.heading("標題", level: 2)
writer.paragraph("內容")
writer.bulletList(["A", "B"])
```

每個方法直接寫入 output，不累積整份文件。

---

## 設計原則

1. **簡單優先** — 不過度設計，解決當前問題
2. **串流處理** — 邊讀邊輸出，記憶體友好
3. **模組獨立** — 每個 package 可單獨使用
4. **原生 Swift** — 利用 macOS 原生能力，不依賴外部工具
5. **文檔歸屬** — 規範文件跟著對應的實作套件走

---

## 文檔歸屬原則

規範文件應該跟著對應的實作套件走：

| 套件 | 文檔 | 說明 |
|------|------|------|
| `ooxml-swift` | `docs/ooxml-spec/` | OOXML 格式規範 |
| `markdown-swift` | `docs/references.md` | CommonMark / GFM 規範 |
| `macdoc` | `docs/philosophy.md` | 設計哲學與架構 |
| `macdoc` | `docs/functional-correspondence.md` | 轉換映射理論 |
| `macdoc` | `docs/modular-architecture.md` | Package 可重組架構與遷移路徑 |

這樣當其他人使用某個套件時，可以直接參考相關的規範文件，不需要去其他專案找。
