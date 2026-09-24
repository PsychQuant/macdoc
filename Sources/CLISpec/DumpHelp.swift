// Private decoder for swift-argument-parser's `--experimental-dump-help`
// output (PsychQuant/macdoc#72, design "Out-of-process dump-help consumed
// through a private versioned decoder").
//
// The dump format is experimental and unversioned beyond its
// `serializationVersion` field, so it is read here through a minimal
// Decodable subset and never leaks past `CLISpecBuilder`: the YAML schema is
// project-owned. Unknown JSON fields are ignored; unknown enumeration values
// (argument kind, name kind, parsing strategy) fail decoding loudly.

import Foundation

enum DumpHelp {
    static let supportedSerializationVersion = 0

    static func decode(_ data: Data) throws -> DumpCommand {
        let decoder = JSONDecoder()
        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw CLISpecError.malformedDump(String(describing: error))
        }
        guard header.serializationVersion == supportedSerializationVersion else {
            throw CLISpecError.unsupportedSerializationVersion(header.serializationVersion)
        }
        do {
            return try decoder.decode(ToolInfo.self, from: data).command
        } catch {
            throw CLISpecError.malformedDump(String(describing: error))
        }
    }

    private struct Header: Decodable {
        let serializationVersion: Int
    }

    private struct ToolInfo: Decodable {
        let command: DumpCommand
    }
}

struct DumpCommand: Decodable {
    let commandName: String
    let abstract: String?
    let discussion: String?
    let aliases: [String]?
    let shouldDisplay: Bool?
    let defaultSubcommand: String?
    let subcommands: [DumpCommand]?
    let arguments: [DumpArgument]?
}

struct DumpArgument: Decodable {
    enum Kind: String, Decodable {
        case positional, option, flag
    }

    /// ArgumentParser's strategy names, re-spelled into the project's
    /// snake_case vocabulary so an upstream rename touches only this table.
    enum ParsingStrategy: String, Decodable {
        case `default`
        case scanningForValue
        case unconditional
        case upToNextOption
        case allRemainingInput
        case postTerminator
        case allUnrecognized

        /// `nil` for the default strategy (the key is omitted).
        var projectSpelling: String? {
            switch self {
            case .default: return nil
            case .scanningForValue: return "scanning_for_value"
            case .unconditional: return "unconditional"
            case .upToNextOption: return "up_to_next_option"
            case .allRemainingInput: return "all_remaining_input"
            case .postTerminator: return "post_terminator"
            case .allUnrecognized: return "all_unrecognized"
            }
        }
    }

    struct Name: Decodable {
        enum Kind: String, Decodable {
            case long, short, longWithSingleDash
        }

        let kind: Kind
        let name: String
    }

    let kind: Kind
    let names: [Name]?
    let valueName: String?
    let isOptional: Bool
    let isRepeating: Bool
    let parsingStrategy: ParsingStrategy
    let defaultValue: String?
    let allValues: [String]?
    let shouldDisplay: Bool
    let sectionTitle: String?
    let abstract: String?
    let discussion: String?
}
