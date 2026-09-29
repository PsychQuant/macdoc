# 第三方文件：公開出口只准寫「文件」

適用於 macdoc 與其 sibling repo（`ooxml-swift`、`che-word-mcp`、`macdoc` 本身，以及任何
PsychQuant 公開 repo）的**所有公開出口**：issue 與 comment（含標題）、PR、commit message、
程式碼與測試（含註解、識別字、環境變數名）、CHANGELOG、README、spec / openspec、fixture 檔名。

## 規則

處理別人的文件（客戶、學生、合作者、受試者交來的 .docx / .pdf 等）時，公開出口**只能稱它為
「文件」（document）**。讀者不得能由任何一處文字推得**是誰的**、**是哪一類**文件。

以下**只有這 6 類**不得出現，**不得依性質相似類推**；遇到沒列到的東西，先問，不要自己判斷
「應該沒關係」：

1. **人名**：當事人、合作者、審閱者、指導者的姓名、暱稱、拼音或縮寫（含檔名裡的）。
2. **機構與單位**：學校、系所、學位別、公司、研究單位的名稱或縮寫。
3. **文件類別**：**任何說出這是哪一種文件的詞**，中英文皆然。只准寫「文件」。本條刻意不舉
   例——舉例本身就是線索。
4. **私有 repo 的名稱與路徑**：包含 `owner/repo`、issue 連結、本機絕對路徑。改寫成
   `<private-repo>`。
5. **文件內容**：原文摘錄、章節標題、統計數字、各種計數（段落數、物件數）。單一計數看似
   無害，但與其他線索合併就能反推。需要重現時用**合成 fixture**，不用真文件的數字。
6. **可反推身分的情境**：截止日、人與人之間的審閱或指導關係、事件時間線。

## 命名（程式碼也算公開出口）

- fixture、測試、環境變數、函式名**不得用文件類別命名**。用 `document-fixture`、
  `OOXML_LOCAL_DOCUMENT_FIXTURE` 這類中性名。
- 需要區分多份 fixture 時用 `fixture-a` / `fixture-b`，不要用能反推來源的名字。

## 送出前檢查（issue / comment / commit / PR / 檔案）

```bash
git grep -n -I -i -E '<當事人姓名>|<機構名>|<文件類別詞>|<私有 repo 名>' -- .
```

被引用的私有資料若要在 issue 裡交代來由，寫「某文件」＋私有 repo 的 `<private-repo>#N`，
不寫其他描述。

## 已經寫出去了怎麼辦

**編輯 issue / comment 不會移除，只會蓋掉最新版**：公開 repo 的「已編輯」歷史任何人可見，
git 歷史也還在。完整處理是（1）編輯或刪除 issue 與 comment、（2）改寫 git 歷史並 force-push、
（3）向 GitHub Support 申請清除快取的 commit 與 issue view。做法與範圍先告訴使用者，
**刪 issue 與 force-push 屬不可逆動作，須使用者明確同意**。

## 為什麼是規則

2026-09-29，一位外部人士在公開 repo 的 issue 裡看到某位當事人的真名，以及私有 repo 的名稱
與路徑。來源是實作某個 API 時，把觸發需求的真實文件情境**逐字**寫進 issue、
CHANGELOG、spec 與測試註解——每一處單看都「只是在交代背景」。多個公開 repo 的 issue、
檔案與 git 歷史都受影響。

背景交代（「為什麼需要這個 API」）要用**合成情境**寫，不要用真實情境。

## 跟其他規則的關係

- 全域 `Git 隱私邊界`：原始第三方逐字內容不進 remote。本條是它在**公開 repo 的具體化**——
  連「這是誰的、哪一類文件」的**描述**也不進 remote，不只逐字內容。
- [`heuristic-output.md`](heuristic-output.md)：converter 輸出不得洩漏源格式語法；本條是
  文件**來源資訊**不得洩漏到公開出口的對應紀律。
