// Manifest.swift — §2.1 of macdoc-docx-workflow-cli.
//
// Root manifest type plus the tagged-by-`type` Step enum. All Phase 1
// runtime-functional step types plus Phase 2c-pending cases compile here;
// runtime gap-handling (warn-and-skip for pending cases) lives in
// EditPlanner + Executor (§4.1, §4.2).

import Foundation

public struct Manifest: Codable, Equatable {
    public let baseline: String
    public let output: String
    public let steps: [Step]
    public let verify: VerifyAssertions?

    public init(
        baseline: String,
        output: String,
        steps: [Step],
        verify: VerifyAssertions? = nil
    ) {
        self.baseline = baseline
        self.output = output
        self.steps = steps
        self.verify = verify
    }
}

// MARK: - Step (tagged enum by `type`)

public enum Step: Codable, Equatable {
    // Phase 1 runtime-functional cases
    case replaceText(ReplaceTextStep)
    case insertParagraph(InsertParagraphStep)
    case setParagraphStyle(SetParagraphStyleStep)
    case wrapLink(WrapLinkStep)
    case setBold(SetBoldStep)
    case setItalic(SetItalicStep)
    case setUnderline(SetUnderlineStep)
    case removeParagraph(RemoveParagraphStep)

    // Phase 2c pending — ooxml-swift#71
    case insertImage(InsertImageStep)
    case insertTable(InsertTableStep)
    case setCellText(SetCellTextStep)
    case insertEquation(InsertEquationStep)

    private enum DiscriminatorKey: String, CodingKey {
        case type
    }

    /// String value carried by the JSON `type` discriminator field.
    /// Identical for runtime-functional and pending cases — pending-step
    /// gap-handling is a runtime concern (EditPlanner), not a decode one.
    public var typeID: String {
        switch self {
        case .replaceText: return "replace_text"
        case .insertParagraph: return "insert_paragraph"
        case .setParagraphStyle: return "set_paragraph_style"
        case .wrapLink: return "wrap_link"
        case .setBold: return "set_bold"
        case .setItalic: return "set_italic"
        case .setUnderline: return "set_underline"
        case .removeParagraph: return "remove_paragraph"
        case .insertImage: return "insert_image"
        case .insertTable: return "insert_table"
        case .setCellText: return "set_cell_text"
        case .insertEquation: return "insert_equation"
        }
    }

    public init(from decoder: Decoder) throws {
        let disc = try decoder.container(keyedBy: DiscriminatorKey.self)
        let type = try disc.decode(String.self, forKey: .type)
        let single = try decoder.singleValueContainer()
        switch type {
        case "replace_text":
            self = .replaceText(try single.decode(ReplaceTextStep.self))
        case "insert_paragraph":
            self = .insertParagraph(try single.decode(InsertParagraphStep.self))
        case "set_paragraph_style":
            self = .setParagraphStyle(try single.decode(SetParagraphStyleStep.self))
        case "wrap_link":
            self = .wrapLink(try single.decode(WrapLinkStep.self))
        case "set_bold":
            self = .setBold(try single.decode(SetBoldStep.self))
        case "set_italic":
            self = .setItalic(try single.decode(SetItalicStep.self))
        case "set_underline":
            self = .setUnderline(try single.decode(SetUnderlineStep.self))
        case "remove_paragraph":
            self = .removeParagraph(try single.decode(RemoveParagraphStep.self))
        case "insert_image":
            self = .insertImage(try single.decode(InsertImageStep.self))
        case "insert_table":
            self = .insertTable(try single.decode(InsertTableStep.self))
        case "set_cell_text":
            self = .setCellText(try single.decode(SetCellTextStep.self))
        case "insert_equation":
            self = .insertEquation(try single.decode(InsertEquationStep.self))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: disc,
                debugDescription: "Unknown step type '\(type)'. Expected one of: replace_text, insert_paragraph, set_paragraph_style, wrap_link, set_bold, set_italic, set_underline, remove_paragraph, insert_image, insert_table, set_cell_text, insert_equation."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        // Each payload struct already carries the `type` discriminator
        // via its own CodingKeys. Encode the payload directly into the
        // single-value container so the JSON shape stays flat.
        var single = encoder.singleValueContainer()
        switch self {
        case .replaceText(let s): try single.encode(s)
        case .insertParagraph(let s): try single.encode(s)
        case .setParagraphStyle(let s): try single.encode(s)
        case .wrapLink(let s): try single.encode(s)
        case .setBold(let s): try single.encode(s)
        case .setItalic(let s): try single.encode(s)
        case .setUnderline(let s): try single.encode(s)
        case .removeParagraph(let s): try single.encode(s)
        case .insertImage(let s): try single.encode(s)
        case .insertTable(let s): try single.encode(s)
        case .setCellText(let s): try single.encode(s)
        case .insertEquation(let s): try single.encode(s)
        }
    }
}

// MARK: - Step payload structs

public struct ReplaceTextStep: Codable, Equatable {
    public let type: String
    public let find: String
    public let replace: String

