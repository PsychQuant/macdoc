import Testing
@testable import TokenCounter

@Test("TokenCounter is importable as a Swift package product")
func tokenCounterProductIsImportable() {
    #expect(Bool(true))
}
