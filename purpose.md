好，那我幫你把決定定錨，並給你一個可立即行動的下一步清單。

⸻

已定錨的命名

✅ Repo 名稱

word-to-md-mac
	•	主體清楚：Word → Markdown
	•	限制後置：macOS
	•	去品牌化、可 fork、可擴展
	•	與你「Swift 城市」的街道命名完全一致

⸻

README 首段（可直接用）

A native macOS Word → Markdown converter written in Swift.
Streaming conversion. No intermediate AST.

（技術細節放 README；名字只負責讓人一眼懂、敢用、敢 fork。）

⸻

立即可做的三步（一天內完成）
	1.	開 repo：word-to-md-mac
	2.	最小功能集（MVP）
	•	Heading styles → # / ## / ###
	•	Paragraph → 空行分隔
	•	Bold / Italic → ** / _
	•	Ordered / Unordered list
	•	Table → pipe table（先不處理合併儲存格）
	3.	嚴格約束
	•	Streaming（逐段輸出）
	•	不建立全文件樹
	•	不做通用 AST / block model

⸻

與你現有成果的關係
	•	che-word-mcp：來源能力（讀 Word 的語意）
	•	word-to-md-mac：城市街道（把語意直接落到 Markdown）
	•	MCP 是地下捷運，不寫進招牌

⸻

之後自然擴展（不用再想命名）
	•	html-to-md-mac
	•	pdf-to-md-mac
	•	word-to-html-mac

街道會自己長出來。

⸻

如果你要，我下一步可以直接幫你：
	•	列出 Word → MD 的事件清單（≤10 個）
	•	給你 Swift CLI 骨架（ArgumentParser + streaming writer）
	•	或幫你寫 測試樣本（對齊 Heading/List/Table）

你只要說要哪一個。