    public init(find: String, replace: String) {
        self.type = "replace_text"
        self.find = find
        self.replace = replace
    }
}

public struct InsertParagraphStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let content: String

    public init(anchor: Anchor, content: String) {
        self.type = "insert_paragraph"
        self.anchor = anchor
        self.content = content
    }
}

public struct SetParagraphStyleStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let styleId: String

    private enum CodingKeys: String, CodingKey {
        case type
        case anchor
        case styleId = "style_id"
    }

    public init(anchor: Anchor, styleId: String) {
        self.type = "set_paragraph_style"
        self.anchor = anchor
        self.styleId = styleId
    }
}

public struct WrapLinkStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let url: String

    public init(anchor: Anchor, url: String) {
        self.type = "wrap_link"
        self.anchor = anchor
        self.url = url
    }
}

public struct SetBoldStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let substring: String

    public init(anchor: Anchor, substring: String) {
        self.type = "set_bold"
        self.anchor = anchor
        self.substring = substring
    }
}

public struct SetItalicStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let substring: String

    public init(anchor: Anchor, substring: String) {
        self.type = "set_italic"
        self.anchor = anchor
        self.substring = substring
    }
}

public struct SetUnderlineStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let substring: String

    public init(anchor: Anchor, substring: String) {
        self.type = "set_underline"
        self.anchor = anchor
        self.substring = substring
    }
}

public struct RemoveParagraphStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor

    public init(anchor: Anchor) {
        self.type = "remove_paragraph"
        self.anchor = anchor
    }
}

// MARK: - Phase 2c pending payload structs (decode + carry; no runtime support yet)

public struct InsertImageStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let path: String
    public let width: Int?
    public let name: String?

    public init(anchor: Anchor, path: String, width: Int? = nil, name: String? = nil) {
        self.type = "insert_image"
        self.anchor = anchor
        self.path = path
        self.width = width
        self.name = name
    }
}

public struct InsertTableStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let rows: Int
    public let columns: Int

    public init(anchor: Anchor, rows: Int, columns: Int) {
        self.type = "insert_table"
        self.anchor = anchor
        self.rows = rows
        self.columns = columns
    }
}

public struct SetCellTextStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let row: Int
    public let col: Int
    public let text: String

    public init(anchor: Anchor, row: Int, col: Int, text: String) {
        self.type = "set_cell_text"
        self.anchor = anchor
        self.row = row
        self.col = col
        self.text = text
    }
}

public struct InsertEquationStep: Codable, Equatable {
    public let type: String
    public let anchor: Anchor
    public let omml: String

    public init(anchor: Anchor, omml: String) {
        self.type = "insert_equation"
        self.anchor = anchor
        self.omml = omml
    }
}
