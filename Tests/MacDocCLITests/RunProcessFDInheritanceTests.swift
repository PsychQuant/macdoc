import Foundation
import Testing

/// PsychQuant/macdoc#224: two gaps `runProcess` (macdoc#219) left
/// unprotected, called out explicitly as needing regression coverage.
///
/// 1. A pipe's write end could be inherited by a *different*, concurrently
///    spawned subprocess (e.g. another `runProcess` call on another thread),
///    keeping the read end from ever seeing EOF until that unrelated process
///    also exits.
/// 2. `process.run()` failing (bad executable) relies on explicitly closing
///    both pipes' write ends to unblock the two background readers —
///    otherwise they'd block in `readDataToEndOfFile()` forever. The
///    existing `testInvalidExecutableReturnsPromptly` in
///    `CLITestHelperTimeoutTests.swift` cannot discriminate the fix from its
///    absence on this platform (its own doc comment says so); the tests
///    below exercise the underlying mechanism directly instead of relying
///    on `process.run()`'s particular failure-mode timing.
///
/// Honest finding while writing point 1's test: on the Darwin/Swift
/// toolchain this suite runs on, `Foundation.Process.run()` already
/// isolates a spawned child from inheriting arbitrary parent fds by
/// default — confirmed empirically: a plain, non-close-on-exec `Pipe()`'s
/// write end is *not* visible to a child spawned via `runProcess`/`Process`,
/// with or without `makeCloseOnExecPipe`'s `fcntl` call. That means a probe
/// built on `Process`/`runProcess` cannot discriminate the fix from its
/// absence — it would pass either way. The tests below instead spawn the
/// probe via **raw** `posix_spawn` with no special attributes (not through
/// `Process`, and specifically *not* setting `POSIX_SPAWN_CLOEXEC_DEFAULT`),
/// reproducing classic POSIX fork+exec fd-inheritance semantics. That does
/// discriminate cleanly: a plain pipe leaks into this raw-spawned probe, a
/// `makeCloseOnExecPipe`-guarded one does not. This is also the more
/// conservative thing to pin down — `runProcess` should not depend on
/// `Process.run()`'s current, platform-specific spawn-attribute choice to
/// stay safe (the CLISpecHarness comment this issue quotes describes an
/// observed ~30s stall from exactly this class of leak, presumably on a
/// Foundation/OS version — or via some other spawn path — that did not
/// isolate by default the way this one does).
///
/// Codex round-1 findings addressed here (beyond the mechanics above):
/// - The original version of these tests only exercised
///   `makeCloseOnExecPipe()` and a hand-rolled `Pipe` reproduction in
///   isolation — proving the *factory* and the *unblocking mechanism* are
///   each correct, but not that `runProcess` actually wires its own pipes
///   through that factory, or that its `catch` block actually calls the
///   exact cleanup function it relies on. `runProcessOwnPipesDoNotLeak`
///   and `closingWriteEndUnblocksBlockedReader` (below) now go through
///   `runProcess` itself (via the test-only `pipesForTesting` hook) and
///   `CLITestHelper.closeWriteEndsForSpawnFailureCleanup` (the literal
///   function the `catch` block calls) respectively — the same
///   factory-vs-call-site gap macdoc#225 fixed for `PageOCRRunner`.
/// - `probesAsLeaked` now fails loudly on any output other than exactly
///   `"LEAKED"` or `"CLEAN"`, instead of treating anything-not-"LEAKED"
///   (including empty output from a broken probe) as a negative result.
// `.serialized`: the fd-inheritance tests below identify a pipe by its raw
// integer fd number and check, from a *separately spawned process*, whether
// that exact number is open. Each tested pipe stays open (not reused) for
// the whole synchronous probe, so a *sibling test's* own pipe cannot
// directly steal that exact number mid-probe — but low fd numbers are
// reused eagerly, and the probe's own raw-spawned child does its own
// allocation (the `outPipe` used to capture the probe's stdout, the shell's
// own bookkeeping) that can land on the number `FD_CLOEXEC` just freed
// inside *that* child during its own `exec()`, independent of any other
// test. Whichever of those is the precise mechanism, serializing removed
// the flake directly: without `.serialized`,
// `closeOnExecPipeDoesNotLeakIntoRawSpawnedChild` failed roughly 2 times
// out of 3 running alongside its siblings in this file; 5 repeated runs
// were clean with it. `.serialized` only protects this one `@Suite` — it
// does not, and cannot, protect against unrelated pipe/process churn in
// *other* concurrently-running suites in the same `swift test` invocation;
// `probesAsLeaked`'s strict output validation (reject anything but exactly
// "LEAKED"/"CLEAN") is the actual defense against a probe silently reading
// the wrong fd's state as a false negative.
@Suite("runProcess FD inheritance and reader-unblocking (macdoc#224)", .serialized)
struct RunProcessFDInheritanceTests {

