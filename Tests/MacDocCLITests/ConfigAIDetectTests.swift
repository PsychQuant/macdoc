import XCTest
import PDFToLaTeXCore
@testable import MacDocCLI

/// PsychQuant/macdoc#226: `config ai detect` 以全新的 `AIConfig()` 覆寫設定檔，
/// 把 `config ocr` 寫入的 host profile、預設 host 與 model 全部打回預設值。
/// 一律以 `--config` 指向暫存檔，不碰使用者真正的 `~/.config/macdoc/config.json`。
final class ConfigAIDetectTests: XCTestCase {

    private func tempConfigPath() -> String {
        FixtureManager.outputPath("macdoc-ai-detect-\(UUID().uuidString).json")
    }

    func testDetectKeepsOCRSettings() throws {
        let configPath = tempConfigPath()
        addTeardownBlock { try? FileManager.default.removeItem(atPath: configPath) }

        for args in [
            ["config", "ocr", "add-host", "kyle", "10.0.0.5:11435", "--config", configPath],
            ["config", "ocr", "set-default", "kyle", "--config", configPath],
            ["config", "ocr", "set-model", "my-ollama-tag", "--config", configPath],
            ["config", "ocr", "set-backend", "mlx", "--config", configPath],
        ] {
            let result = try CLITestHelper.run(args)
            XCTAssertEqual(result.exitCode, 0, "\(args)\nstderr: \(result.stderr)")
        }

        let detect = try CLITestHelper.run(["config", "ai", "detect", "--config", configPath])
        XCTAssertEqual(detect.exitCode, 0, "stderr: \(detect.stderr)")

        let saved = try JSONDecoder().decode(AIConfig.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
        XCTAssertEqual(saved.ocrHosts["kyle"], "10.0.0.5:11435", "detect must not drop OCR host profiles")
        XCTAssertEqual(saved.ocrDefaultHost, "kyle", "detect must not reset the default OCR host")
        XCTAssertEqual(saved.ocrDefaultModel, "my-ollama-tag", "detect must not reset the default OCR model")
        XCTAssertEqual(saved.ocrDefaultBackendOverride, "mlx", "detect must not forget the backend chosen with set-backend")
    }

    /// detect 負責的三個欄位仍然由偵測結果決定（這是命令本身的用途）。
    func testDetectStillRewritesTheFieldsItOwns() throws {
        let configPath = tempConfigPath()
        addTeardownBlock { try? FileManager.default.removeItem(atPath: configPath) }

        var stale = AIConfig()
        stale.available = ["no-such-tool"]
        stale.transcription = "no-such-tool"
        stale.agent = "no-such-tool"
        try stale.save(to: URL(fileURLWithPath: configPath))

        let detect = try CLITestHelper.run(["config", "ai", "detect", "--config", configPath])
        XCTAssertEqual(detect.exitCode, 0, "stderr: \(detect.stderr)")

        let saved = try JSONDecoder().decode(AIConfig.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
        let detected = AIConfig.detect()
        XCTAssertEqual(saved.available, detected.available)
        XCTAssertEqual(saved.transcription, detected.transcription)
        XCTAssertEqual(saved.agent, detected.agent)
        XCTAssertFalse(saved.available.contains("no-such-tool"))
    }

    func testAIListAndSetHonourConfigPath() throws {
        let configPath = tempConfigPath()
        addTeardownBlock { try? FileManager.default.removeItem(atPath: configPath) }

        let set = try CLITestHelper.run(["config", "ai", "set", "agent", "gemini", "--config", configPath])
        XCTAssertEqual(set.exitCode, 0, "stderr: \(set.stderr)")
        let list = try CLITestHelper.run(["config", "ai", "list", "--config", configPath])
        XCTAssertEqual(list.exitCode, 0, "stderr: \(list.stderr)")
        XCTAssertTrue(list.stdout.contains("agent: gemini"), list.stdout)
    }
}
