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
    func testLargeOutputDoesNotDeadlock() throws {
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes | head -c 300000"],
            currentDirectory: nil,
            timeout: 10)
        XCTAssertEqual(result.exitCode, 0, "should exit cleanly, not be killed by the timeout")
        XCTAssertGreaterThanOrEqual(
            result.stdout.utf8.count, 256 * 1024,
            "stdout should be captured in full, past one pipe buffer")
    }
}
