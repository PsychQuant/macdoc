import Foundation

/// Stable Markdown-to-Word errors for recognized math spans that cannot be
/// converted to native Office Math.
public enum MarkdownMathConversionError: Error, Equatable, Sendable {
    case malformedFormula(line: Int, column: Int)
    case unsupportedFormula(token: String, line: Int, column: Int)
    case misplacedDisplayFormula(line: Int, column: Int)
    case formulaPlacementMismatch(line: Int, column: Int)
}

extension MarkdownMathConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformedFormula(let line, let column):
            return "Malformed Markdown math formula at line \(line), column \(column)."
        case .unsupportedFormula(let token, let line, let column):
            return "Unsupported LaTeX token \(token) at line \(line), column \(column)."
        case .misplacedDisplayFormula(let line, let column):
            return "Display math must occupy its own paragraph at line \(line), column \(column)."
        case .formulaPlacementMismatch(let line, let column):
            return "Math formula could not be placed exactly once at line \(line), column \(column)."
        }
    }
}
