# Embedded DSL Spec Pattern 原則

## 核心理念

> **替 embedded DSL 寫 Spectra spec 時，用 Requirements + Scenarios + SBE Examples + 非規範 composition tree。不要用 EBNF / PEG / BNF / ABNF。**

Embedded DSL（host language 的編譯器在做語法 enforcement，例如 Swift `@resultBuilder`）沒有獨立 parser 可以對應 EBNF production rule。硬寫 EBNF 等於替「不存在的 parser」訂規格，讀者會誤以為有 parser 可以拿來測，實際上 reverse-direction transcoder 才是真正的測試對象——而 transcoder 該被 testable Scenarios + 帶 GIVEN/WHEN/THEN 的 SBE Examples 規範。

這個 rule 把 `mdocx-grammar` spec（reference implementation，住在 `openspec/specs/mdocx-grammar/spec.md`）proven out 的 pattern 寫下來，避免下一個寫 embedded DSL spec 的人 default 到 EBNF。

## 第一步：分類 DSL — embedded 還是 external

設計新 DSL spec 的第一個動作不是寫 Requirement，是分類。判準是 binary 的：

| 問題 | Embedded | External |
|------|----------|----------|
| 誰在 enforce 語法？ | Host language compiler（type system / result builder / macro） | 自帶 parser（hand-written / generator-built）|
| 有沒有獨立的 parser 跑在 runtime / build time？ | 沒有 | 有 |
| 語法錯誤怎麼被發現？ | Compile error | Parse error |

**本 rule 只 cover embedded DSL**。External DSL（自帶 parser，例如 SQL、regex、`.bib`、自訂 config 語法）的 spec 寫法不在 scope，那類 spec 用 EBNF / PEG / parser-generator 自己的輸入格式都 OK，不受本 rule 約束。

### 分類對照表

| 候選 DSL | 分類 | 理由 |
|---------|------|------|
| Swift `@resultBuilder` for `.mdocx` | Embedded | Swift 編譯器透過 type checker enforce nesting |
| Swift macro 展開到 typed AST | Embedded | Swift 編譯器在 compile time 驗證展開結果 |
| TypeScript JSX-style component tree | Embedded | TS 編譯器 enforce props 跟 children 的 type |
| 純文字格式 + 自寫 recursive-descent parser | External | Parser 才是語法權威，跑在 parse time |
| String literal 裡的 mini-language（regex、SQL、glob）| External | String 內容自己有 parser，跟 host 無關 |
| YAML / JSON config + schema 驗證 | External | YAML / JSON parser 才是語法權威 |

**判斷後動作**：
- 分類 = embedded → 繼續看下面三個 section（spec 四要素、composition tree、cross-reference）
- 分類 = external → 退出本 rule，依 parser-generator 慣例寫 spec

## Embedded DSL spec 的四個必要元素

確認分類是 embedded 之後，capability spec（`openspec/specs/<capability>/spec.md`）SHALL 包含四個元素：

| 元素 | 位置 | 形式 | 數量 |
|------|------|------|------|
| **Requirements** | `spec.md` | `### Requirement: <name>` + 規範語言（SHALL / MUST）| 每個鎖定的 grammar decision 一個 |
| **Scenarios** | `spec.md`，每個 Requirement 下 | `#### Scenario: <name>` + WHEN / THEN | 每個 Requirement 至少一個 |
| **SBE Examples** | `spec.md`，每個非平凡 Scenario 下 | `##### Example: <name>` + GIVEN / WHEN / THEN（具體值或表格）| 非平凡 Requirement 至少一個 |
| **Composition tree** | `design.md`（**不**在 spec.md）| ASCII 視覺化，section heading 例如「Grammar reference (composition tree)」| 整份 spec 一棵 |

**「非平凡」定義**：Requirement 涉及 data transformation、ordering、結構組合、boundary condition 時算非平凡，要附 SBE Example。純 prohibition scenario（「X 不會被接受」）不算非平凡，可以不附 Example。

### EBNF / PEG / BNF / ABNF 禁令

Embedded DSL 的 spec 跟 design **SHALL NOT** 使用 EBNF、PEG、BNF、ABNF 或任何 context-free grammar production rule notation。

