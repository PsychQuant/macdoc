import XCTest
import PDFToLaTeXCore
@testable import MacDocCLI

/// Coverage for PsychQuant/macdoc#218: `macdoc config ocr` used to write
/// host/model/backend settings that no command ever read (#145 removed the
/// only reader, the top-level `macdoc ocr` shim). `macdoc pdf ocr` now reads
/// them, with priority "explicit flag > `config ocr` setting > built-in
/// default".
///
/// Two layers, deliberately kept separate:
/// - `resolveHost` / `resolveModel` are pure static functions extracted from
///   `OCRPages.run()` so the priority logic can be pinned without running an
///   actual OCR pipeline (which needs a rendered PDF page plus a real MLX
///   model download or a reachable Ollama server — both unavailable and
///   undesirable in a unit test).
/// - `OCRConfigOptionsTests` exercises the real `config ocr` subcommands
///   through the built binary, but always with `--config` pointed at a
///   temporary file — never the user's real `~/.config/macdoc/config.json`.
final class PDFOCRHostModelResolutionTests: XCTestCase {

    private func config(
        ocrHosts: [String: String] = [:],
        ocrDefaultHost: String? = nil,
        ocrDefaultModel: String = "glm-ocr"
    ) -> AIConfig {
        AIConfig(ocrHosts: ocrHosts, ocrDefaultHost: ocrDefaultHost, ocrDefaultModel: ocrDefaultModel)
    }

    // MARK: - resolveHost

    func testExplicitHostWinsOverConfig() {
        let cfg = config(ocrHosts: ["kyle": "10.0.0.5:11434"], ocrDefaultHost: "kyle")
        XCTAssertEqual(
            MacDoc.PDF.OCRPages.resolveHost(explicit: "192.168.1.1:9999", config: cfg),
            "192.168.1.1:9999",
            "an explicit --host that is not a known profile name should be used verbatim"
        )
    }

    func testExplicitHostResolvesAsProfileName() {
        let cfg = config(ocrHosts: ["kyle": "10.0.0.5:11434"])
        XCTAssertEqual(
            MacDoc.PDF.OCRPages.resolveHost(explicit: "kyle", config: cfg),
            "10.0.0.5:11434",
            "an explicit --host matching a profile name should resolve to that profile's address"
        )
    }

    func testMissingHostFallsBackToConfigDefaultProfile() {
        // Exactly the scenario in #218's problem statement: `config ocr
        // add-host kyle …` + `config ocr set-default kyle`, then `pdf ocr`
        // without --host.
        let cfg = config(ocrHosts: ["kyle": "10.0.0.5:11434"], ocrDefaultHost: "kyle")
        XCTAssertEqual(
            MacDoc.PDF.OCRPages.resolveHost(explicit: nil, config: cfg),
            "10.0.0.5:11434"
        )
    }

    func testMissingHostAndMissingConfigFallsBackToBuiltinDefault() {
        let cfg = config()
        XCTAssertEqual(
            MacDoc.PDF.OCRPages.resolveHost(explicit: nil, config: cfg),
            "localhost:11434"
        )
    }

    // MARK: - resolveModel

    func testExplicitModelWinsRegardlessOfMode() {
        XCTAssertEqual(
            MacDoc.PDF.OCRPages.resolveModel(explicit: "custom-model", mode: "ollama", configDefaultModel: "glm-ocr"),
            "custom-model"
        )
        XCTAssertEqual(
            MacDoc.PDF.OCRPages.resolveModel(explicit: "custom-repo", mode: "local", configDefaultModel: "glm-ocr"),
            "custom-repo"
        )
    }

    func testMissingModelInOllamaModeUsesConfigDefault() {
        XCTAssertEqual(
            MacDoc.PDF.OCRPages.resolveModel(explicit: nil, mode: "ollama", configDefaultModel: "my-ollama-tag"),
            "my-ollama-tag"
        )
    }

    func testMissingModelInLocalModeIgnoresConfigAndUsesBuiltinDefault() {
        // Local/MLX model ids (HuggingFace repos) and Ollama model tags are
        // different namespaces; config ocr's default model is documented as
        // being for the ollama backend, so --mode local must never pick it
        // up even if it has been set.
        XCTAssertEqual(
            MacDoc.PDF.OCRPages.resolveModel(explicit: nil, mode: "local", configDefaultModel: "an-ollama-only-tag"),
            MacDoc.PDF.OCRPages.defaultLocalModel
        )
    }

    // MARK: - resolveRunSettings (Codex round-1 finding #3)

    private struct Boom: Error {}

    func testLocalModeNeverLoadsConfig() throws {
        // --mode local (the default) must not depend on `config ocr` at
        // all: it neither reads a host profile nor the default model, so
        // loading the config file at all — let alone one that happens to be
        // unreadable or malformed — must not be able to break it. Proven
        // here by making the loader throw if it's ever called; before this
        // was fixed, `run()` called `configOptions.load()` unconditionally,
        // so this would have failed with `Boom` even for --mode local.
        var loadWasCalled = false
        let (runnerMode, model) = try MacDoc.PDF.OCRPages.resolveRunSettings(
            mode: "local", host: nil, model: nil,
            loadConfig: { loadWasCalled = true; throw Boom() }
        )
        XCTAssertFalse(loadWasCalled, "--mode local must never call the config loader")
        XCTAssertEqual(model, MacDoc.PDF.OCRPages.defaultLocalModel)
        guard case .local = runnerMode else {
            XCTFail("expected .local, got \(runnerMode)")
            return
        }
    }

