import ArgumentParser
import Foundation

extension MacDoc {
    /// Deprecation shim（macdoc#145，2026-08-07）。
    ///
    /// 通用文字辨識的所有權歸 bestOCR（PsychQuant/bestOCR）單點：引擎選擇、
    /// 版本紀錄、evidence 慣例都在那邊維護。本子命令原本自帶完整 OCR 路徑
    /// （ollama/mlx backend、glm-ocr 模型管理），與 bestOCR 完全重疊——同一台
    /// 機器兩套入口各自演進，最後一定分岔。
    ///
    /// 保留 shim 而非直接移除：既有腳本呼叫 `macdoc ocr` 時拿到明確的遷移
    /// 指引與非零退出碼，而不是 `unknown subcommand`。下一個 major 版整個刪除。
    ///
    /// 注意：pdf-to-latex 管線內部的頁級 OCR（PageOCRRunner）不在此列——那是
    /// 管線零件不是通用辨識入口，其委派 bestOCR 屬第二期，前置是
    /// PsychQuant/bestOCR#55 定義的委派介面。
    struct OCR: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ocr",
            abstract: "（已移除）文字辨識改用 bestocr — PsychQuant/bestOCR"
        )

        @Argument(parsing: .allUnrecognized, help: .hidden)
        var ignored: [String] = []

        func run() async throws {
            let message = """
            `macdoc ocr` 已移除（macdoc#145）。

            文字辨識改用 bestOCR：
              bestocr ocr <input>            # 單檔 OCR
              bestocr recommend              # 不確定用哪個引擎時
              bestocr consensus <input>      # 高價值文件的多引擎互核

            安裝與說明：https://github.com/PsychQuant/bestOCR
            """
            FileHandle.standardError.write(Data((message + "\n").utf8))
            throw ExitCode(2)
        }
    }
}
