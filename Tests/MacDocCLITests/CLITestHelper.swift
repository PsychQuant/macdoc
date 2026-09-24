import Foundation
import XCTest

/// CLI 執行結果
struct CLIResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

enum BinarySelectionError: Error, Equatable {
    case invalidOverride(String)
    case unavailable(String)
}

extension BinarySelectionError: CustomStringConvertible {
    /// Human-readable diagnostic, distinct from the `Equatable` conformance
    /// above (tests keep comparing on the raw associated `String`, so this
    /// description is free to be more explicit without breaking anything
    /// that asserts equality). PsychQuant/macdoc#192 asked specifically for
    /// a clearer message when the override points at a directory, since
    /// that used to be indistinguishable from "path just doesn't exist"
    /// until it crashed inside `Process.run()`.
    var description: String {
        switch self {
        case .invalidOverride(let value):
            let shown = value.isEmpty ? "(空字串)" : value
            return "MACDOC_TEST_BINARY 必須是非空、以 / 開頭的絕對路徑，收到的值不符：\(shown)"
        case .unavailable(let path):
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            if exists && isDirectory.boolValue {
                return "找不到可執行的 macdoc binary：\(path) 是一個目錄，不是可執行檔。" +
                    "請確認路徑指向實際的 binary 檔案（例如 .../.build/debug/macdoc），而非其所在目錄。"
            } else if exists {
                return "找不到可執行的 macdoc binary：\(path) 存在，但沒有可執行權限。"
            } else {
                return "找不到可執行的 macdoc binary：\(path) 不存在。" +
                    "請先執行對應組態的 `swift build`，或確認 MACDOC_TEST_BINARY 指向正確路徑。"
            }
        }
    }
}

/// CLI 測試輔助工具
enum CLITestHelper {

    static func resolveBinaryURL(
        repoRoot: URL,
        configuration: String,
        environment: [String: String],
        isExecutable: (String) -> Bool
    ) throws -> URL {
        let candidate: URL
        if let override = environment["MACDOC_TEST_BINARY"] {
            guard !override.isEmpty, override.hasPrefix("/") else {
                throw BinarySelectionError.invalidOverride(override)
            }
            candidate = URL(fileURLWithPath: override)
        } else {
            candidate = repoRoot.appendingPathComponent(".build")
                .appendingPathComponent(configuration)
                .appendingPathComponent("macdoc")
        }

        guard isExecutable(candidate.path) else {
            throw BinarySelectionError.unavailable(candidate.path)
        }
        return candidate
    }

    /// macdoc binary 路徑
    static var binaryPath: String {
        get throws {
            #if DEBUG
            let configuration = "debug"
            #else
            let configuration = "release"
            #endif
            return try resolveBinaryURL(
                repoRoot: repoRoot,
                configuration: configuration,
                environment: ProcessInfo.processInfo.environment,
                isExecutable: Self.isExecutableFile(atPath:)
            ).path
        }
    }

