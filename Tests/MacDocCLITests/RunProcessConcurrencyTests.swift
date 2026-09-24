import Foundation
import Testing

/// macdoc#219 的後續：`runProcess` 的 pipe reader 不得依賴 GCD 的全域佇列。
///
/// Swift Testing 在 cooperative pool 上平行跑測試，每個測試都在 `runProcess` 裡同步等待。
/// reader 若排在 `DispatchQueue.global()`，一旦所有 cooperative 執行緒都卡在等待，workqueue
/// 就不再開執行緒給 reader，所有呼叫一起永遠等下去（整個 CLISpec suite 曾因此卡死）。
/// 這裡刻意開出比 pool 寬度多好幾倍的並行呼叫，逼出那個狀態。
@Suite("runProcess under a saturated cooperative pool")
struct RunProcessConcurrencyTests {
    /// 子行程先睡 1 秒：在任何一個子行程結束之前，所有 task 都已經進入 `runProcess` 同步等待，
    /// cooperative pool 因此確實飽和（只是送出很多 task 不保證這一點）。每個子行程另外往 stderr
    /// 寫超過 pipe 容量的 100 KB，兩個 pipe 都必須被完整讀到，而且不能因背壓卡住。
    @Test("many concurrent runProcess calls all finish with both pipes fully read", .timeLimit(.minutes(1)))
    func concurrentCallsFinish() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount * 3
        let stderrBytes = 100_000
        let outputs = try await withThrowingTaskGroup(of: (String, Int).self) { group in
            for index in 0..<count {
                group.addTask {
                    let result = try CLITestHelper.runProcess(
                        executableURL: URL(fileURLWithPath: "/bin/sh"),
                        arguments: ["-c", "sleep 1; printf '%s' \(index); head -c \(stderrBytes) /dev/zero | tr '\\0' x >&2"],
                        currentDirectory: nil,
                        timeout: 30)
                    return (result.stdout, result.stderr.utf8.count)
                }
            }
            var collected: [(String, Int)] = []
            for try await output in group { collected.append(output) }
            return collected
        }
        #expect(Set(outputs.map(\.0)) == Set((0..<count).map(String.init)), "stdout 必須逐字完整，不做任何裁切")
        #expect(outputs.allSatisfy { $0.1 == stderrBytes }, "stderr 必須完整讀到 \(stderrBytes) bytes")
    }
}
