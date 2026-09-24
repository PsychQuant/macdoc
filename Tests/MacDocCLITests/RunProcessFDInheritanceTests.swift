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
/// Codex findings addressed across two review rounds:
/// - round 1: tests only covered `makeCloseOnExecPipe()` and the reader-
///   unblocking mechanism in isolation, not `runProcess`'s actual call
///   sites; a hand-rolled `Pipe` reproduction stood in for the real
///   `closeWriteEndsForSpawnFailureCleanup`; `probesAsLeaked` silently
///   treated broken-probe output as "not leaked"; and a couple of test-only
///   comments overstated `spawnLock`'s protection scope. All addressed via
///   test-only hooks on `runProcess`/`closeWriteEndsForSpawnFailureCleanup`
///   (`pipesForTesting`, `onEachClosed`), strict probe-output validation,
///   and narrower comment wording.
/// - round 2 (this revision):
///   - **Integration test race**: the first version of `runProcessOwnPipesDoNotLeak`
///     captured a pipe's fd via `pipesForTesting`, then probed it *after*
///     `process.run()` had already been allowed to proceed on another
///     thread. `Foundation.Process`, on a successful spawn, closes its
///     caller-provided pipe's write end in the *parent* shortly after (it
///     has to, for the pipe's own EOF semantics to work at all when nobody
///     else explicitly closes it) — so a probe that runs after that point
///     can observe "fd already closed" and report a false `CLEAN`,
///     regardless of whether `FD_CLOEXEC` was ever set. Fixed: the probe
///     now runs *synchronously inside* the `pipesForTesting` callback,
///     strictly before `process.run()` is called — the only place where
///     the fd's parent-side lifetime is guaranteed. That also removes the
///     separate `Thread` and cross-thread `Captured`/`RunOutcome` reads
///     entirely, which incidentally resolves the round-2 data-race finding
///     on this specific test (see next point) by construction — there is
///     no longer a second thread involved.
///   - **Unsynchronized post-timeout reads**: `XCTAssertTrue`/`#expect`
///     alone are not control-flow guards — execution continues to the next
///     line even when the expectation fails, so a value written by another
///     thread could still be read racily right after a *failed* (timed
///     out) wait. `FileHandleOutputFlushTests.testFlushOnAPipeDoesNotThrow`
///     (in `common-converter-swift`) now `guard`s on the wait's result
///     before reading `box.data`.
///   - **`onSpawnFailureCleanup` didn't prove causality**: it fired as a
///     separate statement after `closeWriteEndsForSpawnFailureCleanup(...)`
///     at the `runProcess` call site, so deleting *only* the cleanup call
///     would have left the hook — and the test observing it — passing
///     regardless. Fixed: the hook is now a parameter threaded *into*
///     `closeWriteEndsForSpawnFailureCleanup` itself (`onEachClosed:`,
///     invoked once per pipe from inside its own loop, right after that
///     pipe's `close()`), so there is exactly one call site and no way to
///     observe cleanup without the function itself running.
///   - **Shell fd bookkeeping could produce a false "LEAKED"**: the
///     `/bin/sh` probe's own redirect handling (`{ : <&N; } 2>/dev/null`)
///     performs its own internal fd save/restore around the redirect,
///     which can itself reallocate a just-freed fd number to something
///     unrelated to the pipe under test, independent of anything
///     `runProcess` does. Fixed: the probe is now `/usr/bin/python3 -c
///     '...'` — Codex round-3: "always present" overstated it; the actual
///     prerequisite is Xcode Command Line Tools being installed, which this
///     suite already requires to build and run at all (it never does
///     shell-style redirect fd juggling regardless) — calling `os.fstat(fd)`
///     directly on the raw integer, and additionally compares the probed fd's
///     `st_dev`/`st_ino` against the *expected* pipe's own — an fd that
///     happens to be open but points at something else (e.g. a descriptor
///     python's own startup opened at that same number) no longer counts
///     as a leak of *this* pipe.
// `.serialized`: even with the round-2 fixes above, the fd-inheritance
// tests still identify pipes by raw integer fd number, which is process-
// wide state. Serializing removes any chance of *this suite's own* tests
// interleaving their pipe lifecycles; it cannot, and does not, protect
// against unrelated pipe/process churn in *other* concurrently-running
// suites in the same `swift test` invocation — the dev/ino identity check
// in `probesAsLeaked` is the actual defense against that, since a fd
// reused by something unrelated to this suite would also fail the identity
// comparison rather than being mistaken for this suite's own pipe.
@Suite("runProcess FD inheritance and reader-unblocking (macdoc#224)", .serialized)
struct RunProcessFDInheritanceTests {

