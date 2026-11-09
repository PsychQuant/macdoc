// WordFormApplyOption.swift — paragraph kind → the `word form apply` flag that
// tidies it (macdoc#255). Moved out of DocxForm when the library went to
// ooxml-swift (macdoc#274); the code is unchanged apart from access level.

import DocxForm

/// The main `word form apply` flag that tidies a paragraph of one kind (#255).
/// `ParagraphKind.applyOption` is what the `word reverse --slot` hints are
/// built from, and a test checks the swiftify skill's kind table against it;
/// other hand-written copies (the macdoc skill's option table, CLI help and
/// messages) are not derived from it. It records only the main flag and
/// its argument, not companion options such as `--field-size`. It lives in the
/// CLI, not in ooxml-swift's DocxForm: the flags are how macdoc is reached, not
/// part of the format (macdoc#274, .claude/rules/format-library-vs-access-surface.md).
struct ApplyOption: Equatable {
    enum Argument: Equatable {
        /// The option takes the paragraph's own id.
        case paraId
        /// The option takes a value the caller chooses, shown by this placeholder.
        case placeholder(String)
    }

    let flag: String
    let argument: Argument

    init(flag: String, argument: Argument) {
        self.flag = flag
        self.argument = argument
    }

    /// The option as written for one paragraph, e.g. `--field 0000A001`.
    func usage(paraId: String) -> String {
        switch argument {
        case .paraId: return "\(flag) \(paraId)"
        case .placeholder(let value): return "\(flag) \(value)"
        }
    }
}

extension ParagraphKind {
    /// The main flag that tidies this kind after render, or nil when the kind
    /// has none. Nil is not "nothing to do": a `body` paragraph's content is
    /// changed with `--insert-after`, which is not a per-kind tidy step.
    var applyOption: ApplyOption? {
        switch self {
        case .tableField: return ApplyOption(flag: "--field", argument: .paraId)
        case .checkboxLine: return ApplyOption(flag: "--checkbox-font", argument: .placeholder("<字型>"))
        case .listCheckbox: return ApplyOption(flag: "--tick-list", argument: .paraId)
        case .body: return nil
        }
    }
}
