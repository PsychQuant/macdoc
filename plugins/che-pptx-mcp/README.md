# che-pptx-mcp

PowerPoint (.pptx) MCP server — PresentationML 解析與生成：slides、shapes、tables、notes、theme、markdown 匯出。

## 安裝

```bash
claude plugin marketplace add PsychQuant/macdoc
claude plugin install che-pptx-mcp@macdoc
```

## 使用方式

安裝後可由 `che-pptx-mcp` skill 取得具名工具流程、Direct／Session 模式、索引與 EMU 慣例：

`plugins/che-pptx-mcp/skills/che-pptx-mcp/SKILL.md`

目前可讀寫 slides、shapes、tables、images、notes、theme，並匯出 Markdown。尚未提供 PDF 匯出、投影片 render／PNG preview 或 cm 幾何工具；`export_image` 只匯出簡報內嵌圖片，不是投影片預覽。

Wrapper 會自動從 [GitHub Releases](https://github.com/PsychQuant/che-pptx-mcp/releases) 下載 release 的 `ChePPTXMCP` universal binary 到 plugin 層級的 `.bin-cache/`（跨 marketplace 隔離、跨版本持久），安裝前與每次啟動時強制驗證 sha256（安裝時）與 Developer ID Application 簽章鏈（Team `6W377FS7BS`）。release 流程含 Apple notarization（wrapper 不重複檢查 notarization）。

## 原始碼

https://github.com/PsychQuant/che-pptx-mcp
