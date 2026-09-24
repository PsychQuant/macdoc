import XCTest
import PDFToLaTeXCore
@testable import MacDocCLI

/// PsychQuant/pdf-to-latex-swift#11 接到 macdoc：`pdf ocr` 的 `--mode` 優先序改為
/// 「明確給的 flag > `config ocr set-backend` 明確設定的值 > 內建 local」。
///
/// 只讀 `AIConfig.ocrDefaultBackendOverride`，不讀舊的 `ocrDefaultBackend`：後者在
/// struct 預設值就是 "ollama"，任何呼叫過 `save()` 的無關命令都會把它寫進設定檔，
/// 分不出是不是使用者選的。
final class PDFOCRModeResolutionTests: XCTestCase {

    private struct Boom: Error {}

    private func config(override: String?, legacy: String = "ollama") -> AIConfig {
        var cfg = AIConfig(ocrHosts: ["kyle": "10.0.0.5:11434"], ocrDefaultHost: "kyle", ocrDefaultModel: "my-ollama-tag")
        cfg.ocrDefaultBackend = legacy
        cfg.ocrDefaultBackendOverride = override
        return cfg
    }

    private func resolve(mode: String?, config: @escaping () throws -> AIConfig) throws
        -> (mode: PageOCRRunner.Mode, model: String, warnings: [String]) {
        var warnings: [String] = []
        let (runnerMode, model) = try MacDoc.PDF.OCRPages.resolveRunSettings(
            mode: mode, host: nil, model: nil, loadConfig: config, warn: { warnings.append($0) })
        return (runnerMode, model, warnings)
    }

    func testNoFlagUsesTheExplicitlySetOllamaBackend() throws {
        let r = try resolve(mode: nil) { self.config(override: "ollama") }
        guard case .ollama(let host) = r.mode else { return XCTFail("expected .ollama, got \(r.mode)") }
        XCTAssertEqual(host, "10.0.0.5:11434")
        XCTAssertEqual(r.model, "my-ollama-tag")
        XCTAssertEqual(r.warnings, [])
    }

    func testNoFlagMapsMlxToLocal() throws {
        let r = try resolve(mode: nil) { self.config(override: "mlx") }
        guard case .local = r.mode else { return XCTFail("expected .local, got \(r.mode)") }
        XCTAssertEqual(r.model, MacDoc.PDF.OCRPages.defaultLocalModel)
    }

    /// #11 的核心：舊欄位是 "ollama"（無關命令寫入的 struct 預設值），但使用者從未
    /// 經由 set-backend 設定過，預設模式必須維持 local。
    func testNoFlagIgnoresTheLegacyBackendField() throws {
        let r = try resolve(mode: nil) { self.config(override: nil, legacy: "ollama") }
        guard case .local = r.mode else { return XCTFail("legacy ocrDefaultBackend must not switch the default to ollama, got \(r.mode)") }
        XCTAssertEqual(r.warnings, [])
    }

    func testExplicitFlagWinsOverTheConfiguredBackend() throws {
        var loadWasCalled = false
        let r = try resolve(mode: "local") { loadWasCalled = true; return self.config(override: "ollama") }
        guard case .local = r.mode else { return XCTFail("expected .local, got \(r.mode)") }
        XCTAssertFalse(loadWasCalled, "--mode local must never read the config")
    }

    /// 沒給 --mode 時要讀設定檔，但壞掉的設定檔不能讓預設模式失敗（#218 Codex R1 #3），
    /// 也不能靜默：退回 local 並警告。
    func testNoFlagWithUnreadableConfigFallsBackToLocalAndWarns() throws {
        let r = try resolve(mode: nil) { throw Boom() }
        guard case .local = r.mode else { return XCTFail("expected .local, got \(r.mode)") }
        XCTAssertEqual(r.warnings.count, 1)
        XCTAssertTrue(r.warnings[0].contains("local"), r.warnings[0])
    }

    func testNoFlagWithUnknownConfiguredBackendFallsBackToLocalAndWarns() throws {
        let r = try resolve(mode: nil) { self.config(override: "tesseract") }
        guard case .local = r.mode else { return XCTFail("expected .local, got \(r.mode)") }
        XCTAssertEqual(r.warnings.count, 1)
        XCTAssertTrue(r.warnings[0].contains("tesseract"), r.warnings[0])
    }

    func testUnknownModeFlagIsRejected() throws {
        XCTAssertThrowsError(try resolve(mode: "tesseract") { self.config(override: nil) })
    }

    func testSetBackendRecordsTheExplicitChoice() throws {
        let configPath = FixtureManager.outputPath("macdoc-set-backend-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: configPath) }

        let set = try CLITestHelper.run(["config", "ocr", "set-backend", "mlx", "--config", configPath])
        XCTAssertEqual(set.exitCode, 0, "stderr: \(set.stderr)")
        let saved = try JSONDecoder().decode(AIConfig.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
        XCTAssertEqual(saved.ocrDefaultBackendOverride, "mlx")
        XCTAssertEqual(saved.ocrDefaultBackend, "mlx", "the legacy field stays in sync for older readers")

        let list = try CLITestHelper.run(["config", "ocr", "list", "--config", configPath])
        XCTAssertTrue(list.stdout.contains("backend: mlx"), list.stdout)
    }

    func testListSaysWhenNoBackendWasChosen() throws {
        let configPath = FixtureManager.outputPath("macdoc-list-backend-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: configPath) }
        try AIConfig().save(to: URL(fileURLWithPath: configPath))

        let list = try CLITestHelper.run(["config", "ocr", "list", "--config", configPath])
        XCTAssertEqual(list.exitCode, 0, "stderr: \(list.stderr)")
        XCTAssertFalse(list.stdout.contains("backend: ollama"), "an unset backend must not be shown as ollama: \(list.stdout)")
        XCTAssertTrue(list.stdout.contains("未設定"), list.stdout)
    }
}
