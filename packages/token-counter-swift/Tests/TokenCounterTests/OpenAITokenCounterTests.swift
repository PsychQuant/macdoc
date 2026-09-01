import CryptoKit
import Darwin
import Foundation
import Testing

@testable import TokenCounter

@Suite("OpenAI o200k_base token counter", .serialized)
struct OpenAITokenCounterTests {
  private static let expectedVocabularySHA256 =
    "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d"

  @Test(
    "matches official Python tiktoken o200k_base reference vectors",
    arguments: OfficialReferenceVector.all
  )
  func matchesOfficialReferenceVector(_ vector: OfficialReferenceVector) throws {
    let counter = try OpenAITokenCounter()

    let result: TokenCount = try counter.count(text: vector.text)

    #expect(result.model == TokenModel.gpt4o)
    #expect(result.source == .local)
    #expect(
      result.tokens == vector.expectedCount,
      "Official token IDs: \(vector.officialTokenIDs)"
    )
  }

  @Test("bundled o200k_base vocabulary has the audited SHA-256")
  func bundledVocabularyHasAuditedSHA256() throws {
    let bytes = try OpenAITokenCounter.bundledResourceLoader()

    #expect(OpenAITokenCounter.expectedVocabularySHA256 == Self.expectedVocabularySHA256)
    #expect(sha256Hex(bytes) == Self.expectedVocabularySHA256)
  }

  @Test("corrupted vocabulary fails with a typed integrity error")
  func corruptedVocabularyFailsBeforeCounting() throws {
    var bytes = try OpenAITokenCounter.bundledResourceLoader()
    try #require(!bytes.isEmpty)
    bytes[bytes.startIndex] ^= 0xff
    let corruptedBytes = bytes

    do {
      _ = try OpenAITokenCounter(resourceLoader: { corruptedBytes })
      Issue.record("A corrupted vocabulary must fail before parsing or counting")
    } catch let error as TokenCounterError {
      guard
        case .resourceIntegrity(
          expectedSHA256: let expected,
          actualSHA256: let actual
        ) = error
      else {
        Issue.record("Expected resourceIntegrity, got \(error)")
        return
      }
      #expect(expected == Self.expectedVocabularySHA256)
      #expect(actual == sha256Hex(corruptedBytes))
      #expect(actual != expected)
    } catch {
      Issue.record("Expected TokenCounterError.resourceIntegrity, got \(error)")
    }
  }

  @Test("injected bytes bypass downloader and create no cache or home artifact")
  func injectedLoaderIsOfflineAndLeavesNoFilesystemArtifact() throws {
    let bundledBytes = try OpenAITokenCounter.bundledResourceLoader()
    let loaderProbe = ResourceLoaderProbe(bytes: bundledBytes)
    let networkProbe = NetworkRequestProbe.shared
    networkProbe.reset()

    let sandbox = try IsolatedFilesystemEnvironment()
    defer { sandbox.restoreAndRemove() }

    let registered = URLProtocol.registerClass(RejectingNetworkURLProtocol.self)
    defer { URLProtocol.unregisterClass(RejectingNetworkURLProtocol.self) }
    #expect(registered)

    let before = try filesystemSnapshot(at: sandbox.root)
    let counter = try OpenAITokenCounter(resourceLoader: loaderProbe.load)
    let result: TokenCount = try counter.count(text: "offline only")
    let after = try filesystemSnapshot(at: sandbox.root)

    #expect(result.model == TokenModel.gpt4o)
    #expect(result.source == .local)
    #expect(loaderProbe.callCount == 1)
    #expect(networkProbe.requestCount == 0)
    #expect(after == before)
  }
}

struct OfficialReferenceVector: Sendable, CustomTestStringConvertible {
  let name: String
  let text: String
  let expectedCount: Int
  let officialTokenIDs: [Int]

  var testDescription: String { name }

