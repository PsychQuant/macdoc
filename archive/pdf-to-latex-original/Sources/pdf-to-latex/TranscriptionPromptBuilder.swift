import Foundation

enum TranscriptionPromptBuilder {
    static func build(for block: BlockRecord) -> String {
        let preview = (block.textPreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let previewSection = preview.isEmpty ? "(無 OCR 預覽)" : preview

        return """
        你正在做數學課本 PDF 的逐塊轉寫。

        任務：
        - 讀取附上的單一 block 圖片
        - 將其內容忠實轉成 LaTeX snippet
        - 不要摘要、不要翻譯、不要補寫不可見內容
        - 輸出必須是符合 schema 的 JSON，且不得使用 Markdown code fence

        規則：
        - `latex` 只能是 snippet，不可包含 documentclass、preamble、\\begin{document}
        - 純文字請輸出可直接放進內文的 LaTeX
        - 若是 display equation，請輸出對應的數學環境或數學內容
        - 若內容主要是圖、示意圖、或你無法可靠辨識，請將 `needsFallback` 設為 true
        - 若部分可辨識但仍有疑慮，可在 `notes` 簡短說明
        - 保留原始大小寫、標點、編號、數學符號

        block metadata:
        - id: \(block.id)
        - type: \(block.type.rawValue)
        - page: \(block.page)

        OCR preview:
        \(previewSection)
        """
    }
}
