## Purpose

Define `cli-spec.yaml`, the generated, versioned, machine-readable specification of the macdoc CLI. The file is derived from the ArgumentParser command declarations (code-first) plus an explicit project metadata overlay, serialized deterministically, and kept honest by drift, route and documentation consistency checks.

## ADDED Requirements

### Requirement: Code-first authority and generated-file header

The ArgumentParser declarations of the `macdoc` executable SHALL be the only authority for command paths, positional arguments, options, flags, required/optional status, repetition, defaults, allowed values and help text in `cli-spec.yaml`. The file SHALL live at the repository root, SHALL be produced only by `CLISpecGenerator.generate(dumpHelpJSON:versionOutput:metadata:)`, and SHALL begin with comment lines stating that it is generated, that it must not be edited by hand, the regeneration command `make cli-spec`, the authority, and the overlay location. The `macdoc` executable SHALL NOT link the `CLISpec` target, so generating the specification never changes CLI behavior.

#### Scenario: Header identifies the file as generated

- **WHEN** `cli-spec.yaml` is generated
- **THEN** its first five lines are comments beginning with `# ` that contain, in order, the file title with `schema_version 1`, the phrase `GENERATED FILE` together with `make cli-spec`, the authority `Sources/MacDocCLI`, the overlay path `Sources/CLISpec/MacDocCLIMetadata.swift`, and the reference `PsychQuant/macdoc#72`

#### Scenario: Executable is unaffected

- **WHEN** Package.swift is inspected after the change
- **THEN** the `MacDocCLI` executable target's dependency list does not contain `CLISpec`, and only the `MacDocCLITests` test target depends on it

### Requirement: Dump-help input is isolated behind a versioned decoder