    func testLocalModeWithExplicitModelStillNeverLoadsConfig() throws {
        var loadWasCalled = false
        let (_, model) = try MacDoc.PDF.OCRPages.resolveRunSettings(
            mode: "local", host: nil, model: "my-explicit-repo",
            loadConfig: { loadWasCalled = true; throw Boom() }
        )
        XCTAssertFalse(loadWasCalled)
        XCTAssertEqual(model, "my-explicit-repo")
    }

    func testOllamaModePropagatesAConfigLoadFailure() {
        // The flip side of the two tests above: --mode ollama genuinely
        // needs the config (for the default host profile and default
        // model), so a load failure there SHOULD surface as an error
        // rather than being silently swallowed or defaulted around.
        XCTAssertThrowsError(try MacDoc.PDF.OCRPages.resolveRunSettings(
            mode: "ollama", host: nil, model: nil,
            loadConfig: { throw Boom() }
        )) { error in
            XCTAssertTrue(error is Boom, "expected the load failure to propagate, got \(error)")
        }
    }

    func testOllamaModeLoadsConfigAndAppliesItsSettings() throws {
        var loadWasCalled = false
        let cfg = config(ocrHosts: ["kyle": "10.0.0.5:11434"], ocrDefaultHost: "kyle", ocrDefaultModel: "my-ollama-tag")
        let (runnerMode, model) = MacDoc.PDF.OCRPages.resolveRunSettings(
            mode: "ollama", host: nil, model: nil,
            loadConfig: { loadWasCalled = true; return cfg }
        )
        XCTAssertTrue(loadWasCalled)
        XCTAssertEqual(model, "my-ollama-tag")
        guard case .ollama(let host) = runnerMode else {
            XCTFail("expected .ollama, got \(runnerMode)")
            return
        }
        XCTAssertEqual(host, "10.0.0.5:11434")
    }
}

/// Coverage for PsychQuant/macdoc#218 Codex round-1 finding #5a:
/// `PageOCRRunner` used to hardcode `OllamaBackend(host:model:)`'s model to
/// `"glm-ocr"` regardless of `self.model`, so wiring `--model`/`config ocr`
/// into `PageOCRRunner`'s own `model` property would have had no observable
/// effect at all. `makeOllamaBackend` is a plain struct construction (no
/// I/O), so this can be pinned directly without a reachable Ollama server.
///
/// Scope, honestly (Codex round-2 finding #2): this only proves the
/// factory itself passes `model` through. It does not prove `run()` still
/// calls this factory with the resolved model instead of, say, a literal —
/// that wiring is a single line at the call site inside `run()`, which
/// needs a real (or injected) OCR pipeline run to observe and is out of
/// reach of a fast unit test.
final class PageOCRRunnerBackendTests: XCTestCase {
    func testOllamaBackendUsesTheGivenModelNotAHardcodedOne() {
        let backend = PageOCRRunner.makeOllamaBackend(host: "h:1234", model: "my-custom-tag")
        XCTAssertEqual(backend.host, "h:1234")
        XCTAssertEqual(backend.model, "my-custom-tag", "must not silently fall back to a hardcoded model")
    }
}

/// CLI-level coverage: `config ocr` subcommands' `--config` redirection
/// (added by #218 so tests, and anyone else, can point at an isolated
/// settings file instead of `~/.config/macdoc/config.json`).
final class OCRConfigOptionsCLITests: XCTestCase {

    private func tempConfigPath() -> String {
        FixtureManager.outputPath("macdoc-ocr-config-\(UUID().uuidString).json")
    }

    func testAddHostAndSetDefaultPersistToTheGivenConfigFileOnly() throws {
        let configPath = tempConfigPath()
        XCTAssertFalse(FileManager.default.fileExists(atPath: configPath), "temp config must start out absent")

        let addHost = try CLITestHelper.run([
            "config", "ocr", "add-host", "kyle", "10.0.0.5:11435", "--config", configPath,
        ])
        XCTAssertEqual(addHost.exitCode, 0, "add-host should succeed\nstderr: \(addHost.stderr)")

        let setDefault = try CLITestHelper.run([
            "config", "ocr", "set-default", "kyle", "--config", configPath,
        ])
        XCTAssertEqual(setDefault.exitCode, 0, "set-default should succeed\nstderr: \(setDefault.stderr)")

        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath), "settings should be written to --config, not the real config")

        let list = try CLITestHelper.run(["config", "ocr", "list", "--config", configPath])
        XCTAssertEqual(list.exitCode, 0)
        XCTAssertTrue(list.stdout.contains("kyle → 10.0.0.5:11435"), list.stdout)
        XCTAssertTrue(list.stdout.contains("default host: kyle"), list.stdout)

        // Confirm the on-disk file actually carries the values (not just
        // process-local state) by decoding it directly.
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let saved = try JSONDecoder().decode(AIConfig.self, from: data)
        XCTAssertEqual(saved.ocrHosts["kyle"], "10.0.0.5:11435")
        XCTAssertEqual(saved.ocrDefaultHost, "kyle")
    }

    func testSetModelPersistsToTheGivenConfigFile() throws {
        let configPath = tempConfigPath()
        let result = try CLITestHelper.run([
            "config", "ocr", "set-model", "my-ollama-tag", "--config", configPath,
        ])
        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")

        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let saved = try JSONDecoder().decode(AIConfig.self, from: data)
        XCTAssertEqual(saved.ocrDefaultModel, "my-ollama-tag")
    }
}