  static let all: [Self] = [
    .init(name: "empty", text: "", expectedCount: 0, officialTokenIDs: []),
    .init(
      name: "ASCII",
      text: "hello world",
      expectedCount: 2,
      officialTokenIDs: [24_912, 2_375]
    ),
    .init(
      name: "台灣正體中文",
      text: "台灣正體中文",
      expectedCount: 5,
      officialTokenIDs: [3_735, 133_072, 10_170, 33_078, 10_667]
    ),
    .init(
      name: "mixed script",
      text: "Hello，台灣！",
      expectedCount: 5,
      officialTokenIDs: [13_225, 979, 3_735, 133_072, 3_393]
    ),
    .init(
      name: "emoji",
      text: "👩‍💻🚀",
      expectedCount: 7,
      officialTokenIDs: [28_823, 102, 2_524, 31_446, 119, 112_927, 222]
    ),
  ]
}

private final class ResourceLoaderProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let bytes: Data
  private var calls = 0

  init(bytes: Data) {
    self.bytes = bytes
  }

  var callCount: Int {
    lock.withLock { calls }
  }

  func load() throws -> Data {
    lock.withLock { calls += 1 }
    return bytes
  }
}

private final class NetworkRequestProbe: @unchecked Sendable {
  static let shared = NetworkRequestProbe()

  private let lock = NSLock()
  private var requests = 0

  var requestCount: Int {
    lock.withLock { requests }
  }

  func recordRequest() {
    lock.withLock { requests += 1 }
  }

  func reset() {
    lock.withLock { requests = 0 }
  }
}

private final class RejectingNetworkURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    guard let scheme = request.url?.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      return false
    }

    NetworkRequestProbe.shared.recordRequest()
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let error = NSError(
      domain: "OpenAITokenCounterTests.NetworkForbidden",
      code: 1
    )
    client?.urlProtocol(self, didFailWithError: error)
  }

  override func stopLoading() {}
}

private struct IsolatedFilesystemEnvironment {
  let root: URL

  private let originalEnvironment: [(key: String, value: String?)]

  init() throws {
    let fileManager = FileManager.default
    root = fileManager.temporaryDirectory
      .appendingPathComponent("OpenAITokenCounterTests-\(UUID().uuidString)", isDirectory: true)

    let home = root.appendingPathComponent("home", isDirectory: true)
    let cache = root.appendingPathComponent("cache", isDirectory: true)
    let temporary = root.appendingPathComponent("tmp", isDirectory: true)
    try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)

    let replacements = [
      ("HOME", home.path),
      ("CFFIXED_USER_HOME", home.path),
      ("XDG_CACHE_HOME", cache.path),
      ("TMPDIR", temporary.path),
    ]
    originalEnvironment = replacements.map { key, _ in
      (key: key, value: environmentValue(for: key))
    }
    for (key, value) in replacements {
      setenv(key, value, 1)
    }
  }

  func restoreAndRemove() {
    for entry in originalEnvironment {
      if let value = entry.value {
        setenv(entry.key, value, 1)
      } else {
        unsetenv(entry.key)
      }
    }
    try? FileManager.default.removeItem(at: root)
  }
}

private func environmentValue(for key: String) -> String? {
  guard let value = getenv(key) else { return nil }
  return String(cString: value)
}

private func filesystemSnapshot(at root: URL) throws -> [String] {
  guard
    let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: []
    )
  else {
    return []
  }

  var entries: [String] = []
  for case let url as URL in enumerator {
    let relativePath = String(url.path.dropFirst(root.path.count + 1))
    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
    if values.isDirectory == true {
      entries.append("directory:\(relativePath)")
    } else if values.isRegularFile == true {
      entries.append("file:\(relativePath):\(sha256Hex(try Data(contentsOf: url)))")
    } else {
      entries.append("other:\(relativePath)")
    }
  }
  return entries.sorted()
}

private func sha256Hex(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
