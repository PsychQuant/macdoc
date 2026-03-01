# ADR: MCP 轉換功能委託 CLI 執行

> **狀態**：Accepted
> **日期**：2026-02-28
> **關聯**：[modular-architecture.md](modular-architecture.md)、[lossless-conversion.md](lossless-conversion.md)

## Context

che-word-mcp 的 `export_markdown` tool 需要 Word → Markdown 轉換功能。
目前的做法是在 che-word-mcp 的 `Package.swift` 中直接依賴 `word-to-md-swift`，在程式碼中呼叫 `WordConverter` API。

這造成以下問題：

1. **API 維護成本高**：`word-to-md-swift` 的 API 每次改動（新增參數、改簽章），che-word-mcp 都要跟著改
2. **重複消費者**：macdoc CLI 和 che-word-mcp 都是 `word-to-md-swift` 的消費者，兩邊都要維護相同的參數對應邏輯
3. **依賴鏈深**：che-word-mcp → word-to-md-swift → doc-converter-swift + ooxml-swift + markdown-swift，發布一個版本要先發布整條鏈
4. **Tier 升級困難**：要支援 Tier 2/3（圖片提取、metadata sidecar），MCP 側要跟著加 `FidelityTier`、`figuresDirectory`、`metadataOutput` 等參數，等於把 `ConversionOptions` 的每個欄位都鏡像一次

## Decision

**che-word-mcp 的轉換功能改為呼叫 `macdoc` CLI binary。**

```
之前：
  che-word-mcp → import word-to-md-swift → WordConverter.convertToString(doc, options)

之後：
  che-word-mcp → save temp.docx → exec `macdoc word temp.docx -o output.md` → read output
```

macdoc CLI 成為 Word → Markdown 轉換的**唯一入口**。MCP 只做 thin wrapper。

## 實作方式

### MCP 側（che-word-mcp）

```swift
// export_markdown handler 改為：
func exportMarkdown(args: [String: Value]) async throws -> String {
    // 1. 取得已開啟的文件，存成暫存 .docx
    let tempDocx = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".docx")
    try doc.save(to: tempDocx)

    // 2. 組合 macdoc CLI 命令
    var arguments = ["word", tempDocx.path]
    if let fidelity = args["fidelity"]?.stringValue, fidelity == "marker" {
        arguments += ["--marker"]
    }
    if args["include_frontmatter"]?.boolValue == true {
        arguments += ["--frontmatter"]
    }
    // ... 其他參數對應

    // 3. 呼叫 macdoc binary
    let process = Process()
    process.executableURL = URL(fileURLWithPath: macdocPath)
    process.arguments = arguments
    // stdout → markdown 輸出, 或 -o 指定輸出路徑

    // 4. 讀取結果，清理暫存檔
    let markdown = // read from stdout or output file
    try? FileManager.default.removeItem(at: tempDocx)
    return markdown
}
```

### CLI 側（macdoc）

macdoc CLI 已經具備完整功能，不需修改：

```bash
# 標準模式（Tier 1）
macdoc word input.docx -o output.md

# 帶 frontmatter
macdoc word input.docx --frontmatter -o output.md

# Marker 模式（Tier 2/3: MD + images + metadata）
macdoc word input.docx --marker -o output_dir/
```

未來 macdoc 新增任何轉換選項（例如 `--hard-breaks`、`--html-extensions`），MCP 只要新增對應的 CLI 參數傳遞即可，不需要重新編譯依賴鏈。

## 依賴圖變化

### 之前

```
che-word-mcp
├── ooxml-swift          ← Word 讀寫（145 tools）
└── word-to-md-swift     ← export_markdown（library 嵌入）
    ├── doc-converter-swift
    ├── ooxml-swift
    └── markdown-swift
```

### 之後

```
che-word-mcp
├── ooxml-swift          ← Word 讀寫（145 tools）
└── macdoc (binary)      ← export_markdown（CLI 呼叫）

macdoc CLI
├── word-to-md-swift     ← 標準轉換
├── marker-swift         ← Marker 模式
└── ArgumentParser
```

che-word-mcp 的 Swift 依賴從 3 個降為 1 個（僅 `ooxml-swift`）。

## 前提條件

- `macdoc` binary 必須在系統上可用（安裝到 `~/bin/macdoc` 或 PATH 中）
- che-word-mcp 需要知道 `macdoc` 的路徑（可透過環境變數 `MACDOC_PATH` 或預設路徑）

## 優缺點

### 優點

| 項目 | 說明 |
|------|------|
| **單一真相來源** | 轉換邏輯只在 macdoc 維護一處，MCP 不再鏡像 API |
| **發布獨立** | 升級 macdoc 不需要重新編譯 che-word-mcp |
| **依賴鏈簡化** | che-word-mcp 只依賴 ooxml-swift，不再拉整條轉換鏈 |
| **功能自動跟進** | macdoc 新增的所有轉換選項，MCP 只要傳 CLI 參數即可 |
| **Binary 瘦身** | che-word-mcp binary 更小（少了 markdown-swift、doc-converter-swift） |
| **效能上限更高** | CLI 可用 streaming 架構（O(1) 記憶體），MCP 做不到（見下方說明） |

### 效能：MCP 記憶體常駐 vs CLI Streaming

che-word-mcp 為了支援 145 個 OOXML 讀寫工具，**必須將整份 `WordDocument` 載入記憶體**——
這是隨機存取（插入段落、改格式、合併儲存格）的必然代價。
當 `export_markdown` 也在 MCP 程序內執行時，它被迫在已載入的記憶體物件上操作，
無法利用 streaming 演算法優化。

相比之下，macdoc CLI 是**獨立程序**，可以：

- **Streaming 轉換**：逐段讀取 .docx XML → 逐段產出 Markdown，記憶體用量 O(1)
- **平行處理**：圖片提取、metadata 收集可與 MD 生成平行
- **提前終止**：如果只需要前 N 段，不用解析整份文件

```
MCP (記憶體模式):     [完整載入 WordDocument] → [遍歷所有段落] → [輸出 MD]
                      ▲ 記憶體 = O(n)，無法優化

CLI (streaming 模式): [逐段讀取 XML] → [逐段輸出 MD] → [完成]
                      ▲ 記憶體 = O(1)，可平行、可提前終止
```

對大型文件（100+ 頁），CLI 路徑的效能優勢尤其明顯。

### 缺點

| 項目 | 說明 | 緩解方式 |
|------|------|---------|
| **額外 I/O** | 需寫暫存 .docx + 讀輸出 .md | 毫秒級，MCP 場景可接受 |
| **Process spawn** | 每次轉換啟動一個子程序 | macOS fork 開銷極小 |
| **部署依賴** | 需要 `macdoc` binary 在系統上 | 統一安裝到 `~/bin/` |
| **錯誤處理** | 需解析 CLI exit code 和 stderr | macdoc 可提供結構化錯誤輸出 |

## 適用範圍

此決策僅適用於**轉換功能**（`export_markdown` 及未來的 `export_pdf` 等）。
che-word-mcp 的 Word 讀寫功能（145 個 OOXML 工具）仍然直接依賴 `ooxml-swift` library，不受影響。

## 通用原則

> **Library 用於需要記憶體內共享狀態的緊密整合。**
> **CLI 用於功能完整且獨立的單元操作。**
>
> 文件轉換是典型的「輸入→處理→輸出」，沒有需要共享的中間狀態，
> 天然適合 CLI 邊界。
