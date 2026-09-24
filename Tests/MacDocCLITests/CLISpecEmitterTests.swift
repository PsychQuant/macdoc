import Testing
import CLISpec

/// Unit tests for the deterministic YAML subset emitter behind `cli-spec.yaml`
/// (Spectra change `cli-spec-yaml`, requirement "Deterministic YAML
/// serialization"; PsychQuant/macdoc#72).
struct CLISpecEmitterTests {

    // The `##### Example: Scalar quoting` table of the cli-spec spec, row by row.
    @Test("scalar quoting follows the spec table", arguments: [
        ("web", "web"),
        ("word-to-md-swift", "word-to-md-swift"),
        ("stdout_or_file", "stdout_or_file"),
        ("144.0", "\"144.0\""),
        (".", "\".\""),
        ("yes", "\"yes\""),
        ("--to", "\"--to\""),
        ("macdoc pdf ocr", "\"macdoc pdf ocr\""),
        ("EZCon/GLM-OCR-8bit-mlx", "\"EZCon/GLM-OCR-8bit-mlx\""),
        ("say \"hi\"", "\"say \\\"hi\\\"\""),
        ("a\nb", "\"a\\nb\""),
        ("原生 macOS 文件處理工具", "\"原生 macOS 文件處理工具\""),
    ])
    func scalarQuoting(input: String, expected: String) {
        #expect(YAMLEmitter.scalar(input) == expected)
    }

    @Test("reserved words and non-identifier strings are quoted", arguments: [
        "true", "False", "NO", "on", "Off", "null", "y", "N", "", "_ok-1.x",
    ])
    func reservedWords(input: String) {
        let emitted = YAMLEmitter.scalar(input)
        if input == "_ok-1.x" {
            #expect(emitted == "_ok-1.x")
        } else {
            #expect(emitted == "\"\(input)\"")
        }
    }

    @Test("control characters and YAML line separators are escaped")
    func controlCharacters() {
        #expect(YAMLEmitter.scalar("a\tb\r\\") == "\"a\\tb\\r\\\\\"")
        #expect(YAMLEmitter.scalar("x\u{0001}y") == "\"x\\u0001y\"")
        #expect(YAMLEmitter.scalar("p\u{2028}q\u{0085}r\u{2029}") == "\"p\\u2028q\\u0085r\\u2029\"")
        #expect(YAMLEmitter.scalar("del\u{7F}") == "\"del\\u007F\"")
        #expect(YAMLEmitter.scalar("c1\u{80}\u{9F}") == "\"c1\\u0080\\u009F\"")
        #expect(YAMLEmitter.scalar("nc\u{FFFE}\u{FFFF}") == "\"nc\\uFFFE\\uFFFF\"")
        // U+00A0 and ordinary non-ASCII text stay literal.
        #expect(YAMLEmitter.scalar("nb\u{A0}sp 中") == "\"nb\u{A0}sp 中\"")
    }

    @Test("sequence items whose first entry is a block, and nested sequences")
    func nestedBlocks() {
        let document = YAMLNode.sequence([
            .mapping([
                YAMLEntry("paths", .sequence([
                    .mapping([YAMLEntry("command", .string("x")), YAMLEntry("note", .string("n"))]),  // "n" is a YAML 1.1 bool word → quoted
                ])),
                YAMLEntry("topic", .string("t")),
            ]),
            .sequence([.string("a"), .string("b")]),
        ])
        let actual = YAMLEmitter.emit(document)
        #expect(actual == """
        - paths:
            - command: x
              note: "n"
          topic: t
        -
          - a
          - b

        """, "\(actual.debugDescription)")
    }

    @Test("block and flow layout, header, booleans, integers and trailing newline")
    func layout() {
        let document = YAMLNode.mapping([
            YAMLEntry("schema_version", .int(1)),
            YAMLEntry("tool", .mapping([
                YAMLEntry("name", .string("macdoc")),
                YAMLEntry("version", .string("0.9.0")),
            ])),
            YAMLEntry("items", .sequence([
                .mapping([
                    YAMLEntry("path", .string("macdoc convert")),
                    YAMLEntry("names", .flow(["--to", "-t"])),
                    YAMLEntry("required", .bool(true)),
                    YAMLEntry("notes", .sequence([.string("a"), .string("b c")])),
                    YAMLEntry("options", .sequence([
                        .mapping([
                            YAMLEntry("names", .flow(["--x"])),
                            YAMLEntry("hidden", .bool(false)),
                        ]),
                    ])),
                ]),
                .mapping([YAMLEntry("path", .string("macdoc"))]),
            ])),
        ])

        let expected = """
        # first line
        #
        schema_version: 1
        tool:
          name: macdoc
          version: "0.9.0"
        items:
          - path: "macdoc convert"
            names: ["--to", "-t"]
            required: true
            notes:
              - a
              - "b c"
            options:
              - names: ["--x"]
                hidden: false
          - path: macdoc

        """
        #expect(YAMLEmitter.emit(document, headerComments: ["first line", ""]) == expected)
    }

    @Test("empty collections are written in flow form")
    func emptyCollections() {
        let document = YAMLNode.mapping([
            YAMLEntry("a", .flow([])),
            YAMLEntry("b", .sequence([])),
            YAMLEntry("c", .mapping([])),
        ])
        #expect(YAMLEmitter.emit(document) == "a: []\nb: []\nc: {}\n")
    }

    @Test("output has no trailing whitespace and exactly one final newline")
    func noTrailingWhitespace() {
        let document = YAMLNode.mapping([
            YAMLEntry("list", .sequence([
                .mapping([YAMLEntry("k", .string("v "))]),
                .string(""),
            ])),
        ])
        let text = YAMLEmitter.emit(document)
        #expect(text.hasSuffix("\n"))
        #expect(!text.hasSuffix("\n\n"))
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            #expect(line.last != " ", "trailing whitespace in line: \(line)")
        }
        #expect(text == "list:\n  - k: \"v \"\n  - \"\"\n")
    }
}
