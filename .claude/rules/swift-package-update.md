# Swift Package 依賴更新流程

當更新本地 Swift Package 依賴（如 ooxml-swift、marker-swift 等）時，必須遵循以下流程：

## 更新步驟

### 1. 在本地套件目錄提交更改
```bash
cd /path/to/local-package  # 例如 ooxml-swift
git add .
git commit -m "描述更改內容"
```

### 2. 推送到遠端倉庫
```bash
git push origin main  # 或對應的分支
```

### 3. 在主專案更新依賴快取
```bash
cd /path/to/main-project  # 例如 macdoc
swift package update      # 更新所有依賴
# 或指定特定套件
swift package update ooxml-swift
```

### 4. 清除建構快取（如有需要）
```bash
swift package clean
swift build
```

## 重要提醒

- **不要**只在本地修改後直接編譯主專案，這樣 Swift Package Manager 不會偵測到更新
- 本地套件的更改必須先 commit + push，主專案才能正確拉取最新版本
- 如果使用 `path:` 本地依賴，則不需要 push，但仍建議 commit 以追蹤版本

## 本專案的套件依賴

| 套件 | 依賴方式 | 路徑/倉庫 |
|------|----------|----------|
| ooxml-swift | `path:` 本地路徑 | `../packages/ooxml-swift` |
| markdown-swift | `path:` 本地路徑 | `../packages/markdown-swift` |
| marker-swift | `path:` 本地路徑 | `../packages/marker-swift` |

## 專案結構

```
docs_processing/
├── macdoc/                    # 主專案 CLI
├── packages/                  # 檔案格式解析套件
│   ├── markdown-swift/        # Markdown 生成
│   ├── marker-swift/          # 圖片分類
│   ├── ooxml-swift/           # OOXML 解析
│   └── surya-swift/           # OCR 套件
└── conversation_logs/         # Claude 對話記錄
```

## 本專案的更新流程（使用 path: 本地依賴）

由於本專案使用 `path:` 本地路徑依賴，更新流程如下：

### 1. 在本地套件目錄修改並提交
```bash
cd ../packages/ooxml-swift  # 進入套件目錄
# 修改程式碼...
git add .
git commit -m "feat: 描述更改"
git push origin main
```

### 2. 在主專案清除快取並重新編譯
```bash
cd ../macdoc  # 回到主專案
swift package clean  # 清除快取
swift build          # 重新編譯
```

**注意**：使用 `path:` 依賴時，Swift Package Manager 會直接讀取本地目錄的程式碼，不需要執行 `swift package update`。但建議清除快取以確保使用最新版本。
