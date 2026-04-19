// TextSegment.swift — Format-agnostic styled text primitives

/// A segment of text with a single semantic style.
public enum TextSegment: Equatable, Sendable {
    case plain(String)
    case italic(String)
    case bold(String)
    case link(text: String, url: String)
}

/// A sequence of styled text segments forming a complete styled string.
public struct StyledText: Equatable, Sendable {
    public let segments: [TextSegment]

    public init(_ segments: [TextSegment]) {
        self.segments = segments
    }

    public init(plain text: String) {
        self.segments = [.plain(text)]
    }

    public init(italic text: String) {
        self.segments = [.italic(text)]
    }

    public var isEmpty: Bool {
        segments.allSatisfy { segment in
            switch segment {
            case .plain(let t), .italic(let t), .bold(let t): return t.isEmpty
            case .link(let t, _): return t.isEmpty
            }
        }
    }
}
