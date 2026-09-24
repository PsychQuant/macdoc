import Testing
import Foundation
import CLISpec

/// Unit tests for the dump-help decoder, the builder and the overlay
/// validation behind `cli-spec.yaml`, run against synthetic dumps so every
/// rule is pinned independently of the real macdoc surface (Spectra change
/// `cli-spec-yaml`; PsychQuant/macdoc#72).
struct CLISpecBuilderTests {

    // MARK: - Synthetic inputs

    static let versionFlag = """
    {"kind":"flag","names":[{"kind":"long","name":"version"}],"preferredName":{"kind":"long","name":"version"},\
    "valueName":"version","isOptional":true,"isRepeating":false,"parsingStrategy":"default","shouldDisplay":true,\
    "abstract":"Show the version."}
    """
    static let helpFlag = """
    {"kind":"flag","names":[{"kind":"short","name":"h"},{"kind":"long","name":"help"}],\
    "preferredName":{"kind":"long","name":"help"},"valueName":"help","isOptional":true,"isRepeating":false,\
    "parsingStrategy":"default","shouldDisplay":true,"abstract":"Show help information."}
    """

    /// Three levels deep, with every argument feature the schema maps, the
    /// builtin flags on every command, and ArgumentParser's auto `help`
    /// subcommand under the root.
    static func dumpJSON(
        serializationVersion: Int = 0,
        alphaExtraField: String = "",
        idParsing: String = "upToNextOption"
    ) -> String {
        """
        {"serializationVersion":\(serializationVersion),"command":{
          "commandName":"tool","abstract":"Root tool","shouldDisplay":true,
          "arguments":[\(versionFlag),\(helpFlag)],
          "subcommands":[
            {"commandName":"alpha","abstract":"Alpha command","discussion":"Line one.\\nLine two.",
             "aliases":["a"],"shouldDisplay":true,"superCommands":["tool"]\(alphaExtraField),
             "arguments":[
               {"kind":"positional","valueName":"input","isOptional":false,"isRepeating":false,
                "parsingStrategy":"default","shouldDisplay":true,"abstract":"Input file"},
               {"kind":"option","names":[{"kind":"short","name":"o"},{"kind":"long","name":"output"}],
                "preferredName":{"kind":"long","name":"output"},"valueName":"output","isOptional":true,
                "isRepeating":false,"parsingStrategy":"default","shouldDisplay":true,"abstract":"Output path"},
               {"kind":"option","names":[{"kind":"long","name":"style"}],"valueName":"style","isOptional":true,
                "isRepeating":false,"parsingStrategy":"default","defaultValue":"web","allValues":["minimal","web"],
                "completionKind":{"list":{"values":["minimal","web"]}},
                "shouldDisplay":true,"sectionTitle":"Styling","abstract":"Style"},
               {"kind":"option","names":[{"kind":"long","name":"id"}],"valueName":"id","isOptional":true,
                "isRepeating":true,"parsingStrategy":"\(idParsing)","shouldDisplay":true,"abstract":"IDs"},
               {"kind":"flag","names":[{"kind":"long","name":"full"}],"valueName":"full","isOptional":true,
                "isRepeating":false,"parsingStrategy":"default","shouldDisplay":true,"abstract":"Full doc"},
               {"kind":"flag","names":[{"kind":"longWithSingleDash","name":"legacy"},{"kind":"long","name":"modern"}],
                "valueName":"modern","isOptional":true,"isRepeating":false,"parsingStrategy":"default",
                "shouldDisplay":false,"abstract":"Hidden flag"},
               \(versionFlag),\(helpFlag)
             ]},
            {"commandName":"group","abstract":"Group","defaultSubcommand":"leaf","shouldDisplay":true,
             "arguments":[\(versionFlag),\(helpFlag)],
             "subcommands":[
               {"commandName":"leaf","abstract":"Leaf","shouldDisplay":true,
                "arguments":[
                  {"kind":"positional","valueName":"rest","isOptional":true,"isRepeating":true,
                   "parsingStrategy":"allUnrecognized","shouldDisplay":false,"abstract":""},
                  \(versionFlag),\(helpFlag)
                ]},
               {"commandName":"other","shouldDisplay":false,"arguments":[\(versionFlag),\(helpFlag)]}
             ]},
            {"commandName":"help","abstract":"Show subcommand help information.","shouldDisplay":true,
             "arguments":[
               {"kind":"positional","valueName":"subcommands","isOptional":true,"isRepeating":true,
                "parsingStrategy":"default","shouldDisplay":true},
               {"kind":"flag","names":[{"kind":"short","name":"h"},{"kind":"long","name":"help"},
                {"kind":"longWithSingleDash","name":"help"}],"valueName":"help","isOptional":true,
                "isRepeating":false,"parsingStrategy":"default","shouldDisplay":false}
             ]}
          ]}}
        """
    }

