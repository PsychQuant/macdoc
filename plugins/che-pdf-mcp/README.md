# che-pdf-mcp

PDF 文件處理 MCP server — PDFKit 解析與文字提取、Vision OCR（原生 macOS）、圖片/區域擷取、亂碼區域偵測。

## 安裝

```bash
claude plugin marketplace add PsychQuant/macdoc
claude plugin install che-pdf-mcp@macdoc
```

Wrapper 會自動從 [GitHub Releases](https://github.com/PsychQuant/che-pdf-mcp/releases) 下載 release 的 `ChePDFMCP` universal binary 到 `~/bin/`，安裝前與每次啟動時強制驗證 sha256（安裝時）與 Developer ID Application 簽章鏈（Team `6W377FS7BS`）。release 流程含 Apple notarization（wrapper 不重複檢查 notarization）。

## 原始碼

https://github.com/PsychQuant/che-pdf-mcp
