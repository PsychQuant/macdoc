// Failures of cli-spec.yaml generation (PsychQuant/macdoc#72).
//
// Dump-level failures (the first four cases) plus the closed list of eight
// overlay failure classes of requirement "Overlay cross-reference
// validation". No other condition is rejected by inference from these.

public enum CLISpecError: Error, Equatable, CustomStringConvertible {
    case unsupportedSerializationVersion(Int)
    case malformedDump(String)
    case emptyVersionOutput
    /// A field the schema needs is absent or empty in the dump — e.g. an
    /// option without `names` or a positional without `valueName`.
    /// `element` is `"<kind> argument #<n>"` (1-based position in the
    /// command's argument list) or `"subcommand #<n>"`.
    case missingRequiredField(command: String, element: String, field: String)

    case unknownCommandPath(String)
    case duplicateCommandMetadata(String)
    case unknownOption(label: String, option: String)
    case unknownStyle(label: String, style: String)
    case duplicateConversion(String)
    case unknownDependency(reference: String, id: String)
    case duplicateDependency(String)
    case unusedDependency(String)

    public var description: String {
        switch self {
        case .unsupportedSerializationVersion(let version):
            return "unsupportedSerializationVersion: --experimental-dump-help 的 serializationVersion 為 \(version)，"
                + "產生器只支援 \(DumpHelp.supportedSerializationVersion)；請更新 Sources/CLISpec/DumpHelp.swift"
        case .malformedDump(let detail):
            return "malformedDump: 無法解析 --experimental-dump-help 輸出：\(detail)"
        case .emptyVersionOutput:
            return "emptyVersionOutput: macdoc --version 沒有輸出版本字串"
        case .missingRequiredField(let command, let element, let field):
            return "missingRequiredField: --experimental-dump-help 中「\(command)」的 \(element) 缺少必要欄位 \(field)（不存在或為空）"
        case .unknownCommandPath(let path):
            return "unknownCommandPath: overlay 引用了不存在的命令路徑「\(path)」"
        case .duplicateCommandMetadata(let path):
            return "duplicateCommandMetadata: overlay 對命令路徑「\(path)」有兩筆以上的 metadata"
        case .unknownOption(let label, let option):
            return "unknownOption: conversion「\(label)」引用的選項 \(option) 未宣告在其命令上（只接受 -- 長名稱）"
        case .unknownStyle(let label, let style):
            return "unknownStyle: conversion「\(label)」的 style「\(style)」不在其命令 --css 的允許值中"
        case .duplicateConversion(let what):
            return "duplicateConversion: overlay 中的 conversion 重複：\(what)"
        case .unknownDependency(let reference, let id):
            return "unknownDependency: 「\(reference)」引用了 external_dependencies 中不存在的 id「\(id)」"
        case .duplicateDependency(let id):
            return "duplicateDependency: external_dependencies 的 id「\(id)」重複"
        case .unusedDependency(let id):
            return "unusedDependency: external_dependencies 的「\(id)」沒有被任何命令或 conversion 引用"
        }
    }
}
