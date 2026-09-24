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
///    absence on this platform (its own doc comment says so); the second
///    test below exercises the underlying mechanism directly instead of
///    relying on `process.run()`'s particular failure-mode timing.
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
// `.serialized`: the fd-inheritance tests below identify a pipe by its raw
// integer fd number and check, from a *separately spawned process*, whether
// that exact number is open. fd numbers are process-wide and get reused the
// moment they're closed, so two of these tests running concurrently (Swift
// Testing's default) can race — one test's pipe close/reopen can hand its
// old fd number to another concurrently-running test's brand new pipe,
// making the probe check the wrong fd entirely. Observed directly: without
// this trait, `closeOnExecPipeDoesNotLeakIntoRawSpawnedChild` flaked
// (failed roughly 2 times out of 3) purely from running alongside its
// sibling tests in this file.
@Suite("runProcess FD inheritance and reader-unblocking (macdoc#224)", .serialized)
struct RunProcessFDInheritanceTests {

    private struct RawSpawnError: Error, CustomStringConvertible {
        let code: Int32
        var description: String { "posix_spawn failed with code \(code)" }
    }

    /// Spawns `/bin/sh -c <command>` via raw `posix_spawn` (attrp `nil` —
    /// no `POSIX_SPAWN_CLOEXEC_DEFAULT`, no other special attributes) and
    /// returns its captured stdout. This is deliberately *not* built on
    /// `Process`/`runProcess` — see the suite doc comment above for why.
    private func rawSpawnAndCaptureStdout(command: String) throws -> String {
        let outPipe = Pipe()
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, outPipe.fileHandleForWriting.fileDescriptor, 1)

        var pid: pid_t = 0
        let argv: [String?] = ["/bin/sh", "-c", command, nil]
        let cArgs = argv.map { $0.flatMap { strdup($0) } }
        defer { for case let arg? in cArgs { free(arg) } }

        let rc = posix_spawn(&pid, "/bin/sh", &fileActions, nil, cArgs, environ)
        try outPipe.fileHandleForWriting.close()
        guard rc == 0 else { throw RawSpawnError(code: rc) }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// `exec 3<&N` in the probed shell only succeeds if fd `N` is already
    /// open in *that* shell — this checks real kernel-level fd inheritance
    /// through a raw fork+exec, not anything about `Process`'s internals.
    private func probesAsLeaked(fd: Int32) throws -> Bool {
        let output = try rawSpawnAndCaptureStdout(
            command: "exec 3<&\(fd) 2>/dev/null && echo LEAKED || echo CLEAN")
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "LEAKED"
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

    /// Point 1: the actual fix. A pipe created via `makeCloseOnExecPipe` —
    /// exactly how `runProcess` creates its own — must not be inherited.
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

    /// Point 2: this is the exact recovery `runProcess`'s `catch` block
    /// performs when `process.run()` throws. Establishes both halves of the
    /// causal claim: (a) without an explicit close, nothing else unblocks a
    /// reader stuck in `readDataToEndOfFile()` — proven by a bounded wait
    /// that must time out — and (b) the explicit close is what unblocks it.
    @Test("closing a pipe's write end — not anything else — unblocks a reader stuck in readDataToEndOfFile")
    func closingWriteEndUnblocksBlockedReader() throws {
        let pipe = Pipe()
        final class Flag: @unchecked Sendable { var finished = false }
        let flag = Flag()
        let sema = DispatchSemaphore(value: 0)
        let reader = Thread {
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            flag.finished = true
            sema.signal()
        }
        reader.start()

        // Negative control: nothing has closed the write end yet, so the
        // reader must still be blocked. Without this, the assertion below
        // would be trivially satisfied by a reader that finishes
        // immediately for an unrelated reason.
        let stillBlocked = sema.wait(timeout: .now() + 0.3) == .timedOut
        #expect(stillBlocked, "reader should still be blocked while the write end remains open")
        #expect(!flag.finished)

        try pipe.fileHandleForWriting.close()

        let finished = sema.wait(timeout: .now() + 5) == .success
        #expect(finished, "closing the write end should unblock the reader promptly")
        #expect(flag.finished)
    }
}
