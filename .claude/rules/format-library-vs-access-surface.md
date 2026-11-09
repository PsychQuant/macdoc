# 函式庫放格式，使用端放取用方式

適用於 macdoc umbrella 下的格式函式庫與它們的使用端：ooxml-swift（含 `OOXMLSwift`、`DocxForm` 等 product）
是函式庫；macdoc CLI 與 che-word-mcp 是使用端。

## 規則

**ooxml-swift 放「格式本身」，可以 `public`。** 指 OOXML 的結構與語意，以及對文件的操作：元素與屬性、
段落與儲存格的分類（例如 `ParagraphKind`）、格線位置、表單整理的操作與它們的拒絕條件、讀寫封裝的限制。
不論誰呼叫，這些都一樣，所以設成 `public` 沒關係。

**使用端放「取用的方式」，不進 ooxml-swift 的 `public` API。** 以下是封閉列舉，只有這四類，
**不得依性質相似類推第五類**：

1. **CLI 的旗標與子命令名稱**，例如 `--field`、`--table-defaults`、`word form apply`。
2. **MCP 的工具名稱與參數名稱**。
3. **格式概念對 1、2 的對照**，例如「`tableField` 段落用 `--field <paraId>` 整理」。邊界：只要對照的
   一端是某個使用端的介面名稱就算，即使另一端是函式庫的 `public` 型別。
4. **告訴人該執行什麼的提示文字**，例如「render 後請跑 `apply --field 0000A002`」。

使用端需要把格式概念接到自己的介面時，在使用端替函式庫的 `public` 型別寫 extension，例如在 MacDocCLI
裡寫 `extension ParagraphKind { var applyOption: ApplyOption? }`。

## 為什麼

1. 函式庫有不只一個使用端，各自的介面名稱不同。macdoc 的 `--field`，在 che-word-mcp 會是 JSON 參數；
   把其中一個使用端的名稱放進函式庫，另一個用不上，而且使用端改名時，函式庫也得跟著發版。
2. `public` 加容易、拿掉難。發版後移除 `public` 是 breaking change，ooxml-swift 又有二十幾個套件依賴；
   先放在使用端，日後真有第二個使用端需要，再加進函式庫，只是 minor 版的新增。
3. 不會悄悄分岔。SwiftPM 套件預設不開 library evolution，函式庫新增一種段落類型時，使用端沒有
   `default` 的 `switch` 會編譯失敗，逼每個使用端決定新類型怎麼對應到自己的介面。

## 觸發過的情境

2026-11-09，PsychQuant/ooxml-swift#238 把 DocxForm 從 macdoc 搬進 ooxml-swift。issue 原本寫
「`ApplyOption` 與 `ParagraphKind.applyOption` 改成 `public`」；它們是段落類型對 macdoc CLI 旗標的
對照（第 3 類），呼叫端只有 macdoc 的 CLI 與 CLI 測試。最後沒有搬進 ooxml-swift，改由
PsychQuant/macdoc#274 移進 MacDocCLI。維護者定下的原則：ooxml-swift 是格式的設定，可以 `public`；
macdoc 裡面寫取用的方式。

## 已知的例外（尚未處理）

- `DocxForm` 的 `FormError` 與 `DocxPackageError` 訊息提到 macdoc CLI 的旗標與命令（第 1、4 類），例如
  `--remove-table`、「使用 --force 覆寫」、`macdoc word form classify --grid`。搬遷時維持逐字不變，因為
  macdoc 的 CLI 測試比對這些訊息。處理方式追蹤於 PsychQuant/che-word-mcp#300：MCP 工具要用到這些錯誤時
  一併決定。不要因為它已經在函式庫裡，就把它當成這條規則允許的寫法。

## 跟其他 rule 的關係

- `terminology.md`：format／style／option 的區分是 CLI 的用語；這條規則決定這些用語的程式碼住在哪個 repo。
- `cross-repo-umbrella.md`：搬遷這類跨 repo 的工作照 umbrella pattern 追蹤（例如 macdoc#275）。
