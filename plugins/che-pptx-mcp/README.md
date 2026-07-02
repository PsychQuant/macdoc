# che-pptx-mcp

PowerPoint (.pptx) MCP server — PresentationML 解析與生成：slides、shapes、tables、notes、theme、markdown 匯出。

## 安裝

```bash
claude plugin marketplace add PsychQuant/macdoc
claude plugin install che-pptx-mcp@macdoc
```

Wrapper 會自動從 [GitHub Releases](https://github.com/PsychQuant/che-pptx-mcp/releases) 下載 release 的 `ChePPTXMCP` universal binary 到 `~/bin/`，安裝前與每次啟動時強制驗證 sha256（安裝時）與 Developer ID Application 簽章鏈（Team `6W377FS7BS`）。release 流程含 Apple notarization（wrapper 不重複檢查 notarization）。

## 原始碼

https://github.com/PsychQuant/che-pptx-mcp