    /// The same tree with `alpha --style` renamed to `--css`, for style checks.
    static let cssDumpJSON = dumpJSON().replacingOccurrences(
        of: #""name":"style"}],"valueName":"style""#, with: #""name":"css"}],"valueName":"css""#)

    static let provenance = CLISpecMetadata.Provenance(
        authority: "ArgumentParser declarations in Sources/Tool (code-first)",
        overlay: "Sources/Tool/Overlay.swift",
        regenerate: "make spec",
        contract: "test contract"
    )

    static func metadata(
        commands: [CLISpecMetadata.CommandInfo] = [],
        conversions: [CLISpecMetadata.Conversion] = [],
        overlaps: [CLISpecMetadata.Overlap] = [],
        dependencies: [CLISpecMetadata.ExternalDependency] = []
    ) -> CLISpecMetadata {
        CLISpecMetadata(
            provenance: provenance,
            commands: commands,
            conversions: conversions,
            overlaps: overlaps,
            externalDependencies: dependencies
        )
    }

    static func conversion(
        _ label: String,
        command: String = "tool alpha",
        from: [String] = ["aa"],
        to: String = "bb",
        options: [String] = [],
        styles: [String] = [],
        dependencies: [String] = []
    ) -> CLISpecMetadata.Conversion {
        CLISpecMetadata.Conversion(
            label: label, command: command, from: from, to: to, converter: "aa-to-bb-swift",
            output: .stdoutOrFile, options: options, styles: styles, dependencies: dependencies
        )
    }

    func generate(
        _ json: String = CLISpecBuilderTests.dumpJSON(),
        version: String = "1.2.3\n",
        metadata: CLISpecMetadata = CLISpecBuilderTests.metadata()
    ) throws -> String {
        try CLISpecGenerator.generate(dumpHelpJSON: Data(json.utf8), versionOutput: version, metadata: metadata)
    }

    // MARK: - Dump-help input is isolated behind a versioned decoder

    @Test("serializationVersion other than 0 is rejected by name")
    func unsupportedVersion() {
        #expect(throws: CLISpecError.unsupportedSerializationVersion(1)) {
            try generate(Self.dumpJSON(serializationVersion: 1))
        }
    }

