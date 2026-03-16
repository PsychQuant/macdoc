# textutil 語法對映

macdoc 的 `convert` 子命令語法與 macOS 內建 `textutil` 對齊。
使用者如果會用 `textutil`，應該能直覺地使用 `macdoc`。

## textutil → macdoc 對照

```bash
# textutil                          # macdoc
textutil -convert html file.docx    macdoc convert --to html file.docx
textutil -info file.docx            macdoc info file.docx    (planned)
textutil -convert txt -output o.txt macdoc convert --to md --output o.md file.docx
textutil -convert html -stdout      macdoc convert --to html --stdout file.md
```

## 語法差異

| textutil | macdoc | 理由 |
|----------|--------|------|
| `-convert html` | `--to html` | swift-argument-parser 慣例用 `--` long flags |
| `-output file` | `--output file` | 同上 |
| `-format txt` | (自動偵測) | 從副檔名推斷，更簡潔 |
| `-cat` | (不支援) | 合併多檔不在 scope 內 |

## Format 短名

| --to 值 | 全名 | 對應 package |
|---------|------|-------------|
| `md` | Markdown | `word-to-md`, `html-to-md`, `pdf-to-md` |
| `html` | HTML | `md-to-html`, `srt-to-html`, `bib-apa-to-html` |
| `docx` | Word | `md-to-word`, `html-to-word`, `pdf-to-docx` |
| `json` | JSON | `bib-apa-to-json` |
| `latex` | LaTeX | `pdf-to-latex` |