The generator SHALL read the command surface from the JSON printed by `macdoc --experimental-dump-help` and the tool version from the trimmed output of `macdoc --version`. It SHALL accept only `serializationVersion` 0, SHALL ignore JSON fields it does not use, and SHALL fail with a `CLISpecError` naming the problem when the version differs, when the JSON does not decode, when an argument `kind`, name kind or `parsingStrategy` is not one it knows, or when the version output is empty. Fields the schema needs SHALL be validated per kind, and a field that is absent or empty SHALL fail with `missingRequiredField(command:element:field:)` naming the command path, the element (`<kind> argument #<n>` by 1-based position in the command's argument list, or `subcommand #<n>`) and the field: every command needs a non-empty `commandName`; a positional needs a non-empty `valueName`; an option needs non-empty `names` with every name non-empty, and a non-empty `valueName`; a flag needs non-empty `names` with every name non-empty. Structural fields that the decoder requires (`kind`, `isOptional`, `isRepeating`, `parsingStrategy`, `shouldDisplay`) fail as `malformedDump` when absent. Unknown extra fields remain tolerated. The YAML `schema_version` SHALL be owned by the project and SHALL NOT change when only the dump format changes.

#### Scenario: Unsupported serialization version

- **GIVEN** a dump whose top-level `serializationVersion` is 1
- **WHEN** the generator runs
- **THEN** it throws `CLISpecError.unsupportedSerializationVersion(1)` and produces no output

#### Scenario: Unknown fields are tolerated

- **GIVEN** a valid version-0 dump in which every command object carries an extra field `"futureField": true`
- **WHEN** the generator runs
- **THEN** the output is byte-identical to the output for the same dump without that field

##### Example: Version and parsing-strategy spellings

| Dump input | Result |
| ---------- | ------ |
| `serializationVersion: 0` | accepted |
| `serializationVersion: 1` | `unsupportedSerializationVersion(1)` |
| `parsingStrategy: "upToNextOption"` | emitted as `parsing: up_to_next_option` |
| `parsingStrategy: "allUnrecognized"` | emitted as `parsing: all_unrecognized` |
| `parsingStrategy: "default"` | `parsing` key omitted |
| `parsingStrategy: "somethingNew"` | decoding fails (`malformedDump`) |
| `macdoc --version` prints `"0.9.0\n"` | `tool.version: "0.9.0"` |
| `macdoc --version` prints `"\n"` | `emptyVersionOutput` |
| option `names` renamed to `spellings` | `missingRequiredField(command: "tool alpha", element: "option argument #2", field: "names")` |
| option `"names": []` | `missingRequiredField(…, field: "names")` |
| positional without `valueName` | `missingRequiredField(…, element: "positional argument #1", field: "valueName")` |
| flag name `""` | `missingRequiredField(…, field: "names")` |
| subcommand `"commandName": ""` | `missingRequiredField(command: "tool group", element: "subcommand #1", field: "commandName")` |
| flag without `isOptional` | `malformedDump` |

### Requirement: Derived command surface and ordering

The `commands` sequence SHALL contain one entry per command in depth-first pre-order, starting with the root and visiting subcommands in their declaration order. Each entry SHALL use these keys in this order, omitting a key whose value is absent or empty: `path` (space-joined invocation path starting with `macdoc`), `abstract`, `discussion`, `aliases`, `hidden` (only when the command is not displayed), `default_subcommand`, `subcommands` (child names), `arguments` (positionals), `options`, `flags`, `project` (overlay; see the overlay requirement). Within `arguments`, `options` and `flags`, entries SHALL keep declaration order.

#### Scenario: Nested subcommand path

- **WHEN** the specification is generated from the current binary
- **THEN** an entry with `path: "macdoc pdf ocr"` exists, appears after `path: "macdoc pdf render"` and before `path: "macdoc pdf blocks"`, and the `macdoc pdf` entry has `default_subcommand: status`

##### Example: Command order prefix

- **GIVEN** the current declarations
- **WHEN** the specification is generated
- **THEN** the first eight `path` values are `macdoc`, `macdoc convert`, `macdoc pdf`, `macdoc pdf init`, `macdoc pdf segment`, `macdoc pdf render`, `macdoc pdf ocr`, `macdoc pdf blocks`

#### Scenario: Config document subtree

- **WHEN** the specification is generated from the current binary
- **THEN** the `macdoc config document` entry lists `subcommands: [show, set-default, import-official]`, and `macdoc config document set-default` has one positional `profile` with `required: true` and `values: [inherit, official]` plus an option `--config`

### Requirement: Builtin surface normalization

The generator SHALL drop, from every command, each flag whose long names include `help` or `version`, and SHALL drop the subcommand named `help` that ArgumentParser adds directly under the root, including its name from the root's `subcommands` list. The version string SHALL appear once, as `tool.version`. No other argument or command SHALL be dropped; hidden arguments SHALL be kept and marked `hidden: true`.

#### Scenario: Builtins absent, hidden shim argument present

- **WHEN** the specification is generated from the current binary
- **THEN** no entry lists `--help`, `-h`, `-help` or `--version` in any `names` list, no entry has `path: "macdoc help"`, the root lists `subcommands: [convert, pdf, bib, config, ocr, docx, word]`, and the `macdoc ocr` entry has one positional `ignored` with `repeating: true`, `parsing: all_unrecognized` and `hidden: true`

### Requirement: Argument field mapping

Every positional, option and flag entry SHALL use these keys in this order, omitting absent or empty values: `name` (positionals only: the value name), `names` (options and flags: every spelling, long names first, then single-dash long names, then short names, each group in declaration order; long names rendered `--x`, single-dash `-x`, short `-x`), `value_name` (options only), `required` (always present: `true` exactly when the dump marks the argument non-optional), `repeating` (only when `true`), `parsing` (only when the strategy is not `default`), `default`, `values` (allowed values in declaration order), `hidden` (only when `true`), `section`, `help` (the argument's abstract), `discussion`.

#### Scenario: Required option with no default

- **WHEN** the specification is generated from the current binary
- **THEN** the `macdoc convert` entry's first option renders exactly as the lines below

##### Example: convert --to and --css

- **GIVEN** the `convert` declarations `@Option(name: .long, help: "Target format (md, html, docx, pdf, json, marker, tokens)") var to: String` and `@Option(name: .long, help: "CSS style: minimal|web (bib), dark|light (srt)") var css: CSSStyle = .web`
- **WHEN** the specification is generated
- **THEN** the options contain these two blocks:

```yaml
      - names: ["--to"]
        value_name: to
        required: true
        help: "Target format (md, html, docx, pdf, json, marker, tokens)"
```

```yaml
      - names: ["--css"]
        value_name: css
        required: false
        default: web
        values: [minimal, web, dark, light]
        help: "CSS style: minimal|web (bib), dark|light (srt)"
```

#### Scenario: Name ordering and repeating options

- **WHEN** the specification is generated from the current binary
- **THEN** `macdoc bib to-html`'s output option has `names: ["--output", "-o"]` although it is declared `[.short, .long]`, its `--key` option has `repeating: true`, and `macdoc word reverse`'s `--slot` option has `value_name: "name=paraId"` and `repeating: true`

#### Scenario: Word render required output

- **WHEN** the specification is generated from the current binary
- **THEN** `macdoc word render` has a required positional `input`, a required option `--to-docx`, optional options `--profile` (values `[inherit, official]`), `--document-config` and `--verify-against`, and a flag `--force` with `required: false`

### Requirement: Project metadata overlay

Facts that ArgumentParser cannot express SHALL come only from the Swift overlay `MacDocCLIMetadata.overlay` and SHALL appear only in these places: a command's `project` mapping (keys in order `status`, `replacement`, `dependencies`, `notes`, `docs`; `status` is one of `active`, `deprecated`, `removed`; the mapping is emitted only for commands that have an overlay entry, and a command without one is active), and the top-level sequences `conversions`, `overlaps` and `external_dependencies`. A conversion SHALL use the keys `label`, `command`, `from` (source extensions without dots; `"*"` means any extension), `to`, `converter`, `output`, `options`, `styles`, `dependencies`, `notes` in that order, where `output` is one of `stdout_or_file` (stdout unless `--output`), `file` (writes `--output` or a path derived from the input), `directory` (writes a directory) and `directory_or_stdout` (writes a directory unless `--stdout`), and `options` lists only route-specific options (never `--output` or `--stdout`). An overlap SHALL use the keys `topic` and `paths`, each path using `command`, `usage`, `note`. An external dependency SHALL use the keys `id`, `kind` (`cli`, `application` or `network_service`), `purpose`, `install`, `used_by`. In all overlay-derived mappings a key whose value is absent or empty SHALL be omitted, exactly as for command and argument entries. For external dependencies, `used_by` is derived by the generator: the command paths (in command order) and then the conversion labels (in conversion order) that reference the id, without duplicates.

#### Scenario: Removed top-level ocr shim

- **WHEN** the specification is generated
- **THEN** the `macdoc ocr` entry's `project` has `status: removed` and a `replacement` naming `bestocr` and `https://github.com/PsychQuant/bestOCR`

#### Scenario: Deprecated pdf block pipeline

- **WHEN** the specification is generated
- **THEN** `macdoc pdf blocks`, `macdoc pdf transcribe`, `macdoc pdf transcribe-pages` and `macdoc pdf resume` each have `project.status: deprecated` and `project.replacement: "macdoc pdf ocr"`

#### Scenario: Overlapping PDF paths are documented

- **WHEN** the specification is generated
- **THEN** an overlap entry lists, as separate paths, `macdoc convert` with usage `macdoc convert --to md file.pdf`, `macdoc pdf ocr`, and `macdoc ocr`, and its notes distinguish the PDFKit text layer, page-image GLM-OCR inside the PDF → LaTeX project pipeline, and the removed shim

##### Example: Selected conversions

| label | command | from | to | output | options | styles | dependencies |
| ----- | ------- | ---- | -- | ------ | ------- | ------ | ------------ |
| Word → Markdown | macdoc convert | [docx] | md | stdout_or_file | [--frontmatter, --hard-breaks] | | |
| HTML → PDF | macdoc convert | [html, htm] | pdf | file | | | [playwright] |
| SRT → HTML | macdoc convert | [srt] | html | stdout_or_file | [--full, --css] | [dark, light] | |
| 舊版 Note → HTML | macdoc convert | [note, ntb] | html | directory_or_stdout | [--full, --css] | [dark, light] | |
| PDF → LaTeX | macdoc pdf | [pdf] | tex | directory | | | |
| UTF-8 text → Token count | macdoc convert | ["*"] | tokens | stdout_or_file | [--model, --allow-network] | | [anthropic-api] |

#### Scenario: Dependency usage is derived

- **WHEN** the specification is generated
- **THEN** the `playwright` external dependency has `used_by: ["HTML → PDF"]`, and every catalog entry's `used_by` is non-empty

### Requirement: Overlay cross-reference validation

The builder SHALL reject the overlay with a `CLISpecError` whose description names the offending value when any of the following holds. This is a closed list of eight failure classes; a condition not listed here SHALL NOT be rejected by inference from these: (1) `unknownCommandPath` — a command entry, a conversion's `command`, or an overlap path's `command` names a path absent from the derived surface; (2) `duplicateCommandMetadata` — two command entries share a path; (3) `unknownOption` — a conversion option is not a long name of an option or flag declared on the conversion's command; (4) `unknownStyle` — a conversion style is not among the allowed values of the `--css` option of the conversion's command, or that command has no `--css` option; (5) `duplicateConversion` — two conversions share a label, or two conversions on the same command share a (source extension, target) pair (an extension repeated inside one conversion is not a second conversion and is not rejected); (6) `unknownDependency` — a command or conversion references an id absent from the catalog; (7) `duplicateDependency` — two catalog entries share an id; (8) `unusedDependency` — a catalog entry is referenced by no command and no conversion.

#### Scenario: Stale command path

- **GIVEN** an overlay command entry for `macdoc pdf transcribe` and a dump in which `pdf` no longer declares `transcribe`
- **WHEN** the generator runs
- **THEN** it throws `unknownCommandPath("macdoc pdf transcribe")`

##### Example: Validation failures

| Overlay defect | Error |
| -------------- | ----- |
| conversion option `--no-such-flag` on `macdoc convert` | `unknownOption` naming the label and `--no-such-flag` |
| conversion style `sepia` on `macdoc convert` | `unknownStyle` naming the label and `sepia` |
| two conversions labelled `Word → HTML` | `duplicateConversion` naming `Word → HTML` |
| conversions `[html] → pdf` and `[htm, html] → pdf` on `macdoc convert` | `duplicateConversion` naming `html → pdf` |
| conversion dependency `pandoc` not in the catalog | `unknownDependency` naming `pandoc` |
| catalog entry `latex2rtf` referenced by nothing | `unusedDependency` naming `latex2rtf` |

### Requirement: Deterministic YAML serialization

For the same dump JSON, version output and overlay, the generator SHALL return byte-identical text, independent of JSON object key order. Serialization SHALL follow these rules: two-space indentation; mapping keys in the orders fixed by this specification; sequences whose elements are mappings, and `notes`, in block style with `- ` items indented two spaces under their key; sequences of scalars other than `notes` in flow style `[a, b]`; a string is written plain only when it starts with an ASCII letter or `_`, contains only ASCII letters, digits, `_`, `.` and `-`, and is not (case-insensitively) `true`, `false`, `yes`, `no`, `on`, `off`, `null`, `y` or `n`, and otherwise in double quotes with `\\`, `\"`, `\n`, `\r`, `\t` escapes and `\uXXXX` for every other character YAML forbids unescaped (C0 controls, DEL, the C1 controls U+0080–U+009F, U+2028, U+2029, U+FFFE, U+FFFF); booleans as `true` / `false`; integers in decimal; non-ASCII characters written as UTF-8; LF line endings; no trailing whitespace; exactly one newline at end of file. Header comment text SHALL be split at line breaks (LF, CR, CRLF, U+0085, U+2028, U+2029) into physical lines, each written as `# ` followed by the line with trailing spaces and tabs removed, or as `#` when that leaves it empty; within a comment line, every character YAML forbids other than tab (C0 controls, DEL, C1 controls, U+FFFE, U+FFFF) SHALL be written as the visible text `\uXXXX`.

#### Scenario: Multi-line header comment

- **GIVEN** a header comment `a` + LF + `b` + CRLF + `c` + U+0001
- **WHEN** the document is emitted
- **THEN** the header lines are `# a`, `# b` and `# c\u0001`

#### Scenario: Repeated generation is byte-identical

- **WHEN** the generator runs twice on the same inputs, and once more on the same dump re-serialized with sorted keys
- **THEN** the three outputs are byte-identical

##### Example: Scalar quoting

| String | Emitted |
| ------ | ------- |
| `web` | `web` |
| `word-to-md-swift` | `word-to-md-swift` |
| `stdout_or_file` | `stdout_or_file` |
| `144.0` | `"144.0"` |
| `.` | `"."` |
| `yes` | `"yes"` |
| `--to` | `"--to"` |
| `macdoc pdf ocr` | `"macdoc pdf ocr"` |
| `EZCon/GLM-OCR-8bit-mlx` | `"EZCon/GLM-OCR-8bit-mlx"` |
| `say "hi"` | `"say \"hi\""` |
| `a` + LF + `b` | `"a\nb"` |
| `x` + U+0080 + `y` | `"x\u0080y"` |
| `原生 macOS 文件處理工具` | `"原生 macOS 文件處理工具"` |

### Requirement: Drift contract for the committed specification

The test suite SHALL regenerate the specification from the freshly built binary and compare it byte-for-byte with the committed `cli-spec.yaml`. On mismatch the test SHALL fail with a message naming the first differing line number and both line contents, and stating `make cli-spec` as the fix. `make cli-spec` SHALL be the only documented way to rewrite the file: it runs `swift build` and then that test with `MACDOC_RECORD_CLI_SPEC=1` set for that one invocation, and in that mode the test SHALL write the generated text to `cli-spec.yaml` and pass. Record mode SHALL require the exact value `1`, and SHALL be refused whenever the environment variable `CI` is present (with any value, including empty): the test SHALL then fail without writing, with a message naming `CI`, `MACDOC_RECORD_CLI_SPEC` and `make cli-spec`.

#### Scenario: Stale committed file

- **GIVEN** a committed `cli-spec.yaml` whose `macdoc convert` `--to` help differs from the code
- **WHEN** `swift test --filter CLISpecDriftTests` runs without `MACDOC_RECORD_CLI_SPEC`
- **THEN** the test fails and its message contains the first differing line number and `make cli-spec`

#### Scenario: Record mode

- **WHEN** `make cli-spec` runs outside CI
- **THEN** `cli-spec.yaml` contains exactly the generated text and a subsequent `swift test --filter CLISpecDriftTests` passes

#### Scenario: Record mode refused under CI

- **GIVEN** `CI=true` and an inherited `MACDOC_RECORD_CLI_SPEC=1`
- **WHEN** the drift test runs
- **THEN** it fails without writing `cli-spec.yaml`, and its message names `CI`, `MACDOC_RECORD_CLI_SPEC` and `make cli-spec`

##### Example: Record-mode switch values

| MACDOC_RECORD_CLI_SPEC | CI | Behavior |
| ---------------------- | -- | -------- |
| unset | unset | compare |
| `1` | unset | write and pass |
| `true` | unset | compare |
| `0` | unset | compare |
| unset | `true` | compare |
| `1` | `true` | refuse: fail without writing |
| `1` | empty | refuse: fail without writing |

### Requirement: Convert routes match the binary's dispatch

For the conversions whose `command` is `macdoc convert` and whose `from` is not `"*"`, let E be the union of their source extensions with the probe vocabulary's extensions, and T the union of their targets with the probe vocabulary's targets. The probe vocabulary is a fixed list kept in the route-probe test; it SHALL contain every source extension and target used by those conversions (so removing a conversion from the overlay while the binary still dispatches it is detected) plus candidate formats (sources `txt`, `rtf`, `odt`, `epub`, `pptx`, `xlsx`, `csv`, `typ`, `ipynb`, `mdocx`; targets `txt`, `rtf`, `epub`, `tex`, `pptx`, `srt`). For every pair (e, t) in E × T the probe SHALL run `macdoc convert --to t --output <temp path> [--css <first style of the conversion>] <temp dir>/probe.e` with `PATH=/usr/bin:/bin`. When (e, t) belongs to a listed conversion, the input SHALL be a real fixture of that format (a valid document the route can convert) and the probe SHALL require positive evidence that the route itself ran: exit status 0 and a non-empty output file or non-empty output directory at the `--output` path, or — only for the conversions in the closed in-route diagnostics table of the probe test, which contains exactly `HTML → PDF` with `需要 playwright CLI` — a non-zero exit with that route's own diagnostic. The mere absence of `不支援從` SHALL NOT count as evidence. When (e, t) is not listed, the input SHALL be an empty file and the probe SHALL require a non-zero exit with stderr containing `不支援從 .e 轉換到 t`.

#### Scenario: Listed and unlisted pairs

- **WHEN** the route probe runs against the current binary and overlay
- **THEN** every listed pair converts its fixture successfully (or, for HTML → PDF, prints `需要 playwright CLI`) and every unlisted pair is rejected with the named diagnostic

#### Scenario: A route blocked before its converter is detected

- **GIVEN** a binary whose `(tex, docx)` dispatch case throws a validation error before calling its converter
- **WHEN** the route probe runs
- **THEN** the `(tex, docx)` probe fails, although stderr does not contain `不支援從`

##### Example: Probe expectations

| Pair | Expected |
| ---- | -------- |
| (docx, md) | exit 0, non-empty output file |
| (docx, marker) | exit 0, non-empty output directory |
| (srt, html) with `--css dark` | exit 0, non-empty output file |
| (htm, pdf) | non-zero exit, `需要 playwright CLI` (playwright kept off PATH) |
| (ntb, pdf) | exit 0 on a legacy `.note` container named `.ntb` |
| (srt, md) | `不支援從 .srt 轉換到 md` |
| (tex, html) | `不支援從 .tex 轉換到 html` |
| (bib, docx) | `不支援從 .bib 轉換到 docx` |
| (pdf, tex) | `不支援從 .pdf 轉換到 tex` (PDF → LaTeX is the `macdoc pdf` pipeline) |
| (txt, md) | `不支援從 .txt 轉換到 md` (candidate format) |

### Requirement: CONVERSIONS.md agrees with the specification

The set of first-cell labels of the data rows of the table under the `## Converter Details` heading of CONVERSIONS.md SHALL equal the set of `conversions[].label` values of the specification. A mismatch SHALL fail the check and list the labels present on only one side.

#### Scenario: Route documented on both sides

- **WHEN** the consistency check runs
- **THEN** it passes, and the labels `Word → Marker`, `HTML → PDF`, `LaTeX → Word`, `PDF → LaTeX` and `UTF-8 text → Token count` are present on both sides

#### Scenario: Undocumented route

- **GIVEN** a CONVERSIONS.md Converter Details table without a `HTML → PDF` row
- **WHEN** the consistency check runs
- **THEN** it fails and names `HTML → PDF` as present only in the specification
