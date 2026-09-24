import Foundation

// DocxIntegrationBinaryResolver — extracted from MacDocDocxIntegrationTests
// per PsychQuant/macdoc#192.
//
// MacDocDocxIntegrationTests has always resolved the `macdoc` binary with
// its own private, cwd-relative lookup instead of going through
// `CLITestHelper` — it only ever checks `<cwd>/.build/debug/macdoc` and
// ignores `MACDOC_TEST_BINARY` entirely. #192 asked to make that resolver
// independently testable *without* folding it into `CLITestHelper` into a
// single unified resolver — the two are deliberately different: this one
// stays pinned to the debug product regardless of build configuration or
// override, which is fine for these tests (they only assert on `--help`
// output and a manifest apply/plan round trip, not on which configuration
// produced the binary).
//
// Do not add MACDOC_TEST_BINARY (or any other override) support here. If a
// future change needs that, it belongs in `CLITestHelper`, and
// `MacDocDocxIntegrationTests` should migrate to it explicitly — not gain it
// silently through this type.
enum DocxIntegrationBinaryResolver {
    /// Resolves the built `macdoc` binary used by `MacDocDocxIntegrationTests`.
    ///
    /// - Parameters:
    ///   - cwd: The process's current working directory (tests run from the
    ///     repo root, so this is expected to be the repo root).
    ///   - environment: Accepted for callers that want to pass the real
    ///     process environment, but intentionally unused — see the type doc
    ///     comment above. Defaults to `[:]` so call sites that have no
    ///     environment to pass don't need to fabricate one.
    ///   - fileExists: Injected so tests can simulate presence/absence
    ///     without touching the real filesystem.
    /// - Returns: `<cwd>/.build/debug/macdoc` if `fileExists` reports it
    ///   present, otherwise `nil`.
    static func resolve(
        cwd: URL,
        environment: [String: String] = [:],
        fileExists: (String) -> Bool
    ) -> URL? {
        let candidate = cwd.appendingPathComponent(".build/debug/macdoc")
        return fileExists(candidate.path) ? candidate : nil
    }
}
