// Project-owned document model of cli-spec.yaml, schema_version 1
// (PsychQuant/macdoc#72, design "Project-owned schema with a derived/overlay
// provenance split").
//
// Derived fields live directly on `Command` / `Argument`; overlay facts live
// only in `Command.project` and the top-level `conversions`, `overlaps` and
// `externalDependencies`. `yamlNode` fixes every key order the spec pins.

public struct CLISpecDocument: Equatable, Sendable {
    public static let schemaVersion = 1

    public struct Tool: Equatable, Sendable {
        public var name: String
        public var version: String
        public var abstract: String?
    }

    public struct Source: Equatable, Sendable {
        public var authority: String
        public var dumpHelpSerializationVersion: Int
        public var overlay: String
        public var regenerate: String
    }

    public struct Argument: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            case positional, option, flag
        }

        public var kind: Kind
        /// Positionals only: the value name.
        public var name: String?
        /// Options and flags: every spelling, long first, then single-dash
        /// long, then short.
        public var names: [String]
        /// Options only.
        public var valueName: String?
        public var required: Bool
        public var repeating: Bool
        public var parsing: String?
        public var defaultValue: String?
        public var values: [String]
        public var hidden: Bool
        public var section: String?
        public var help: String?
        public var discussion: String?
    }

    public struct Command: Equatable, Sendable {
        public var path: String
        public var abstract: String?
        public var discussion: String?
        public var aliases: [String]
        public var hidden: Bool
        public var defaultSubcommand: String?
        public var subcommands: [String]
        public var arguments: [Argument]
        public var options: [Argument]
        public var flags: [Argument]
        public var project: CLISpecMetadata.CommandInfo?
    }

    public struct ExternalDependency: Equatable, Sendable {
        public var dependency: CLISpecMetadata.ExternalDependency
        /// Command paths (command order), then conversion labels (conversion
        /// order) that reference the dependency, without duplicates.
        public var usedBy: [String]
    }

    public var tool: Tool
    public var source: Source
    public var commands: [Command]
    public var conversions: [CLISpecMetadata.Conversion]
    public var overlaps: [CLISpecMetadata.Overlap]
    public var externalDependencies: [ExternalDependency]
}

// MARK: - YAML node tree (key orders are normative; see the cli-spec spec)

extension CLISpecDocument {
    public var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("schema_version", .int(Self.schemaVersion))
        entries.add("tool", tool.yamlNode)
        entries.add("source", source.yamlNode)
        entries.add("commands", commands.map(\.yamlNode))
        entries.add("conversions", conversions.map(\.yamlNode))
        entries.add("overlaps", overlaps.map(\.yamlNode))
        entries.add("external_dependencies", externalDependencies.map(\.yamlNode))
        return entries.node
    }
}

extension CLISpecDocument.Tool {
    var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("name", name)
        entries.add("version", version)
        entries.add("abstract", abstract)
        return entries.node
    }
}

extension CLISpecDocument.Source {
    var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("authority", authority)
        entries.add("dump_help_serialization_version", .int(dumpHelpSerializationVersion))
        entries.add("overlay", overlay)
        entries.add("regenerate", regenerate)
        return entries.node
    }
}

extension CLISpecDocument.Command {
    var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("path", path)
        entries.add("abstract", abstract)
        entries.add("discussion", discussion)
        entries.addFlow("aliases", aliases)
        entries.addTrue("hidden", hidden)
        entries.add("default_subcommand", defaultSubcommand)
        entries.addFlow("subcommands", subcommands)
        entries.add("arguments", arguments.map(\.yamlNode))
        entries.add("options", options.map(\.yamlNode))
        entries.add("flags", flags.map(\.yamlNode))
        if let project {
            entries.add("project", project.yamlNode)
        }
        return entries.node
    }
}

extension CLISpecDocument.Argument {
    var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("name", name)
        entries.addFlow("names", names)
        entries.add("value_name", valueName)
        entries.add("required", .bool(required))
        entries.addTrue("repeating", repeating)
        entries.add("parsing", parsing)
        entries.add("default", defaultValue)
        entries.addFlow("values", values)
        entries.addTrue("hidden", hidden)
        entries.add("section", section)
        entries.add("help", help)
        entries.add("discussion", discussion)
        return entries.node
    }
}

extension CLISpecMetadata.CommandInfo {
    var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("status", status.rawValue)
        entries.add("replacement", replacement)
        entries.addFlow("dependencies", dependencies)
        entries.addBlock("notes", notes)
        entries.addFlow("docs", docs)
        return entries.node
    }
}

extension CLISpecMetadata.Conversion {
    var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("label", label)
        entries.add("command", command)
        entries.addFlow("from", from)
        entries.add("to", to)
        entries.add("converter", converter)
        entries.add("output", output.rawValue)
        entries.addFlow("options", options)
        entries.addFlow("styles", styles)
        entries.addFlow("dependencies", dependencies)
        entries.addBlock("notes", notes)
        return entries.node
    }
}

extension CLISpecMetadata.Overlap {
    var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("topic", topic)
        entries.add("paths", paths.map { path in
            var pathEntries = MappingBuilder()
            pathEntries.add("command", path.command)
            pathEntries.add("usage", path.usage)
            pathEntries.add("note", path.note)
            return pathEntries.node
        })
        return entries.node
    }
}

extension CLISpecDocument.ExternalDependency {
    var yamlNode: YAMLNode {
        var entries = MappingBuilder()
        entries.add("id", dependency.id)
        entries.add("kind", dependency.kind.rawValue)
        entries.add("purpose", dependency.purpose)
        entries.add("install", dependency.install)
        entries.addFlow("used_by", usedBy)
        return entries.node
    }
}

/// Collects mapping entries in call order, omitting absent or empty values.
private struct MappingBuilder {
    private(set) var entries: [YAMLEntry] = []

    var node: YAMLNode { .mapping(entries) }

    mutating func add(_ key: String, _ value: YAMLNode) {
        entries.append(YAMLEntry(key, value))
    }

    mutating func add(_ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        entries.append(YAMLEntry(key, .string(value)))
    }

    /// A block sequence of mappings; omitted when empty.
    mutating func add(_ key: String, _ items: [YAMLNode]) {
        guard !items.isEmpty else { return }
        entries.append(YAMLEntry(key, .sequence(items)))
    }

    /// A flow sequence of scalars; omitted when empty.
    mutating func addFlow(_ key: String, _ values: [String]) {
        guard !values.isEmpty else { return }
        entries.append(YAMLEntry(key, .flow(values)))
    }

    /// A block sequence of strings (used for `notes`); omitted when empty.
    mutating func addBlock(_ key: String, _ values: [String]) {
        guard !values.isEmpty else { return }
        entries.append(YAMLEntry(key, .sequence(values.map(YAMLNode.string))))
    }

    /// A boolean emitted only when true.
    mutating func addTrue(_ key: String, _ value: Bool) {
        guard value else { return }
        entries.append(YAMLEntry(key, .bool(true)))
    }
}
