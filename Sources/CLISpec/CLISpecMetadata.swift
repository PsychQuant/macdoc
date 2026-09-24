// Types of the project metadata overlay for cli-spec.yaml (PsychQuant/macdoc#72,
// design "Metadata overlay as a compiler-checked Swift literal").
//
// The overlay carries only facts ArgumentParser cannot express. Every
// reference it makes (command paths, option names, CSS styles, dependency ids)
// is cross-checked by `CLISpecBuilder` against the derived surface.

public struct CLISpecMetadata: Equatable, Sendable {

    /// Where the specification comes from; printed in the header and the
    /// `source` block.
    public struct Provenance: Equatable, Sendable {
        public var authority: String
        public var overlay: String
        public var regenerate: String
        public var contract: String

        public init(authority: String, overlay: String, regenerate: String, contract: String) {
            self.authority = authority
            self.overlay = overlay
            self.regenerate = regenerate
            self.contract = contract
        }
    }

    public enum CommandStatus: String, Equatable, Sendable {
        case active
        case deprecated
        case removed
    }

    /// Overlay facts about one command path, rendered under its `project` key.
    public struct CommandInfo: Equatable, Sendable {
        public var path: String
        public var status: CommandStatus
        public var replacement: String?
        public var dependencies: [String]
        public var notes: [String]
        public var docs: [String]

        public init(
            path: String,
            status: CommandStatus,
            replacement: String? = nil,
            dependencies: [String] = [],
            notes: [String] = [],
            docs: [String] = []
        ) {
            self.path = path
            self.status = status
            self.replacement = replacement
            self.dependencies = dependencies
            self.notes = notes
            self.docs = docs
        }
    }

    /// How a conversion delivers its result.
    public enum OutputMode: String, Equatable, Sendable {
        /// stdout unless `--output` is given.
        case stdoutOrFile = "stdout_or_file"
        /// Always a file: `--output`, or a path derived from the input.
        case file
        /// A directory: `--output`, or a path derived from the input.
        case directory
        /// A directory unless `--stdout` is given.
        case directoryOrStdout = "directory_or_stdout"
    }

    /// One conversion macdoc offers. `label` equals the first cell of the
    /// matching CONVERSIONS.md "Converter Details" row.
    public struct Conversion: Equatable, Sendable {
        public var label: String
        public var command: String
        /// Source extensions without dots; `"*"` means any extension.
        public var from: [String]
        public var to: String
        public var converter: String
        public var output: OutputMode
        /// Route-specific long option names (never `--output` / `--stdout`).
        public var options: [String]
        /// Accepted `--css` values for this route.
        public var styles: [String]
        public var dependencies: [String]
        public var notes: [String]

        public init(
            label: String,
            command: String,
            from: [String],
            to: String,
            converter: String,
            output: OutputMode,
            options: [String] = [],
            styles: [String] = [],
            dependencies: [String] = [],
            notes: [String] = []
        ) {
            self.label = label
            self.command = command
            self.from = from
            self.to = to
            self.converter = converter
            self.output = output
            self.options = options
            self.styles = styles
            self.dependencies = dependencies
            self.notes = notes
        }
    }

    public struct OverlapPath: Equatable, Sendable {
        public var command: String
        public var usage: String
        public var note: String

        public init(command: String, usage: String, note: String) {
            self.command = command
            self.usage = usage
            self.note = note
        }
    }

    /// Several command paths that reach similar results; the notes say which
    /// one to use when.
    public struct Overlap: Equatable, Sendable {
        public var topic: String
        public var paths: [OverlapPath]

        public init(topic: String, paths: [OverlapPath]) {
            self.topic = topic
            self.paths = paths
        }
    }

    public enum DependencyKind: String, Equatable, Sendable {
        case cli
        case application
        case networkService = "network_service"
    }

    public struct ExternalDependency: Equatable, Sendable {
        public var id: String
        public var kind: DependencyKind
        public var purpose: String
        public var install: String?

        public init(id: String, kind: DependencyKind, purpose: String, install: String? = nil) {
            self.id = id
            self.kind = kind
            self.purpose = purpose
            self.install = install
        }
    }

    public var provenance: Provenance
    public var commands: [CommandInfo]
    public var conversions: [Conversion]
    public var overlaps: [Overlap]
    public var externalDependencies: [ExternalDependency]

    public init(
        provenance: Provenance,
        commands: [CommandInfo] = [],
        conversions: [Conversion] = [],
        overlaps: [Overlap] = [],
        externalDependencies: [ExternalDependency] = []
    ) {
        self.provenance = provenance
        self.commands = commands
        self.conversions = conversions
        self.overlaps = overlaps
        self.externalDependencies = externalDependencies
    }
}
