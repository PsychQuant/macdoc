# Extension-First DSL 原則

## 核心理念

> **凡是引入新的 authoring DSL，必須先設計副檔名。副檔名是 contract——它告訴人 + 告訴工具這個檔案是什麼。設計副檔名比實作 DSL 早。**

副檔名不是後綴裝飾。它是一個 file-level 的 type annotation，決定：

- 編輯器怎麼開這個檔案（syntax highlighting、LSP、snippets）
- shell tools / CI / file watcher 怎麼識別（`find -name "*.mdocx"`、file association）
- macdoc CLI / MCP 怎麼 dispatch（看到 `.mdocx` 就走 word DSL pipeline）
- 作者腦袋裡這個檔案的 mental model（看到 `.mdocx` 就知道「這是一份會被 Word 對齊的腳本」）

副檔名有任何不對，這四件事全部錯位。所以**設計 DSL 的第一步是定副檔名，不是寫 builder API**。

## 何時觸發此規則

**觸發**：引入新的 authoring DSL 時。判準是「這個功能會讓使用者寫一種新的、有 hierarchical / declarative 語法的腳本檔」。

| 場景 | 觸發？ | 範例 |
|------|--------|------|
| 新 DSL 用來描述產出物（document、design、config）| ✓ | Word doc 腳本 → `.mdocx` |
| 新格式的 reader/writer，使用者寫的還是該格式原生語法 | ✗ | 新增 `.epub` 支援，使用者寫的就是 ePub HTML |
| 新 CLI 子命令 / flag | ✗ | `macdoc convert --to xyz` |
| 新 MCP tool | ✗ | `mcp__che-word-mcp__do_thing` |
| 純內部 helper / converter / library | ✗ | `MarkerWordConverter` |
| 新的設定檔格式（YAML / JSON config）| 視情況 | 一次性 config 不需要；長期 schema 可考慮 `.macdocrc` 之類 |

判斷公式：**會不會有人開 IDE 寫這個檔案？會 → 開副檔名。不會 → 不開**。

## 設計 DSL 之前：先確認預設作者是誰

> **設計 DSL 的第一個問題不是「語法長什麼樣」而是「誰會寫它」。** 預設作者改變所有後續 trade-off。

|預設作者|看重的|看輕的|連帶設計後果|
|---|---|---|---|
|**人類**|簡潔、直覺、低 verbosity、Markdown-style ergonomics|嚴格 determinism、explicit ID、編譯期驗證|可接受 syntactic sugar、accept 部分 lossy、容忍 multiple parsers|
|**AI**|可預測 (1:1 mapping)、編譯期 feedback、無歧義 syntax、reverse direction 無損|Verbosity（AI 不疲勞）、命名一致性負擔（AI 擅長）、學習曲線（AI 看 codebase 即會）|傾向純 typed builder、嚴格副檔名 dispatch、強制 explicit ID|
|**程式工具**（lint / formatter / generator）|機器可解析 grammar、無 implicit 行為|人類可讀性|傾向 S-expression / JSON / pure data|

設計 DSL **第一份文件**應在 design doc 開頭（或 callout block）明示：「本 DSL 預設作者是 X」。後續所有 trade-off（要不要 Markdown / 要不要 YAML escape hatch / 要不要 implicit ID / 要不要 sugar syntax）都從這個前提推導。

**反例**：v0.x design 文件假設「人類」作者，所以保留 Markdown layer 作 ergonomics。實際上預設作者是 AI（人類只看 / 改不寫），ergonomics 計算翻轉，Markdown layer 變成純粹 determinism risk 而沒有 ergonomics 收益——應該砍掉。`docs/swift-as-document-source.md` §3.5 記錄這個 retroactive correction。

切換預設作者時要 audit：每個 syntax 抉擇是不是還合理？例如「人類為主，AI 也能用」設計，AI 切到主導角色後可能變成「AI 寫得 OK，但因為 Markdown 層的 lossy reverse 導致 AI 無法迭代」。

## 副檔名設計守則

### 1. 短、好認、沒衝突

|好|不好|為什麼|
|---|---|---|
|`.mdocx`|`.macdoc-word-document`|短才能在 shell 裡常用|
|`.mpdf`|`.pdf-script-swift`|前綴一致（`m` = macdoc 品牌），副檔名末段直接是目標格式|
|`.mbib`|`.bibapa`|跟同 family 對齊命名|

跟既有副檔名比對 → 沒撞車（檢查 https://fileinfo.com 或 `man file`）。

### 2. 跟 host 語言的關係明確

兩種主流 pattern：

**Pattern A — 純自訂副檔名**（`.svelte` / `.vue` / `.astro` 走這條）：
- 檔名：`mydoc.mdocx`
- IDE 要設定 `*.mdocx` → swift mode 才有 highlighting
- file association 強：看到副檔名立刻知道是什麼

**Pattern B — Dual extension**（`.tsx` / `.mdx` 走這條）：
- 檔名：`mydoc.mdocx.swift`
- Xcode / SwiftLSP 認 `.swift` → 完整 IDE 支援不用配置
- macdoc CLI / file glob 認 `.mdocx` 部分 → 也能 dispatch

**選 A 還是 B**：
- 如果 DSL 跟 host 語言（Swift）幾乎沒差別、只多了 macros / result builder → **Pattern B**（成本低，IDE 直接用）
- 如果 DSL 加了非 Swift 語法（custom syntax、JSX-style tags）→ **Pattern A**（Swift LSP 不認，反正都要寫 plugin）