    private struct RawSpawnError: Error, CustomStringConvertible {
        let code: Int32
        var description: String { "posix_spawn failed with code \(code)" }
    }

    private struct UnexpectedProbeOutput: Error, CustomStringConvertible {
        let output: String
        var description: String {
            "probe produced neither \"LEAKED\" nor \"CLEAN\" (got: \(output.isEmpty ? "<empty>" : output)) — probe itself is broken, not a valid CLEAN result"
        }
    }

    /// Spawns `/bin/sh -c <command>` via raw `posix_spawn` (attrp `nil` —
    /// no `POSIX_SPAWN_CLOEXEC_DEFAULT`, no other special attributes) and
    /// returns its captured stdout. This is deliberately *not* built on
    /// `Process`/`runProcess` — see the suite doc comment above for why.
    ///
    /// Codex round-1 finding #6 (robustness): checks every `posix_spawn*`
    /// return code (previously ignored) and retries `waitpid` on `EINTR`
    /// instead of silently accepting whatever `waitpid` happened to return.
    private func rawSpawnAndCaptureStdout(command: String) throws -> String {
        let outPipe = Pipe()
        var fileActions: posix_spawn_file_actions_t?
        var rc = posix_spawn_file_actions_init(&fileActions)
        guard rc == 0 else { throw RawSpawnError(code: rc) }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        rc = posix_spawn_file_actions_adddup2(&fileActions, outPipe.fileHandleForWriting.fileDescriptor, 1)
        guard rc == 0 else { throw RawSpawnError(code: rc) }

        var pid: pid_t = 0
        let argv: [String?] = ["/bin/sh", "-c", command, nil]
        let cArgs = argv.map { $0.flatMap { strdup($0) } }
        defer { for case let arg? in cArgs { free(arg) } }

        rc = posix_spawn(&pid, "/bin/sh", &fileActions, nil, cArgs, environ)
        try outPipe.fileHandleForWriting.close()
        guard rc == 0 else { throw RawSpawnError(code: rc) }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        var status: Int32 = 0
        while true {
            let waited = waitpid(pid, &status, 0)
            if waited == -1 && errno == EINTR { continue }
            break
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `{ : <&N; }` in the probed shell only succeeds if fd `N` is already
    /// open in *that* shell — this checks real kernel-level fd inheritance
    /// through a raw fork+exec, not anything about `Process`'s internals.
    /// Uses `:` (the shell's no-op builtin) with a redirect scoped to just
    /// that one command, not `exec 3<&N` — `exec` permanently dup's fd `N`
    /// onto a *new* fd (3) for the rest of the script, which is an
    /// additional fd allocation the probe doesn't need and that could
    /// itself interact with whatever fd churn is under investigation.
    ///
    /// Codex round-1 finding #4: rejects any output other than exactly
    /// "LEAKED" or "CLEAN" — previously, anything-not-"LEAKED" (including
    /// empty output from a broken probe: a failed `sh` invocation, a
    /// truncated read, …) silently counted as a negative ("not leaked")
    /// result, which could mask a broken probe as a passing test.
    private func probesAsLeaked(fd: Int32) throws -> Bool {
        let output = try rawSpawnAndCaptureStdout(
            command: "{ : <&\(fd); } 2>/dev/null && echo LEAKED || echo CLEAN")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "LEAKED": return true
        case "CLEAN": return false
        default: throw UnexpectedProbeOutput(output: output)
        }
    }

    /// Point 1, negative control: establishes that the probe above actually
    /// discriminates the fix from its absence — a *plain* `Pipe()` (skipping
    /// `makeCloseOnExecPipe`'s `fcntl` call) must leak into a raw fork+exec.
    /// This is the exact RED state `makeCloseOnExecPipe` fixes.
    @Test("(negative control) a plain Pipe()'s write end leaks into a raw fork+exec child")
    func plainPipeLeaksIntoRawSpawnedChild() throws {
        let pipe = Pipe()
        let writeFD = pipe.fileHandleForWriting.fileDescriptor
        defer {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        #expect(try probesAsLeaked(fd: writeFD), "a plain Pipe()'s write end (fd \(writeFD)) should leak into a raw fork+exec child")
    }

    /// Point 1: the actual fix, exercised at the factory level. A pipe
    /// created via `makeCloseOnExecPipe` must not be inherited.
    @Test("a close-on-exec pipe's write end does not leak into a raw fork+exec child")
    func closeOnExecPipeDoesNotLeakIntoRawSpawnedChild() throws {
        let pipe = CLITestHelper.makeCloseOnExecPipe()
        let writeFD = pipe.fileHandleForWriting.fileDescriptor
        defer {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        #expect(try !probesAsLeaked(fd: writeFD), "makeCloseOnExecPipe's write end (fd \(writeFD)) must not leak into a raw fork+exec child")
    }

    /// Point 1, integration: the factory-level test above only proves
    /// `makeCloseOnExecPipe()` itself is correct — not that `runProcess`
    /// actually uses it for its own pipes (Codex round-1 finding #2:
    /// reverting `runProcess` back to plain `Pipe()` calls would leave that
    /// test, and the one above, unaffected). This one goes through
    /// `runProcess` itself: a slow child (`sleep 0.5`) keeps `runProcess`'s
    /// own stdout pipe write end open long enough to probe it via the
    /// test-only `pipesForTesting` hook, while `runProcess` is still
    /// in-flight on another thread.
    @Test("runProcess's own pipes — not just makeCloseOnExecPipe() in isolation — do not leak into a raw fork+exec child")
    func runProcessOwnPipesDoNotLeak() throws {
        final class Captured: @unchecked Sendable {
            var stdoutWriteFD: Int32?
        }
        final class RunOutcome: @unchecked Sendable {
            var result: Swift.Result<CLIResult, Error>?
        }
        let captured = Captured()
        let outcome = RunOutcome()
        let pipeReady = DispatchSemaphore(value: 0)
        let runFinished = DispatchSemaphore(value: 0)

        // A real pthread, not a `Task` — same reasoning `runProcess`'s own
        // reader threads document: a raw `DispatchSemaphore.wait()` inside
        // an `async` test body would block a Swift concurrency
        // cooperative-pool worker, which is the exact starvation class
        // macdoc#219 exists to avoid (and, as of Swift 6, is a hard
        // compiler error to write directly in an `async` context anyway).
        let runner = Thread {
            do {
                let result = try CLITestHelper.runProcess(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "sleep 0.5"],
                    currentDirectory: nil,
                    timeout: 10,
                    pipesForTesting: { stdout, _ in
                        captured.stdoutWriteFD = stdout.fileHandleForWriting.fileDescriptor
                        pipeReady.signal()
                    })
                outcome.result = .success(result)
            } catch {
                outcome.result = .failure(error)
            }
            runFinished.signal()
        }
        runner.start()

        let observed = pipeReady.wait(timeout: .now() + 5) == .success
        #expect(observed, "did not observe runProcess's pipe via pipesForTesting in time")
        guard let writeFD = captured.stdoutWriteFD else {
            _ = runFinished.wait(timeout: .now() + 10)
            return
        }

        // runProcess's child is still sleeping (0.5s), so its stdout pipe's
        // write end is still open in this process at this point — probe it
        // for real, the same way the factory-level test above does.
        #expect(try !probesAsLeaked(fd: writeFD), "runProcess's own stdout pipe write end (fd \(writeFD)) must not leak into a raw fork+exec child")

        _ = runFinished.wait(timeout: .now() + 10)
        if case .failure(let error) = outcome.result {
            throw error
        }
    }

    /// Point 2, mechanism: this is the exact function `runProcess`'s
    /// `catch` block calls when `process.run()` throws
    /// (`CLITestHelper.closeWriteEndsForSpawnFailureCleanup`) — not a
    /// hand-rolled reproduction of the same idea (Codex round-1 finding
    /// #1). Establishes both halves of the causal claim: (a) without a
    /// close, nothing else unblocks a reader stuck in
    /// `readDataToEndOfFile()` — proven by a bounded wait that must time
    /// out — and (b) calling this exact function is what unblocks it.
    ///
    /// Codex round-1 finding #3: the reader thread's completion is
    /// observed *only* through `DispatchSemaphore.wait()`'s return value —
    /// no auxiliary `Bool` flag read outside that synchronization, since a
    /// flag read after a `.timedOut` wait would race with the reader
    /// thread's eventual write to it.
    @Test("runProcess's spawn-failure cleanup — closeWriteEndsForSpawnFailureCleanup — unblocks a reader stuck in readDataToEndOfFile")
    func closingWriteEndUnblocksBlockedReader() throws {
        let pipe = CLITestHelper.makeCloseOnExecPipe()
        let readerFinished = DispatchSemaphore(value: 0)
        let reader = Thread {
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            readerFinished.signal()
        }
        reader.start()

        // Negative control: nothing has closed the write end yet, so the
        // reader must still be blocked. Without this, the assertion below
        // would be trivially satisfied by a reader that finishes
        // immediately for an unrelated reason.
        let stillBlocked = readerFinished.wait(timeout: .now() + 0.3) == .timedOut
        #expect(stillBlocked, "reader should still be blocked while the write end remains open")

        CLITestHelper.closeWriteEndsForSpawnFailureCleanup(pipe)

        let finished = readerFinished.wait(timeout: .now() + 5) == .success
        #expect(finished, "closeWriteEndsForSpawnFailureCleanup should unblock the reader promptly")
    }

    /// Point 2, integration: the test above proves
    /// `closeWriteEndsForSpawnFailureCleanup` itself works, but not that
    /// `runProcess`'s own `catch` block actually reaches that call when
    /// `process.run()` throws. This one goes through the real `runProcess`
    /// with a guaranteed-nonexistent executable and observes the
    /// `onSpawnFailureCleanup` hook, which only fires from inside that
    /// exact `catch` block, right after its cleanup call.
    @Test("runProcess's catch block actually reaches its spawn-failure cleanup call")
    func runProcessCatchBlockReachesCleanup() throws {
        let cleanupRan = DispatchSemaphore(value: 0)
        _ = try? CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/nonexistent/definitely-not-a-binary-\(UUID().uuidString)"),
            arguments: [],
            currentDirectory: nil,
            timeout: 10,
            onSpawnFailureCleanup: { cleanupRan.signal() })
        let observed = cleanupRan.wait(timeout: .now() + 5) == .success
        #expect(observed, "runProcess's catch block should reach its spawn-failure cleanup call for a nonexistent executable")
    }
}
