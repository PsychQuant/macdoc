import Foundation
import XCTest

/// Regression test for macdoc#133: the timeout path in CLITestHelper must
/// reap the child before reading terminationStatus, otherwise
/// `-[NSConcreteTask terminationStatus]` throws NSInvalidArgumentException
/// ("task still running") and takes down the whole test process.
///
/// Uses `/bin/sleep` (guaranteed to outlive a sub-second timeout) so the
/// terminate branch is exercised deterministically — independent of macdoc's
/// cold-start timing.
final class CLITestHelperTimeoutTests: XCTestCase {

    func testTimeoutPathReapsChildAndDoesNotCrash() throws {
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            currentDirectory: nil,
            timeout: 0.3)
        // The child was SIGTERM'd on timeout; reaching this line at all means
        // terminationStatus was read on a reaped process (no exception).
        XCTAssertNotEqual(result.exitCode, 0,
                          "a timed-out (terminated) process must not report success")
    }

    func testNormalPathStillReturnsCleanly() throws {
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["ok"],
            currentDirectory: nil,
            timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
    }

    /// Regression test for macdoc#219: `runProcess` used to wait for the
    /// child to exit *before* draining its stdout/stderr pipes. A pipe's
    /// kernel buffer is far smaller than 256 KB (~64 KB on macOS), so any
    /// child writing more than that blocks on `write(2)` waiting for a
    /// reader that never comes until the process is reaped — deadlock,
    /// broken only by the timeout killing the child mid-write. `yes | head
    /// -c 300000` produces just over 256 KB of stdout, comfortably past one
    /// pipe buffer, and should complete well inside a generous timeout once
    /// the pipes are drained concurrently with the process running.
    ///
    /// Asserts the exact byte count, not just "at least 256 KB" (Codex
    /// round-1 finding #5b): `head -c 300000` writes exactly that many
    /// bytes, so anything else — including a silent truncation that still
    /// clears the 256 KB floor — is itself a bug this should catch.
    func testLargeOutputDoesNotDeadlock() throws {
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes | head -c 300000"],
            currentDirectory: nil,
            timeout: 10)
        XCTAssertEqual(result.exitCode, 0, "should exit cleanly, not be killed by the timeout")
        XCTAssertEqual(result.stdout.utf8.count, 300_000, "stdout should be captured in full, byte for byte")
    }

    /// Regression test for macdoc#219 round-2 (Codex finding #5b): the
    /// single-stream test above only proves stdout is drained; it says
    /// nothing about stderr, which is drained by a second, independent
    /// background reader. Fill both streams past one pipe buffer *at the
    /// same time* (both backgrounded in the child, so both pipes are
    /// filling concurrently, not one after the other) — if either reader
    /// were missing or serialized behind the other, this would deadlock or
    /// truncate exactly the way the original bug did.
    func testLargeOutputOnBothStreamsSimultaneouslyDoesNotDeadlock() throws {
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes | head -c 300000 & yes | head -c 300000 1>&2 & wait"],
            currentDirectory: nil,
            timeout: 10)
        XCTAssertEqual(result.exitCode, 0, "should exit cleanly, not be killed by the timeout")
        XCTAssertEqual(result.stdout.utf8.count, 300_000, "stdout should be captured in full, byte for byte")
        XCTAssertEqual(result.stderr.utf8.count, 300_000, "stderr should be captured in full, byte for byte")
    }

    /// Regression test for Codex round-1 finding #4: the two background
    /// pipe-drain readers are started *before* `process.run()`, so that
    /// they're already waiting the instant the process starts writing. If
    /// `run()` then throws (here: a nonexistent executable), nothing used
    /// to close the pipes' write ends, so both readers — blocked forever
    /// in `readDataToEndOfFile()` waiting for an EOF that would never come
    /// — could leak for the rest of the process's lifetime, along with
    /// their file descriptors. `runProcess` now closes both write ends on
    /// that failure path before rethrowing, so the readers see EOF and
    /// return normally instead.
    ///
    /// Honest limitation (Codex round-2 finding #1): this test does NOT
    /// actually discriminate the fix from the bug it describes. Verified by
    /// hand — reverting the write-end-closing fix still passes this test,
    /// because on this Foundation implementation `readDataToEndOfFile()`
    /// already returns promptly once `process.run()` throws for a
    /// nonexistent path, for reasons this investigation did not fully pin
    /// down (see macdoc#219's fix commit message). So this test currently
    /// only proves "an invalid executable does not hang the caller" — a
    /// legitimate smoke-test property in its own right — not specifically
    /// that the write-end-closing code is what makes that true. Turning it
    /// into a real regression guard for the leak itself would need an
    /// observable way to detect whether the two background readers have
    /// actually completed (e.g. exposing their own completion signal for
    /// tests), which is a large enough change to `runProcess`'s shape that
    /// it is left as a follow-up rather than folded into this fix.
    func testInvalidExecutableDoesNotLeakBlockedReaders() {
        let returned = expectation(description: "runProcess returns despite process.run() throwing")
        DispatchQueue.global().async {
            _ = try? CLITestHelper.runProcess(
                executableURL: URL(fileURLWithPath: "/nonexistent/definitely-not-a-binary-\(UUID().uuidString)"),
                arguments: [],
                currentDirectory: nil,
                timeout: 30)
            returned.fulfill()
        }
        wait(for: [returned], timeout: 5)
    }
}