macdoc 的所有 DSL 目前都是「Swift + result builder + macros」，沒有非 Swift 語法 → **預設選 Pattern B**。

### 3. 命名 family — `m` prefix + 目標 format 副檔名

公式：`.m<目標 format 的副檔名>`

| 副檔名 | 解讀 | 目標產出 |
|--------|------|---------|
| `.mdocx` | **m**acdoc script that produces `.docx` | Word `.docx` |
| `.mpdf` | **m**acdoc script that produces `.pdf` | PDF `.pdf` |
| `.mbib` | **m**acdoc script that produces `.bib` | BibLaTeX `.bib` |
| `.mpptx` | **m**acdoc script that produces `.pptx` | PowerPoint `.pptx`(如果未來做)|

設計理由：
- `m` prefix = **macdoc** 品牌前綴。不歧義（不像 `w` 可能讀作 Word 或 writable）；macdoc owns 整個 family，不撞既有副檔名（沒主流工具用 `m<format>` pattern）
- 目標 format 嵌在副檔名裡 — `.mdocx` / `.mpptx` / `.mpdf` 不用解釋就知道輸出什麼
- 跟使用者已熟的 `.docx` / `.pptx` / `.pdf` 副檔名押韻，只多一個字母 prefix → 0 認知負擔
- 跟 macdoc 的「DSL = source of truth, target format = artifact」哲學一致：副檔名告訴你「這是 macdoc 用來寫 X 的腳本」

### 4. 副檔名要進文件

**新 DSL 的副檔名落地清單**：

- [ ] 在 `docs/` 寫一份對應的 design doc，標題或開頭明示「這個 DSL 用 `.xdoc` 副檔名」
- [ ] 在 `.claude/rules/cli-design/`（如果牽涉 CLI）或本 rule 文件下方「已註冊副檔名」表格加一行
- [ ] 在 macdoc CLI 加 `--from .xdoc` 或 file-glob dispatch
- [ ] 在 `.gitignore`（如果該 DSL 會產生衍生 artifact）區分原始檔 vs 產物

## 已註冊副檔名

| 副檔名 | 領域 | Pattern | 設計文件 | 狀態 |
|--------|------|---------|---------|------|
| `.mdocx` / `.mdocx.swift` | Word document scripts | B（dual） | `docs/swift-as-document-source.md`（narrative）+ `openspec/specs/mdocx-grammar/spec.md`（normative，archive 後生效；首批 reference implementation of [`embedded-dsl-spec-pattern`](embedded-dsl-spec-pattern.md)）| 規格 locked（Spectra change `mdocx-syntax` apply 中）；implementation 屬 `word-aligned-state-sync` Phase 7 |

未來預定但未開始：

| 副檔名 | 領域 | 觸發時機 |
|--------|------|---------|
| `.mpdf` | PDF document scripts | 把 word-aligned 的 op-log 模式套到 PDF 時 |
| `.mbib` | Bibliography APA scripts | 如果 bib-apa 變成可程式化的排版 DSL（目前是純 converter，不需要）|
| `.mpptx` | PowerPoint document scripts | 套到 pptx-swift 時 |

## 反例 — 為什麼這個規則存在

**反例 A**：v0.x 的 `pdf-to-latex-swift` 直接用 `.tex` 作為 pipeline 中介格式。沒問題，因為使用者寫的就是 LaTeX，不是 macdoc 自訂 DSL。**符合本規則**（不需要新副檔名）。

**反例 B**：假想場景——新增「Word 腳本」功能但沿用 `.swift` 副檔名。後果：
- IDE 看到一個 `.swift` 檔案，不知道是普通 Swift 還是 Word DSL
- `find . -name "*.swift" | grep -v Tests` 撈不出 Word DSL，需要額外 heuristic
- macdoc CLI 不能用副檔名 dispatch，要看檔案內容判斷
- 作者打開檔案要先讀第一行 import 才知道這是什麼

這就是「DSL 沒設計副檔名」的代價——**判別 ambiguous，工具鏈到處要加 sniff 邏輯**。

**反例 C**：v0.x 的 `marker-swift` 輸出是「目錄結構（`.md` + `_meta.json` + `images/`）」。曾經有人提議叫 `.marker` 副檔名包成 zip。**沒做**，因為 marker 不是給人寫的 DSL，是 converter 的輸出產物。「給人寫的 DSL」才需要副檔名 contract，「機器產出的目錄」沒有 IDE 開檔需求，目錄結構就足夠。**符合本規則**（不需要新副檔名）。

## 跟其他 rule 的關係

- [`embedded-dsl-spec-pattern.md`](embedded-dsl-spec-pattern.md)：副檔名定好之後，**寫該 DSL 的 Spectra spec 時走那份 rule**。本 rule 規範 file-level contract，那份 rule 規範 spec-level shape（Requirements + Scenarios + SBE Examples + composition tree，不用 EBNF）
- `terminology.md`：副檔名是 format 的一種表達。新 format 通常對應新 `--to` 值；新 DSL 對應新副檔名（不一定對應新 `--to`，因為 DSL 是輸入端）
- `cli-design/textutil-compat.md`：CLI 命令的副檔名 dispatch 規則（自動偵測 input format）。新 DSL 副檔名要納入該偵測邏輯
- `native-macos-compat.md`：副檔名跟 macOS file association 也綁——要 `lsregister` 註冊 → 雙擊開 macdoc CLI 路徑