    private struct RawSpawnError: Error, CustomStringConvertible {
        let code: Int32
        var description: String { "posix_spawn failed with code \(code)" }
    }

    private struct UnexpectedProbeOutput: Error, CustomStringConvertible {
        let output: String
        var description: String {
            "probe produced unparseable output (got: \(output.isEmpty ? "<empty>" : output))"
        }
    }

    private struct FstatFailed: Error, CustomStringConvertible {
        let fd: Int32
        var description: String { "fstat failed for fd \(fd)" }
    }

    /// This process's own `st_dev`/`st_ino` for an open fd — used to give
    /// the raw-spawned probe an identity to compare against, not just a
    /// number (Codex round-2 finding: a bare fd-number check can produce a
    /// false "LEAKED" if something *else* ends up open at the same number
    /// in the probe process).
    private func identity(ofOpenFD fd: Int32) throws -> (dev: Int32, ino: UInt64) {
        var status = stat()
        guard fstat(fd, &status) == 0 else { throw FstatFailed(fd: fd) }
        return (dev: status.st_dev, ino: UInt64(status.st_ino))
    }

    /// Spawns `/usr/bin/python3 -c <script>` via raw `posix_spawn` (attrp
    /// `nil` — no `POSIX_SPAWN_CLOEXEC_DEFAULT`, no other special
    /// attributes) and returns its captured stdout. Deliberately *not*
    /// built on `Process`/`runProcess` — see the suite doc comment above
    /// for why. Deliberately python3, not `/bin/sh` — see the doc comment's
    /// round-2 "shell fd bookkeeping" point.
    ///
    /// Checks every `posix_spawn*` return code, retries `waitpid` on
    /// `EINTR`, and (Codex round-3 finding) verifies the child actually
    /// terminated normally with exit status 0 rather than silently
    /// accepting any `waitpid` result — a probe that printed a
    /// recognizable-looking line and then exited abnormally would
    /// otherwise be indistinguishable from a genuine, trustworthy result.
    /// `readDataToEndOfFile()` has no explicit deadline of its own; this is
    /// accepted here because the script is always a short, fixed,
    /// guaranteed-terminating `os.fstat` + `print` (never anything that
    /// could block on I/O or user input), not because blocking reads are
    /// safe in general — `runProcess`'s own concurrent-drain design exists
    /// precisely because that assumption doesn't hold for arbitrary
    /// commands.
    private func rawSpawnPythonAndCaptureStdout(script: String) throws -> String {
        let outPipe = Pipe()
        var fileActions: posix_spawn_file_actions_t?
        var rc = posix_spawn_file_actions_init(&fileActions)
        guard rc == 0 else { throw RawSpawnError(code: rc) }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        rc = posix_spawn_file_actions_adddup2(&fileActions, outPipe.fileHandleForWriting.fileDescriptor, 1)
        guard rc == 0 else { throw RawSpawnError(code: rc) }

        var pid: pid_t = 0
        let argv: [String?] = ["/usr/bin/python3", "-c", script, nil]
        let cArgs = argv.map { $0.flatMap { strdup($0) } }
        defer { for case let arg? in cArgs { free(arg) } }

        rc = posix_spawn(&pid, "/usr/bin/python3", &fileActions, nil, cArgs, environ)
        try outPipe.fileHandleForWriting.close()
        guard rc == 0 else { throw RawSpawnError(code: rc) }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        var status: Int32 = 0
        while true {
            let waited = waitpid(pid, &status, 0)
            if waited == -1 {
                if errno == EINTR { continue }
                throw RawSpawnError(code: errno)
            }
            guard waited == pid else { throw RawSpawnError(code: -1) }
            break
        }
        guard status == 0 else { throw RawSpawnError(code: status) }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Probes whether fd `fd` is open in a raw-spawned child and, if so,
    /// whether it identifies the *same* underlying file as `expected`
    /// (this pipe's own `st_dev`/`st_ino`, captured in this process before
    /// spawning the probe). `os.fstat` is a direct syscall wrapper — no
    /// shell redirect machinery sits between the child's `exec()` and the
    /// check.
    private func probesAsLeaked(fd: Int32, expected: (dev: Int32, ino: UInt64)) throws -> Bool {
        let script = """
        import os
        try:
            st = os.fstat(\(fd))
            print("OPEN", st.st_dev, st.st_ino)
        except OSError:
            print("CLOSED")
        """
        let output = try rawSpawnPythonAndCaptureStdout(script: script)
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard let first = parts.first else { throw UnexpectedProbeOutput(output: output) }
        switch first {
        case "CLOSED":
            return false
        case "OPEN":
            guard parts.count == 3, let dev = Int32(parts[1]), let ino = UInt64(parts[2]) else {
                throw UnexpectedProbeOutput(output: output)
            }
            // Open, but at something other than this pipe (e.g. a fd
            // python's own startup happened to allocate at the same
            // number) — not a leak of *this* pipe.
            return dev == expected.dev && ino == expected.ino
        default:
            throw UnexpectedProbeOutput(output: output)
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
        let expected = try identity(ofOpenFD: writeFD)
        defer {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        #expect(try probesAsLeaked(fd: writeFD, expected: expected), "a plain Pipe()'s write end (fd \(writeFD)) should leak into a raw fork+exec child")
    }

    /// Point 1: the actual fix, exercised at the factory level. A pipe
    /// created via `makeCloseOnExecPipe` must not be inherited.
    @Test("a close-on-exec pipe's write end does not leak into a raw fork+exec child")
    func closeOnExecPipeDoesNotLeakIntoRawSpawnedChild() throws {
        let pipe = CLITestHelper.makeCloseOnExecPipe()
        let writeFD = pipe.fileHandleForWriting.fileDescriptor
        let expected = try identity(ofOpenFD: writeFD)
        defer {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
        }
        #expect(try !probesAsLeaked(fd: writeFD, expected: expected), "makeCloseOnExecPipe's write end (fd \(writeFD)) must not leak into a raw fork+exec child")
    }

    /// Point 1, integration: the factory-level test above only proves
    /// `makeCloseOnExecPipe()` itself is correct — not that `runProcess`
    /// actually uses it for its own pipes (Codex round-1: reverting
    /// `runProcess` back to plain `Pipe()` calls would leave that test, and
    /// the one above, unaffected). This one goes through `runProcess`
    /// itself via the test-only `pipesForTesting` hook.
    ///
    /// Codex round-2: the probe runs *synchronously inside* that callback,
    /// strictly before `process.run()` — see this file's top-level doc
    /// comment for why probing any later races against `Process.run()`'s
    /// own parent-side pipe cleanup on a successful spawn.
    @Test("runProcess's own pipes — not just makeCloseOnExecPipe() in isolation — do not leak into a raw fork+exec child")
    func runProcessOwnPipesDoNotLeak() throws {
        struct LeakDetected: Error, CustomStringConvertible {
            let name: String
            let fd: Int32
            var description: String { "runProcess's own \(name) pipe write end (fd \(fd)) leaked into a raw fork+exec child" }
        }

        final class ProbeOutcome: @unchecked Sendable {
            var error: Error?
        }
        let outcome = ProbeOutcome()

        _ = try? CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "true"],
            currentDirectory: nil,
            timeout: 10,
            pipesForTesting: { stdout, stderr in
                do {
                    for (name, pipe) in [("stdout", stdout), ("stderr", stderr)] {
                        let fd = pipe.fileHandleForWriting.fileDescriptor
                        let expected = try identity(ofOpenFD: fd)
                        if try probesAsLeaked(fd: fd, expected: expected) {
                            outcome.error = LeakDetected(name: name, fd: fd)
                            return
                        }
                    }
                } catch {
                    outcome.error = error
                }
            })

        if let error = outcome.error {
            throw error
        }
    }

    /// Point 2, mechanism: this is the exact function `runProcess`'s
    /// `catch` block calls when `process.run()` throws
    /// (`CLITestHelper.closeWriteEndsForSpawnFailureCleanup`) — not a
    /// hand-rolled reproduction of the same idea. Establishes both halves
    /// of the causal claim: (a) without a close, nothing else unblocks a
    /// reader stuck in `readDataToEndOfFile()` — proven by a bounded wait
    /// that must time out — and (b) calling this exact function is what
    /// unblocks it.
    ///
    /// The reader thread's completion is observed *only* through
    /// `DispatchSemaphore.wait()`'s return value — no auxiliary `Bool` flag
    /// read outside that synchronization, since a flag read after a
    /// `.timedOut` wait would race with the reader thread's eventual write
    /// to it.
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
    /// `onSpawnFailureCleanup` hook.
    ///
    /// Codex round-2: the hook is threaded into
    /// `closeWriteEndsForSpawnFailureCleanup`'s own `onEachClosed:`
    /// parameter (fired once per pipe, from inside its own close loop) —
    /// not a separate statement at the `runProcess` call site — so there is
    /// exactly one call site left, and no way to delete the cleanup call
    /// while leaving the observation intact. Verified by hand: removing
    /// that call from `runProcess`'s `catch` block doesn't just fail this
    /// test — `drainGroup.wait()` right after it blocks forever with no
    /// cleanup ever reached, a hang rather than a clean failure.
    ///
    /// Codex round-3: that hang is exactly why `runProcess` itself must not
    /// run on this test's own thread — `runProcess(timeout:)` only bounds
    /// its *successfully spawned child's* runtime, not the synchronous
    /// `drainGroup.wait()` on the failure path, so a regression there would
    /// hang indefinitely with no timeout anywhere to catch it (as just
    /// confirmed). Running it on a background `Thread` means this test's
    /// own bounded `cleanupRan.wait(timeout:)` below is what actually
    /// bounds the test, even if `runProcess` itself never returns; the
    /// worst case on a regression is a leaked thread (same accepted
    /// trade-off as `CLITestHelperTimeoutTests
    /// .testInvalidExecutableReturnsPromptly`), not a hung test run.
    @Test("runProcess's catch block actually reaches its spawn-failure cleanup call")
    func runProcessCatchBlockReachesCleanup() throws {
        let cleanupRan = DispatchSemaphore(value: 0)
        let runner = Thread {
            _ = try? CLITestHelper.runProcess(
                executableURL: URL(fileURLWithPath: "/nonexistent/definitely-not-a-binary-\(UUID().uuidString)"),
                arguments: [],
                currentDirectory: nil,
                timeout: 10,
                onSpawnFailureCleanup: { cleanupRan.signal() })
        }
        runner.start()
        let observed = cleanupRan.wait(timeout: .now() + 5) == .success
        #expect(observed, "runProcess's catch block should reach its spawn-failure cleanup call for a nonexistent executable")
    }
}
