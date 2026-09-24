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
    @Test("many concurrent runProcess calls all finish", .timeLimit(.minutes(1)))
    func concurrentCallsFinish() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount * 3
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<count {
                group.addTask {
                    let result = try CLITestHelper.runProcess(
                        executableURL: URL(fileURLWithPath: "/bin/sh"),
                        arguments: ["-c", "sleep 0.2; echo \(index)"],
                        currentDirectory: nil,
                        timeout: 30)
                    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            var collected: [String] = []
            for try await output in group { collected.append(output) }
            return collected
        }
        #expect(Set(outputs) == Set((0..<count).map(String.init)))
    }
}