    /// `FileManager.isExecutableFile(atPath:)` returns `true` for a
    /// directory that has its execute bit set — true of almost every
    /// directory, since that bit is what makes it `cd`-able. Left unguarded,
    /// a `MACDOC_TEST_BINARY` override pointing at a directory would sail
    /// past `resolveBinaryURL`'s `guard isExecutable(...)` check and only
    /// fail later inside `Process.run()`, with a low-level error instead of
    /// the clean `BinarySelectionError.unavailable` this helper is supposed
    /// to produce (PsychQuant/macdoc#192). Reject directories up front.
    private static func isExecutableFile(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        if isDirectory.boolValue {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// repo 根目錄（從 Tests/MacDocCLITests/ 往上兩層）
    static var repoRoot: URL {
        // #file 在 Tests/MacDocCLITests/CLITestHelper.swift
        // 往上 3 層 = repo root
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // MacDocCLITests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    /// 執行 macdoc 指令
    static func run(
        _ arguments: [String],
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil
    ) throws -> CLIResult {
        let path = try binaryPath
        // Evaluated for PsychQuant/macdoc#192: switching this to the
        // throwing `try? FileHandle.standardError.write(contentsOf:)` does
        // NOT reliably avoid crashing the test process on a closed/broken
        // stderr pipe. Spiked both APIs against a `Pipe` whose reading end
        // was closed first:
        //   - With SIGPIPE at its default disposition (the normal state of
        //     an XCTest/Swift Testing process), the write(2) syscall itself
        //     raises SIGPIPE and terminates the process immediately — this
        //     happens before Foundation gets a chance to translate the
        //     error, for EITHER API. `try?` cannot catch a signal.
        //   - Only if SIGPIPE is explicitly ignored (`signal(SIGPIPE,
        //     SIG_IGN)`) process-wide does the legacy `write(_:)` raise an
        //     uncatchable `NSFileHandleOperationException` (ObjC exception,
        //     not a Swift `Error` — `do/catch` cannot intercept it either)
        //     while `write(contentsOf:)` throws a genuine, catchable Swift
        //     `Error`.
        // So `write(contentsOf:)` is only safer in a scenario (SIGPIPE
        // already globally ignored) that does not hold for this shared test
        // binary, and ignoring SIGPIPE process-wide to enable that path is
        // out of scope here — it would change signal disposition for every
        // other test sharing the process, not just this diagnostic write.
        // Kept as the non-throwing `write(_:)` call; see also
        // Tests/MacDocCLITests/README.md.
        FileHandle.standardError.write(Data("[macdoc-test] binary=\(path)\n".utf8))
        return try runProcess(
            executableURL: URL(fileURLWithPath: path),
            arguments: arguments,
            currentDirectory: repoRoot,
            timeout: timeout,
            environment: environment)
    }

    /// Global across every `runProcess` call in the test process. macdoc#224:
    /// `fork()`/`posix_spawn()` duplicate every open fd that isn't
    /// `FD_CLOEXEC` into the new child, including a *different*, concurrently
    /// in-flight `runProcess` call's pipes. `makeCloseOnExecPipe()` closes
    /// that gap for our own pipes, but only if nothing else can spawn a
    /// process in the moment between a pipe's creation and this call's own
    /// `process.run()` — this lock serializes exactly that narrow window
    /// across every `runProcess` caller (not the slow read/wait afterward,
    /// which stays concurrent). Scope, honestly: it only coordinates
    /// `runProcess` callers with each other. It does not, and cannot,
    /// protect against a raw `Process`/`posix_spawn`/`fork()` call made
    /// outside `runProcess` (this test target has none in production code;
    /// `RunProcessFDInheritanceTests`'s own raw-`posix_spawn` probes are
    /// deliberately outside this lock, since they exist to observe real fd
    /// state, not to spawn something that needs coordinating with).
    private static let spawnLock = NSLock()

    /// Creates a `Pipe` and immediately marks both of its file descriptors
    /// `FD_CLOEXEC`. macdoc#224: without this, a subprocess spawned by a
    /// *different*, concurrently-running `runProcess` call (e.g. another
    /// Swift Testing task on another thread) can inherit this pipe's write
    /// end across its own `exec()` — `fork`/`posix_spawn` duplicate every
    /// open fd unless it's marked close-on-exec, and fd tables are shared
    /// across all threads of one process. That extra, unrelated reference
    /// then keeps this pipe's read end from ever seeing EOF until the other
    /// process *also* exits (observed as an ~30s stall: `CLISpecHarness`'s
    /// dump-help call stuck behind a slow route-probe test running in
    /// parallel — see that file's comment on why it used to avoid this
    /// function entirely). `dup2`-created descriptors (what `Process` uses
    /// to wire a pipe end to a child's stdin/stdout/stderr) never inherit
    /// `FD_CLOEXEC` from their source regardless of this flag, so this does
    /// not affect our own child's ability to read/write the pipe.
    static func makeCloseOnExecPipe() -> Pipe {
        let pipe = Pipe()
        for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
            let fd = handle.fileDescriptor
            let flags = fcntl(fd, F_GETFD)
            guard flags != -1 else { continue }
            _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC)
        }
        return pipe
    }

    /// The exact recovery `runProcess`'s `catch` block performs when
    /// `process.run()` throws: closing both pipes' write ends is what
    /// unblocks the two background readers stuck in `readDataToEndOfFile()`
    /// — extracted to its own function (Codex round-1 finding #1) so a test
    /// can exercise *this specific function*, the one the catch block
    /// actually calls, rather than only a hand-rolled reproduction of the
    /// same idea with a different `Pipe`.
    static func closeWriteEndsForSpawnFailureCleanup(_ pipes: Pipe...) {
        for pipe in pipes {
            try? pipe.fileHandleForWriting.close()
        }
    }

    /// Runs an arbitrary executable with a timeout, returning its captured
    /// output. Extracted from `run` so the timeout path is testable against a
    /// deterministically-slow command (macdoc#133).
    ///
    /// - Parameter pipesForTesting: **Test-only.** Called with this call's
    ///   own `stdoutPipe`/`stderrPipe` right after they're created and
    ///   assigned to `process`, before `process.run()`. macdoc#224 (Codex
    ///   round-1 finding #2): without this, a test can only exercise
    ///   `makeCloseOnExecPipe()` in isolation — proving the factory itself
    ///   is correct, not that `runProcess` actually uses it for its own
    ///   pipes (the same factory-vs-call-site gap macdoc#225 fixed for
    ///   `PageOCRRunner`). Always `nil` in production; adding it does not
    ///   change behavior for any real caller.
    /// - Parameter onSpawnFailureCleanup: **Test-only.** Called right after
    ///   `closeWriteEndsForSpawnFailureCleanup` runs in the `catch` block
    ///   below, i.e. only when `process.run()` actually throws. macdoc#224
    ///   (Codex round-1 finding #1): closes the remaining gap between
    ///   "`closeWriteEndsForSpawnFailureCleanup` does what it claims"
    ///   (covered directly by `RunProcessFDInheritanceTests
    ///   .closingWriteEndUnblocksBlockedReader`, which calls that function
    ///   but not through `runProcess`) and "`runProcess`'s own `catch` block
    ///   actually reaches that call" — this hook lets a test observe the
    ///   latter directly instead of only inferring it from `runProcess`
    ///   returning promptly (which, per the honest limitation on
    ///   `CLITestHelperTimeoutTests.testInvalidExecutableReturnsPromptly`,
    ///   this platform's `Process`/Foundation may already guarantee for
    ///   reasons independent of this code path). Always `nil` in
    ///   production.
    static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectory: URL?,
        timeout: TimeInterval,
        environment: [String: String]? = nil,
        pipesForTesting: ((_ stdout: Pipe, _ stderr: Pipe) -> Void)? = nil,
        onSpawnFailureCleanup: (() -> Void)? = nil
    ) throws -> CLIResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(
                environment,
                uniquingKeysWith: { _, override in override }
            )
        }

        // macdoc#224: pipe creation, marking them FD_CLOEXEC, and spawning
        // this function's own child are one atomic unit with respect to
        // every other `runProcess` call — see `spawnLock`'s doc comment.
        // Everything after `process.run()` returns (the timeout loop,
        // `waitUntilExit`, draining) stays outside the lock and fully
        // concurrent, same as before.
        spawnLock.lock()
        let stdoutPipe = makeCloseOnExecPipe()
        let stderrPipe = makeCloseOnExecPipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        pipesForTesting?(stdoutPipe, stderrPipe)

        // macdoc#219: a pipe's kernel buffer (~64 KB on macOS) is far
        // smaller than plenty of real command output (e.g. `macdoc
        // --experimental-dump-help`, ~180 KB). Reading *after* the process
        // exits — the previous approach — deadlocks the moment a child
        // fills that buffer: the child blocks in write(2) waiting for a
        // reader, while this function blocks waiting for the child to exit,
        // and nobody drains the pipe until the timeout kills the child
        // mid-write. Draining both pipes continuously on background queues,
        // started before the process even runs, means neither pipe can ever
        // fill up, so the child is never blocked on write(2) regardless of
        // output size.
        final class OutputBox: @unchecked Sendable {
            var data = Data()
        }
        let stdoutBox = OutputBox()
        let stderrBox = OutputBox()
        let drainGroup = DispatchGroup()

        // Dedicated threads, not `DispatchQueue.global()`: non-overcommit
        // global queues share the constrained thread limit (≈ CPU count)
        // with Swift concurrency's cooperative pool. Swift Testing runs many
        // tests in parallel on that pool and each one blocks synchronously
        // below (`waitUntilExit`, `drainGroup.wait()`); once every
        // cooperative thread is blocked, the workqueue spawns no thread for
        // a GCD reader, the reader never runs, and every caller waits
        // forever. Observed: the whole CLISpec suite hung with all 18
        // cooperative threads parked in `drainGroup.wait()` and no reader
        // thread in existence. A `Thread` is a real pthread outside that
        // limit, so each reader always gets to run.
        for (handle, box) in [(stdoutPipe.fileHandleForReading, stdoutBox),
                              (stderrPipe.fileHandleForReading, stderrBox)] {
            drainGroup.enter()
            let reader = Thread {
                box.data = handle.readDataToEndOfFile()
                drainGroup.leave()
            }
            reader.stackSize = 1 << 18
            reader.start()
        }

        do {
            try process.run()
        } catch {
            spawnLock.unlock()
            // The readers above are already blocked waiting for EOF, but if
            // the process never started (bad executable path, no exec
            // permission, …) nothing will ever close the pipes' write ends
            // to deliver that EOF — the two background threads, and the
            // file descriptors they're blocked on, would otherwise leak for
            // the lifetime of the process. Closing our own write-end handles
            // is enough: the read ends then see EOF on their own and the
            // readers return normally, so this doesn't need to touch the
            // read ends (which a background thread may still be inside a
            // syscall on) at all.
            closeWriteEndsForSpawnFailureCleanup(stdoutPipe, stderrPipe)
            onSpawnFailureCleanup?()
            drainGroup.wait()
            throw error
        }
        spawnLock.unlock()

        // Timeout 保護
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }

        // macdoc#133: terminate() only sends SIGTERM (async). Reading
        // terminationStatus before the process is reaped throws
        // NSInvalidArgumentException ("task still running") and crashes the
        // whole test process. waitUntilExit() reaps it — safe on both the
        // normal-exit and the timeout-terminate paths.
        process.waitUntilExit()

        // Each background read reaches EOF (and `drainGroup.leave()`) once
        // every process holding the pipe's write end open has exited.
        // `waitUntilExit()` above only guarantees *this* process (the one
        // we spawned) has exited — not any grandchildren. Unrelated,
        // concurrently-spawned processes can no longer hold onto this
        // pipe's write end (macdoc#224's `FD_CLOEXEC` fix above), so this
        // now depends only on this process's own descendants closing their
        // copies, same as any ordinary use of `Pipe` + `Process`.
        drainGroup.wait()

        return CLIResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutBox.data, encoding: .utf8) ?? "",
            stderr: String(data: stderrBox.data, encoding: .utf8) ?? ""
        )
    }

    /// 執行 macdoc convert 指令
    static func convert(
        to format: String,
        input: String,
        flags: [String] = [],
        environment: [String: String]? = nil
    ) throws -> CLIResult {
        var args = ["convert", "--to", format] + flags + [input]
        return try run(args, environment: environment)
    }

    /// 取得 .note 測試 fixture 的絕對路徑。若 repo 內無可用樣本則 XCTSkip。
    ///
    /// Resolution order (per PsychQuant/macdoc#100 verify fix 2026-06-01):
    /// 1. Tests/MacDocCLITests/Fixtures/mini.note (curated committable)
    /// 2. test-files/*.note (rich developer fixture — preferred when present
    ///    so strict NoteHTMLConvertTests assertions exercise real content)
    /// 3. Freshly synthesized via NoteFixtureGenerator (synthetic content;
    ///    regenerated every call — no cache, since stale-cache bugs were the
    ///    #100 verify P1 finding)
    /// 4. XCTSkip (only if all of the above fail — should be rare)
    ///
    /// Why prefer test-files over synthetic: the strict assertions in
    /// `NoteHTMLConvertTests.testNoteToHTMLSmoke` (`>750KB index.html` +
    /// `media/ >= 1 asset`) calibrated against rich content per #81 only
    /// fire when the fixture has actual recordings/images. Cache + synthetic
    /// silently masked test-files in the initial #100 implementation; this
    /// order prevents that regression. Synthetic remains the CI fallback so
    /// repos without a local fixture still run the smoke tests (with
    /// fixture-type-aware structural assertions).
    static func noteFixture(file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        // 1. Pre-generated committable fixture (if present)
        let committedFixture = repoRoot.appendingPathComponent(
            "Tests/MacDocCLITests/Fixtures/mini.note"
        )
        if FileManager.default.fileExists(atPath: committedFixture.path) {
            return committedFixture
        }

        // 2. Rich developer fixture — gitignored local samples per #81.
        //    Prefer this over synthetic so strict assertions exercise real
        //    content when a developer has it locally.
        let candidates = [
            "test-files/筆記 2026-03-20 15_25_20.note",
        ]
        for relativePath in candidates {
            let url = repoRoot.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let fallbackDir = repoRoot.appendingPathComponent("test-files")
        if FileManager.default.fileExists(atPath: fallbackDir.path) {
            let contents = try FileManager.default.contentsOfDirectory(
                at: fallbackDir, includingPropertiesForKeys: nil
            )
            let noteFiles = contents
                .filter { $0.pathExtension.lowercased() == "note" }
                .sorted(by: { $0.path < $1.path })
            if let found = noteFiles.first {
                return found
            }
        }

        // 3. Freshly synthesized — regenerate every call. Generator is fast
        //    (~ms), so the no-cache strategy avoids the stale-cache bugs
        //    flagged in #100's first-round verify (P1). The output URL uses
        //    a UUID per invocation so concurrent test processes don't race.
        let freshURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-synthetic-fixture-\(UUID().uuidString).note")
        do {
            try NoteFixtureGenerator.generate(at: freshURL)
            return freshURL
        } catch {
            // Generator failure is unexpected — surface clearly. Don't silently
            // skip; raise via XCTSkip with the underlying error in the message.
            throw XCTSkip(
                "NoteFixtureGenerator failed: \(error). No .note fixture available. See PsychQuant/macdoc#100.",
                file: file, line: line
            )
        }
    }
}