**唯一例外**：embedded DSL 接受一個 string literal，其內容由獨立的 mini-language parser 處理（例如查詢表達式、日期格式、regex pattern）。在這個 case 下，EBNF 可以用來規範**那段 string 的內容**，但 **MUST 明確標出範圍**，不能 leak 到 embedded DSL 的結構性 grammar。

```
✗ 禁止（embedded DSL 結構性 grammar 用 EBNF）：
  WordDocument ::= Section+
  Section ::= Paragraph | Table | ...

✓ 允許（mini-language 內容用 EBNF）：
  // The following EBNF describes the contents of the `where:` string literal
  // accepted by `Query(where: "...")`. It does NOT describe the embedded DSL.
  expression ::= term (("AND" | "OR") term)*
  term ::= identifier ("=" | "!=") value
```

### 為什麼是這四個元素

- **Requirements + Scenarios** 是 Spectra 表達 normative 行為的標準形式（`OOXML library design principles` 等其他 spec 也用同形式）
- **SBE Examples** 把抽象的 Scenario 變成可參數化的 test fixture（一個 Example 行 = 一個 test case）。Embedded DSL 沒有 parser test，但 reverse-direction transcoder 跟 round-trip equality 需要具體值
- **Composition tree** 補 Requirements 列表看不到的鳥瞰視角——「哪個元素能裝在哪個元素裡」這種結構性問題，在分散的 Requirement 之間 reverse-engineer 很費力，一棵樹一目了然
- **EBNF 不在 list 裡**，因為 embedded DSL 沒 parser；EBNF 替「不存在的 parser」訂規格，誤導讀者，且 reverse-direction transcoder 無法用 EBNF 來測（要的是 GIVEN OOXML → THEN DSL source 的 1:1 mapping，不是 parse validity）

## Composition tree notation 慣例

Composition tree 住在 `design.md`（**不**在 spec.md，因為 spec.md 是 normative SHALL/MUST 語氣，混入非規範視覺化會稀釋規範語氣）。所有 embedded DSL 的 tree SHALL 用以下統一 notation，避免每份 spec 自己發明寫法：

| 寫法 | 意思 |
|------|------|
| `[A \| B]*` | 零個或多個 child，每個是 A 或 B |
| `[X]+` | 一個或多個 X child |
| `→`（容器名跟內容之間）| Container body / 「expands to」 |
| `└─`（filesystem-tree style 前綴）| Child element nested 在 parent 底下 |

每個節點 SHALL 標註：
- **Leaf vs container**：leaf 寫「leaf (no children, no text)」；container 寫「container → [legal child set]」
- **Reading hints**：非顯而易見的節點（例如 DSL 層存在但 serialise 後消失的 container），SHALL 在 tree 下方加一行 cross-reference 指向同 design.md 裡解釋該節點的 Decision 或 Open Item

### 範例（取自 `mdocx-grammar` design.md）

```
WordDocument                                       (top-level result builder entry)
  └─ [Section]+                                    (one or more required)
       └─ [Paragraph | Table | Hyperlink | Bookmark | WordComponent]*
            ├─ Paragraph body : [String | Run | Tab | Break | NoBreakHyphen | Hyperlink | Bookmark]*
            │                   (String literal → implicit unstyled Run)
            ├─ Run             : leaf  (text + optional format flags)
            └─ Table           → [TableRow]+
                                  └─ TableCell  → [Paragraph]+
```

**Reading hints**（範例下方）：
- `Section` 為什麼是 container，但 OOXML 用 marker pattern？→ 見 Decision 6
- 為什麼 String literal 不需要 explicit `Run(...)` wrapper？→ 見 Decision 1（implicit string-to-Run）

### 禁止使用的形式

| 不要用 | 為什麼 |
|-------|-------|
| Mermaid diagram | Markdown viewer 渲染不一致，貼到 AI prompt 不乾淨 |
| Graphviz / SVG embed | 同上，且 binary diff 在 git 不友善 |
| EBNF production rule（即使叫它「tree」）| 違反 spec composition 規則，重新引入 parser-grammar mental model |

ASCII 是必須的：跨 markdown viewer 渲染一致、貼進 AI prompt 乾淨、git diff 直接是純文字。

## Cross-reference 雙向契約