    @Test("unknown JSON fields are ignored")
    func unknownFieldsTolerated() throws {
        let plain = try generate()
        let withExtra = try generate(Self.dumpJSON(alphaExtraField: #","futureField":true"#))
        #expect(plain == withExtra)
        // Every command and argument object (all carry "shouldDisplay"), plus the top level.
        let everywhere = Self.dumpJSON()
            .replacingOccurrences(of: #""shouldDisplay":"#, with: #""futureField":{"nested":[1,2]},"shouldDisplay":"#)
            .replacingOccurrences(of: #"{"serializationVersion":0,"#, with: #"{"serializationVersion":0,"futureTop":"x","#)
        #expect(everywhere != Self.dumpJSON())
        #expect(try generate(everywhere) == plain)
    }

    @Test("parsing strategies are re-spelled into project names", arguments: [
        ("upToNextOption", "parsing: up_to_next_option"),
        ("allUnrecognized", "parsing: all_unrecognized"),
        ("scanningForValue", "parsing: scanning_for_value"),
        ("unconditional", "parsing: unconditional"),
        ("allRemainingInput", "parsing: all_remaining_input"),
        ("postTerminator", "parsing: post_terminator"),
    ])
    func parsingSpelling(strategy: String, expectedLine: String) throws {
        let yaml = try generate(Self.dumpJSON(idParsing: strategy))
        #expect(yaml.contains("        " + expectedLine + "\n"))
    }

    @Test("default parsing strategy omits the key")
    func defaultParsingOmitted() throws {
        let yaml = try generate(Self.dumpJSON(idParsing: "default"))
        #expect(!yaml.contains("parsing: default"))
        #expect(!yaml.contains("parsing: up_to_next_option"))
    }

    @Test("an unknown parsing strategy or argument kind is a malformed dump")
    func unknownEnumerations() {
        let badStrategy = #expect(throws: CLISpecError.self) {
            try generate(Self.dumpJSON(idParsing: "somethingNew"))
        }
        #expect(badStrategy?.isMalformedDump == true)

        let badKind = Self.dumpJSON().replacingOccurrences(of: #""kind":"positional","valueName":"input""#,
                                                            with: #""kind":"subparser","valueName":"input""#)
        let kindError = #expect(throws: CLISpecError.self) {
            try generate(badKind)
        }
        #expect(kindError?.isMalformedDump == true)

        let badNameKind = Self.dumpJSON().replacingOccurrences(of: #"{"kind":"long","name":"full"}"#,
                                                               with: #"{"kind":"doubleDash","name":"full"}"#)
        #expect(badNameKind != Self.dumpJSON())
        let nameKindError = #expect(throws: CLISpecError.self) {
            try generate(badNameKind)
        }
        #expect(nameKindError?.isMalformedDump == true)
    }

    @Test("version output is trimmed; an empty one is rejected")
    func versionOutput() throws {
        #expect(try generate(version: "1.2.3\n").contains("\n  version: \"1.2.3\"\n"))
        #expect(throws: CLISpecError.emptyVersionOutput) {
            try generate(version: "\n")
        }
    }

    // MARK: - Derived surface, builtin normalization, argument mapping

    static let expectedSyntheticYAML = """
    # cli-spec.yaml — tool CLI specification (schema_version 1)
    # GENERATED FILE — do not edit by hand. Regenerate: make spec
    # Authority: ArgumentParser declarations in Sources/Tool (code-first)
    # Project metadata overlay: Sources/Tool/Overlay.swift
    # Contract: test contract
    schema_version: 1
    tool:
      name: tool
      version: "1.2.3"
      abstract: "Root tool"
    source:
      authority: "ArgumentParser declarations in Sources/Tool (code-first)"
      dump_help_serialization_version: 0
      overlay: "Sources/Tool/Overlay.swift"
      regenerate: "make spec"
    commands:
      - path: tool
        abstract: "Root tool"
        subcommands: [alpha, group]
      - path: "tool alpha"
        abstract: "Alpha command"
        discussion: "Line one.\\nLine two."
        aliases: [a]
        arguments:
          - name: input
            required: true
            help: "Input file"
        options:
          - names: ["--output", "-o"]
            value_name: output
            required: false
            help: "Output path"
          - names: ["--style"]
            value_name: style
            required: false
            default: web
            values: [minimal, web]
            section: Styling
            help: Style
          - names: ["--id"]
            value_name: id
            required: false
            repeating: true
            parsing: up_to_next_option
            help: IDs
        flags:
          - names: ["--full"]
            required: false
            help: "Full doc"
          - names: ["--modern", "-legacy"]
            required: false
            hidden: true
            help: "Hidden flag"
      - path: "tool group"
        abstract: Group
        default_subcommand: leaf
        subcommands: [leaf, other]
      - path: "tool group leaf"
        abstract: Leaf
        arguments:
          - name: rest
            required: false
            repeating: true
            parsing: all_unrecognized
            hidden: true
      - path: "tool group other"
        hidden: true

    """

    @Test("synthetic tree renders to the exact expected YAML")
    func exactSyntheticYAML() throws {
        let yaml = try generate()
        #expect(yaml == Self.expectedSyntheticYAML, "diff at line \(firstDifferingLine(yaml, Self.expectedSyntheticYAML))")
    }

    @Test("commands are in depth-first pre-order; builtins are dropped")
    func orderingAndBuiltins() throws {
        let document = try CLISpecBuilder.build(
            dumpHelpJSON: Data(Self.dumpJSON().utf8), versionOutput: "1.2.3", metadata: Self.metadata())
        #expect(document.commands.map(\.path) == ["tool", "tool alpha", "tool group", "tool group leaf", "tool group other"])
        #expect(document.commands[0].subcommands == ["alpha", "group"])
        #expect(document.tool.version == "1.2.3")
        let allNames = document.commands.flatMap { $0.options + $0.flags }.flatMap(\.names)
        #expect(!allNames.contains("--help"))
        #expect(!allNames.contains("-h"))
        #expect(!allNames.contains("-help"))
        #expect(!allNames.contains("--version"))
    }

    // MARK: - Project metadata overlay

    @Test("overlay facts appear under project and in the top-level sections")
    func overlayRendering() throws {
        let metadata = Self.metadata(
            commands: [
                CLISpecMetadata.CommandInfo(
                    path: "tool group other", status: .deprecated, replacement: "tool alpha",
                    dependencies: ["dep-b"], notes: ["First note.", "Second note."], docs: ["docs/x.md"]),
            ],
            conversions: [
                Self.conversion("Alpha → Beta", from: ["aa", "*"], options: ["--full", "--css"], styles: ["minimal"],
                                dependencies: ["dep-a", "dep-b", "dep-a"]),
                Self.conversion("Gamma → Beta", from: ["gg"], dependencies: ["dep-a"]),
            ],
            overlaps: [
                CLISpecMetadata.Overlap(topic: "Two ways", paths: [
                    CLISpecMetadata.OverlapPath(command: "tool alpha", usage: "tool alpha x", note: "Direct."),
                    CLISpecMetadata.OverlapPath(command: "tool group leaf", usage: "tool group leaf", note: "Indirect."),
                ]),
            ],
            dependencies: [
                CLISpecMetadata.ExternalDependency(id: "dep-a", kind: .cli, purpose: "Does A.", install: "brew install a"),
                CLISpecMetadata.ExternalDependency(id: "dep-b", kind: .networkService, purpose: "Does B."),
            ]
        )
        let yaml = try generate(Self.cssDumpJSON, metadata: metadata)

        #expect(yaml.contains("""
          - path: "tool group other"
            hidden: true
            project:
              status: deprecated
              replacement: "tool alpha"
              dependencies: [dep-b]
              notes:
                - "First note."
                - "Second note."
              docs: ["docs/x.md"]
        conversions:
          - label: "Alpha → Beta"
            command: "tool alpha"
            from: [aa, "*"]
            to: bb
            converter: aa-to-bb-swift
            output: stdout_or_file
            options: ["--full", "--css"]
            styles: [minimal]
            dependencies: [dep-a, dep-b, dep-a]
          - label: "Gamma → Beta"
            command: "tool alpha"
            from: [gg]
            to: bb
            converter: aa-to-bb-swift
            output: stdout_or_file
            dependencies: [dep-a]
        overlaps:
          - topic: "Two ways"
            paths:
              - command: "tool alpha"
                usage: "tool alpha x"
                note: Direct.
              - command: "tool group leaf"
                usage: "tool group leaf"
                note: Indirect.
        external_dependencies:
          - id: dep-a
            kind: cli
            purpose: "Does A."
            install: "brew install a"
            used_by: ["Alpha → Beta", "Gamma → Beta"]
          - id: dep-b
            kind: network_service
            purpose: "Does B."
            used_by: ["tool group other", "Alpha → Beta"]

        """))
        #expect(yaml.hasSuffix("used_by: [\"tool group other\", \"Alpha → Beta\"]\n"))
    }

    // MARK: - Overlay cross-reference validation (closed list of eight classes)

    @Test("unknownCommandPath: command entry, conversion command, overlap command")
    func unknownCommandPath() {
        let stale = CLISpecMetadata.CommandInfo(path: "tool pdf transcribe", status: .deprecated)
        #expect(throws: CLISpecError.unknownCommandPath("tool pdf transcribe")) {
            try generate(metadata: Self.metadata(commands: [stale]))
        }
        #expect(throws: CLISpecError.unknownCommandPath("tool beta")) {
            try generate(metadata: Self.metadata(conversions: [Self.conversion("X", command: "tool beta")]))
        }
        let overlap = CLISpecMetadata.Overlap(topic: "t", paths: [
            CLISpecMetadata.OverlapPath(command: "tool gone", usage: "u", note: "n"),
        ])
        #expect(throws: CLISpecError.unknownCommandPath("tool gone")) {
            try generate(metadata: Self.metadata(overlaps: [overlap]))
        }
        #expect(CLISpecError.unknownCommandPath("tool pdf transcribe").description.contains("tool pdf transcribe"))
    }

    @Test("duplicateCommandMetadata")
    func duplicateCommandMetadata() {
        let entry = CLISpecMetadata.CommandInfo(path: "tool alpha", status: .active)
        #expect(throws: CLISpecError.duplicateCommandMetadata("tool alpha")) {
            try generate(metadata: Self.metadata(commands: [entry, entry]))
        }
    }

    @Test("unknownOption names the label and the option")
    func unknownOption() {
        let error = CLISpecError.unknownOption(label: "X", option: "--no-such-flag")
        #expect(throws: error) {
            try generate(metadata: Self.metadata(conversions: [Self.conversion("X", options: ["--no-such-flag"])]))
        }
        #expect(error.description.contains("X") && error.description.contains("--no-such-flag"))
        // Short spellings are not accepted: options are referenced by long name.
        #expect(throws: CLISpecError.unknownOption(label: "X", option: "-o")) {
            try generate(metadata: Self.metadata(conversions: [Self.conversion("X", options: ["-o"])]))
        }
    }

    @Test("unknownStyle: value outside --css values, or command without --css")
    func unknownStyle() {
        // The synthetic `alpha` command has `--style`, not `--css`.
        #expect(throws: CLISpecError.unknownStyle(label: "X", style: "minimal")) {
            try generate(metadata: Self.metadata(conversions: [Self.conversion("X", styles: ["minimal"])]))
        }
        let css = Self.cssDumpJSON
        #expect(throws: CLISpecError.unknownStyle(label: "X", style: "sepia")) {
            try generate(css, metadata: Self.metadata(conversions: [Self.conversion("X", styles: ["sepia"])]))
        }
        #expect(throws: Never.self) {
            try generate(css, metadata: Self.metadata(conversions: [Self.conversion("X", styles: ["minimal", "web"])]))
        }
    }

    @Test("duplicateConversion by label and by (extension, target) pair")
    func duplicateConversion() {
        #expect(throws: CLISpecError.duplicateConversion("Word → HTML")) {
            try generate(metadata: Self.metadata(conversions: [
                Self.conversion("Word → HTML", from: ["aa"]), Self.conversion("Word → HTML", from: ["cc"]),
            ]))
        }
        #expect(throws: CLISpecError.duplicateConversion("html → pdf")) {
            try generate(metadata: Self.metadata(conversions: [
                Self.conversion("One", from: ["html"], to: "pdf"),
                Self.conversion("Two", from: ["htm", "html"], to: "pdf"),
            ]))
        }
        // A repeated extension inside one conversion is not a second conversion.
        #expect(throws: Never.self) {
            try generate(metadata: Self.metadata(conversions: [Self.conversion("One", from: ["html", "html"], to: "pdf")]))
        }
        // The same pair on different commands is not a duplicate.
        #expect(throws: Never.self) {
            try generate(metadata: Self.metadata(conversions: [
                Self.conversion("One", from: ["html"], to: "pdf"),
                Self.conversion("Two", command: "tool group leaf", from: ["html"], to: "pdf"),
            ]))
        }
    }

    @Test("unknownDependency, duplicateDependency, unusedDependency")
    func dependencyValidation() {
        #expect(throws: CLISpecError.unknownDependency(reference: "X", id: "pandoc")) {
            try generate(metadata: Self.metadata(conversions: [Self.conversion("X", dependencies: ["pandoc"])]))
        }
        let commandRef = CLISpecMetadata.CommandInfo(path: "tool alpha", status: .active, dependencies: ["pandoc"])
        #expect(throws: CLISpecError.unknownDependency(reference: "tool alpha", id: "pandoc")) {
            try generate(metadata: Self.metadata(commands: [commandRef]))
        }
        let dep = CLISpecMetadata.ExternalDependency(id: "latex2rtf", kind: .cli, purpose: "p")
        #expect(throws: CLISpecError.duplicateDependency("latex2rtf")) {
            try generate(metadata: Self.metadata(
                conversions: [Self.conversion("X", dependencies: ["latex2rtf"])], dependencies: [dep, dep]))
        }
        #expect(throws: CLISpecError.unusedDependency("latex2rtf")) {
            try generate(metadata: Self.metadata(dependencies: [dep]))
        }
    }

    // MARK: - Deterministic YAML serialization

    @Test("repeated generation and key-reordered JSON are byte-identical")
    func determinism() throws {
        let first = try generate()
        let second = try generate()
        let object = try JSONSerialization.jsonObject(with: Data(Self.dumpJSON().utf8))
        let sorted = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        let third = try CLISpecGenerator.generate(
            dumpHelpJSON: sorted, versionOutput: "1.2.3\n", metadata: Self.metadata())
        #expect(first == second)
        #expect(first == third)
    }
}

extension CLISpecError {
    var isMalformedDump: Bool {
        if case .malformedDump = self { return true }
        return false
    }
}

/// 1-based line number of the first difference between two texts (0 when equal).
func firstDifferingLine(_ lhs: String, _ rhs: String) -> Int {
    let left = lhs.components(separatedBy: "\n")
    let right = rhs.components(separatedBy: "\n")
    for index in 0..<max(left.count, right.count) {
        let l = index < left.count ? left[index] : nil
        let r = index < right.count ? right[index] : nil
        if l != r { return index + 1 }
    }
    return 0
}
