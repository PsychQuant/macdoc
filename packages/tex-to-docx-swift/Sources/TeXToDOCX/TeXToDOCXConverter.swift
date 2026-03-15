import Foundation
import CommonConverterSwift
import OOXMLSwift

public struct TeXToDOCXConverter: DocumentConverter {
    public static let sourceFormat = "tex"

    public init() {}

    /// Streaming output is not supported for DOCX (binary ZIP format).
    /// Use convertToFile() instead.
    public func convert<W: StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        throw ConversionError.unsupportedFormat("DOCX is a binary format; use convertToFile() instead of streaming convert()")
    }

    public func convertToFile(
        input: URL,
        output: URL,
        options: ConversionOptions = .default
    ) throws {
        let document = try convertToDocument(input: input, options: options)
        try DocxWriter.write(document, to: output)
    }

    public func convertToDocument(
        input: URL,
        options: ConversionOptions = .default
    ) throws -> WordDocument {
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw ConversionError.fileNotFound(input.path)
        }

        let source = try String(contentsOf: input, encoding: .utf8)
        let expanded = try expandInputs(source: source, baseURL: input.deletingLastPathComponent())

        var builder = TeXWordBuilder(source: expanded, sourceURL: input, options: options)
        return builder.build()
    }

    /// Recursively expand \input{...} directives, resolving paths relative to
    /// each included file's directory (not just the root baseURL).
    private func expandInputs(source: String, baseURL: URL) throws -> String {
        let pattern = #"\\input\{([^}]+)\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        var result = source

        var iterations = 0
        while let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
              iterations < 200 {
            iterations += 1

            let fullRange = Range(match.range, in: result)!
            let pathRange = Range(match.range(at: 1), in: result)!
            var path = String(result[pathRange])

            if !path.hasSuffix(".tex") {
                path += ".tex"
            }

            let fileURL = baseURL.appendingPathComponent(path).standardized
            if FileManager.default.fileExists(atPath: fileURL.path) {
                var content = try String(contentsOf: fileURL, encoding: .utf8)
                // Rewrite relative \input paths inside included file to be relative to baseURL
                let includeDir = fileURL.deletingLastPathComponent()
                let relPrefix = includeDir.path.replacingOccurrences(of: baseURL.path, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relPrefix.isEmpty {
                    // Prepend the include's relative directory to any \input inside it
                    let innerRegex = try NSRegularExpression(pattern: #"\\input\{([^}]+)\}"#)
                    let innerMatches = innerRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
                    // Process in reverse to preserve ranges
                    for innerMatch in innerMatches.reversed() {
                        if let innerPathRange = Range(innerMatch.range(at: 1), in: content) {
                            let innerPath = String(content[innerPathRange])
                            // Only rewrite if not already an absolute or upward-relative path
                            if !innerPath.hasPrefix("/") && !innerPath.hasPrefix("..") {
                                content.replaceSubrange(innerPathRange, with: relPrefix + "/" + innerPath)
                            }
                        }
                    }
                }
                result.replaceSubrange(fullRange, with: content)
            } else {
                result.replaceSubrange(fullRange, with: "")
            }
        }

        return result
    }
}