Rule 沒人讀就沒用。Embedded DSL 設計者的 entry point 通常**不是**這份 rule 本身，而是：
- 「我要新副檔名」→ 找 `.claude/rules/extension-first-dsl.md`
- 「Swift script 要長怎樣」→ 找 narrative design doc（例如 `docs/swift-as-document-source.md` for `.mdocx`）
- 「之前那個 DSL spec 怎麼寫的」→ 找 reference implementation spec（首批是 `mdocx-grammar`）

所以 cross-reference SHALL 雙向設計：

### 引入新 embedded DSL change MUST 更新的對象

| 對象 | 動作 |
|------|------|
| `.claude/rules/extension-first-dsl.md` 「已註冊副檔名」表格 | 加一 row，連到新 capability spec |
| Narrative design doc（如果先寫了）| 在介紹該 DSL 表面的章節加 link 指到新 capability spec |

### 新 capability spec MUST 反向 link 到的對象

| 對象 | 動作 |
|------|------|
| `.claude/rules/extension-first-dsl.md` | 在 spec 開頭 note 區提及「extension contract 見 extension-first-dsl」 |
| `.claude/rules/embedded-dsl-spec-pattern.md`（本 rule）| 在 spec 開頭 note 區提及「spec shape 遵循 embedded-dsl-spec-pattern」 |
| 上一份 reference implementation spec | 在 spec 開頭 note 區 link 到上一份作為 worked example（首批 = `mdocx-grammar`）|

### 完整 cross-reference graph 範例

假設新 embedded DSL `.mxyz`，capability `xyz-grammar`，narrative doc `docs/swift-as-xyz-source.md`：

```
extension-first-dsl.md (table row for .mxyz)
  ├──→ docs/swift-as-xyz-source.md
  └──→ specs/xyz-grammar/spec.md

docs/swift-as-xyz-source.md (intro section)
  └──→ specs/xyz-grammar/spec.md

specs/xyz-grammar/spec.md (header note)
  ├──→ .claude/rules/extension-first-dsl.md
  ├──→ .claude/rules/embedded-dsl-spec-pattern.md
  └──→ specs/mdocx-grammar/spec.md  (previous reference impl)
```

走完這個 graph，作者從任一 entry point（rule、narrative、現有 spec）都能順著 link 找到完整 context。

## 跟其他 rule 的關係

- `extension-first-dsl.md`：副檔名 contract（**先做**）→ 本 rule：spec shape（**後做**）。順序不能換——沒副檔名就沒 file-association，沒 file-association 就無法談語法 enforcement
- `terminology.md`：format / style / option 區分。Embedded DSL 的副檔名屬於 format
- `cli-design/textutil-compat.md`：CLI 副檔名 dispatch。新 embedded DSL 副檔名要納入 dispatch 邏輯
- `heuristic-output.md`：跟本 rule 不直接相關（converter 輸出 vs DSL 輸入）
- `native-macos-compat.md`：跟本 rule 不直接相關

## 反例 — 為什麼這個規則存在

**反例 A**：假想場景——替 `.mdocx` spec 寫 EBNF：
```
WordDocument ::= Section+
Section ::= Paragraph | Table | Hyperlink | Bookmark | WordComponent
Paragraph ::= (String | Run | Tab | Break | NoBreakHyphen | Hyperlink | Bookmark)*
```
**問題**：
- Swift compiler 才是 enforcer，沒有獨立 parser 對應這份 EBNF
- Reverse direction（OOXML → Swift source）的測試對象是 transcoder，不是 parser；EBNF 無法表達「GIVEN `<w:r>` with no rPr THEN emit String literal」這種 1:1 mapping
- 讀者誤以為有 parser 可以 fuzz，實際上要 fuzz 的是 result builder 展開行為
- 維護成本：grammar 變動時要同時改 Swift code + EBNF + tests，三套真理源頭

**正解（`mdocx-grammar` 採用的）**：Requirements + Scenarios + SBE Examples 描述行為，composition tree 視覺化結構，Swift code 本身就是 parser。

**反例 B**：假想場景——替未來 `.mbib` spec 用 EBNF。
- 如果 `.mbib` 還是 embedded DSL（Swift result builder 包裝 BibLaTeX entries）→ 違反本 rule
- 如果 `.mbib` 是 external DSL（直接拿 `.bib` 文字格式 + 自寫 parser）→ 不在本 rule scope，EBNF OK

判斷再次回到分類：先問「Swift compiler 是不是語法 enforcer？」
