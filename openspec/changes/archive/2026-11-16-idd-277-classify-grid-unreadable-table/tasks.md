## 1. Test

- [x] 1.1 Requirement "Unreadable tables are reported whatever their paragraph ids": add `testClassifyGridNotesAnUnreadableTableWhoseIdsAreAllSkipped` to `Tests/MacDocCLITests/WordFormCommandTests.swift`, carrying the marker `spec-example: docx-form-normalization / hMerge table with an escape-sequence paraId`: it builds the form with a second table whose single `w:hMerge` cell holds one paragraph with the escape-sequence `w14:paraId`, runs `macdoc word form classify --grid`, and asserts exit code 0, the stderr note `note: 第 2 張表格的欄列位置無法判讀`, the stderr count `略過 1 個 w14:paraId`, and no `偽造` or U+001B on stdout. Verification: running `swift test --filter WordFormCommandTests/testClassifyGridNotesAnUnreadableTableWhoseIdsAreAllSkipped` fails before task 2.1 because the unreadable-table note is missing.

## 2. Fix

- [x] 2.1 Requirement "Unreadable tables are reported whatever their paragraph ids": in `MacDoc.Word.Form.Classify.run()` (`Sources/MacDocCLI/MacDoc+Word+Form.swift`), record a paragraph's table as unreadable before the malformed-id skip, and only when `--grid` is given, so a table made only of skipped paragraphs is still named in the stderr note; stdout lines and the skipped-id count stay unchanged. Verification: the test from task 1.1 passes, and `swift test --filter WordFormCommandTests` passes with no other change in results.
