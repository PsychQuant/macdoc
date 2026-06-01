// Anchor.swift — §2.2 of macdoc-docx-workflow-cli.
//
// Decodes from a JSON object with exactly one of the keys `before_text`,
// `after_text`, or `paragraph_index`. Resolution semantics live in
// AnchorResolver (§3.1).

import Foundation

public enum Anchor: Codable, Equatable {
    case beforeText(String)
    case afterText(String)
    case paragraphIndex(Int)

    private enum CodingKeys: String, CodingKey {
        case beforeText = "before_text"
        case afterText = "after_text"
        case paragraphIndex = "paragraph_index"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try container.decodeIfPresent(String.self, forKey: .beforeText) {
            self = .beforeText(text)
        } else if let text = try container.decodeIfPresent(String.self, forKey: .afterText) {
            self = .afterText(text)
        } else if let idx = try container.decodeIfPresent(Int.self, forKey: .paragraphIndex) {
            self = .paragraphIndex(idx)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .beforeText,
                in: container,
                debugDescription: "Anchor MUST contain exactly one of: before_text, after_text, paragraph_index"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .beforeText(let text):
            try container.encode(text, forKey: .beforeText)
        case .afterText(let text):
            try container.encode(text, forKey: .afterText)
        case .paragraphIndex(let idx):
            try container.encode(idx, forKey: .paragraphIndex)
        }
    }
}
