// Maps the decoded dump-help tree into the project schema and merges the
// metadata overlay (PsychQuant/macdoc#72; design "Builtin surface
// normalization and declaration-order traversal" and "Metadata overlay as a
// compiler-checked Swift literal").

import Foundation

public enum CLISpecBuilder {

    public static func build(
        dumpHelpJSON: Data,
        versionOutput: String,
        metadata: CLISpecMetadata
    ) throws -> CLISpecDocument {
        let root = try DumpHelp.decode(dumpHelpJSON)
        let version = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { throw CLISpecError.emptyVersionOutput }

        var commands: [CLISpecDocument.Command] = []
        appendCommands(root, parentPath: nil, into: &commands)

        let merged = try OverlayMerger(commands: commands, metadata: metadata).merge()

        return CLISpecDocument(
            tool: CLISpecDocument.Tool(name: root.commandName, version: version, abstract: root.abstract),
            source: CLISpecDocument.Source(
                authority: metadata.provenance.authority,
                dumpHelpSerializationVersion: DumpHelp.supportedSerializationVersion,
                overlay: metadata.provenance.overlay,
                regenerate: metadata.provenance.regenerate
            ),
            commands: merged.commands,
            conversions: metadata.conversions,
            overlaps: metadata.overlaps,
            externalDependencies: merged.dependencies
        )
    }

    // MARK: - Derived surface

    /// Name of the subcommand ArgumentParser adds directly under the root.
    static let builtinHelpSubcommand = "help"
    /// Long names of the flags ArgumentParser injects into every command.
    static let builtinFlagLongNames: Set<String> = ["help", "version"]

    /// Depth-first pre-order, children in declaration order.
    private static func appendCommands(
        _ command: DumpCommand,
        parentPath: String?,
        into commands: inout [CLISpecDocument.Command]
    ) {
        let isRoot = parentPath == nil
        let path = parentPath.map { $0 + " " + command.commandName } ?? command.commandName
        let children = (command.subcommands ?? []).filter { child in
            !(isRoot && child.commandName == builtinHelpSubcommand)
        }
        let arguments = (command.arguments ?? []).filter { !isBuiltinFlag($0) }

        commands.append(CLISpecDocument.Command(
            path: path,
            abstract: command.abstract,
            discussion: command.discussion,
            aliases: command.aliases ?? [],
            hidden: command.shouldDisplay == false,
            defaultSubcommand: command.defaultSubcommand,
            subcommands: children.map(\.commandName),
            arguments: arguments.filter { $0.kind == .positional }.map(mapArgument),
            options: arguments.filter { $0.kind == .option }.map(mapArgument),
            flags: arguments.filter { $0.kind == .flag }.map(mapArgument),
            project: nil
        ))
        for child in children {
            appendCommands(child, parentPath: path, into: &commands)
        }
    }

    private static func isBuiltinFlag(_ argument: DumpArgument) -> Bool {
        guard argument.kind == .flag else { return false }
        return (argument.names ?? []).contains { name in
            name.kind == .long && builtinFlagLongNames.contains(name.name)
        }
    }

    private static func mapArgument(_ argument: DumpArgument) -> CLISpecDocument.Argument {
        let kind: CLISpecDocument.Argument.Kind
        switch argument.kind {
        case .positional: kind = .positional
        case .option: kind = .option
        case .flag: kind = .flag
        }
        return CLISpecDocument.Argument(
            kind: kind,
            name: kind == .positional ? argument.valueName : nil,
            names: kind == .positional ? [] : renderedNames(argument.names ?? []),
            valueName: kind == .option ? argument.valueName : nil,
            required: !argument.isOptional,
            repeating: argument.isRepeating,
            parsing: argument.parsingStrategy.projectSpelling,
            defaultValue: argument.defaultValue,
            values: argument.allValues ?? [],
            hidden: !argument.shouldDisplay,
            section: argument.sectionTitle,
            help: argument.abstract,
            discussion: argument.discussion
        )
    }

    /// Long names first, then single-dash long names, then short names;
    /// declaration order within each group.
    private static func renderedNames(_ names: [DumpArgument.Name]) -> [String] {
        let long = names.filter { $0.kind == .long }.map { "--" + $0.name }
        let singleDash = names.filter { $0.kind == .longWithSingleDash }.map { "-" + $0.name }
        let short = names.filter { $0.kind == .short }.map { "-" + $0.name }
        return long + singleDash + short
    }
}

// MARK: - Overlay merge and cross-reference validation

/// Applies the overlay to the derived commands. Throws the first violation of
/// the closed list of eight overlay failure classes, checked in this order:
/// command metadata, conversions, overlaps, dependency catalog.
private struct OverlayMerger {
    let commands: [CLISpecDocument.Command]
    let metadata: CLISpecMetadata

    func merge() throws -> (commands: [CLISpecDocument.Command], dependencies: [CLISpecDocument.ExternalDependency]) {
        let byPath = Dictionary(commands.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        // (1) unknownCommandPath, (2) duplicateCommandMetadata
        var infoByPath: [String: CLISpecMetadata.CommandInfo] = [:]
        for info in metadata.commands {
            guard byPath[info.path] != nil else { throw CLISpecError.unknownCommandPath(info.path) }
            guard infoByPath[info.path] == nil else { throw CLISpecError.duplicateCommandMetadata(info.path) }
            infoByPath[info.path] = info
        }

        try validateConversions(byPath)

        for overlap in metadata.overlaps {
            for path in overlap.paths where byPath[path.command] == nil {
                throw CLISpecError.unknownCommandPath(path.command)
            }
        }

        let mergedCommands = commands.map { command -> CLISpecDocument.Command in
            var command = command
            command.project = infoByPath[command.path]
            return command
        }
        return (mergedCommands, try dependencies(orderedCommandInfos: mergedCommands.compactMap(\.project)))
    }

    private func validateConversions(_ byPath: [String: CLISpecDocument.Command]) throws {
        var labels = Set<String>()
        var pairs = Set<String>()
        for conversion in metadata.conversions {
            // (1) unknownCommandPath
            guard let command = byPath[conversion.command] else {
                throw CLISpecError.unknownCommandPath(conversion.command)
            }
            // (5) duplicateConversion — by label
            guard labels.insert(conversion.label).inserted else {
                throw CLISpecError.duplicateConversion(conversion.label)
            }
            // (5) duplicateConversion — by (extension, target) on one command
            for ext in conversion.from {
                let pair = "\(ext) → \(conversion.to)"
                guard pairs.insert(conversion.command + "\u{0}" + pair).inserted else {
                    throw CLISpecError.duplicateConversion(pair)
                }
            }
            // (3) unknownOption — long names declared on the command
            let declared = Set((command.options + command.flags).flatMap(\.names).filter { $0.hasPrefix("--") })
            for option in conversion.options where !declared.contains(option) {
                throw CLISpecError.unknownOption(label: conversion.label, option: option)
            }
            // (4) unknownStyle — values of the command's --css option
            if !conversion.styles.isEmpty {
                let css = command.options.first { $0.names.contains("--css") }
                let allowed = Set(css?.values ?? [])
                for style in conversion.styles where !allowed.contains(style) {
                    throw CLISpecError.unknownStyle(label: conversion.label, style: style)
                }
            }
        }
    }

    /// (6) unknownDependency, (7) duplicateDependency, (8) unusedDependency,
    /// and the derived `used_by` lists.
    private func dependencies(
        orderedCommandInfos: [CLISpecMetadata.CommandInfo]
    ) throws -> [CLISpecDocument.ExternalDependency] {
        var catalogIDs = Set<String>()
        for dependency in metadata.externalDependencies {
            guard catalogIDs.insert(dependency.id).inserted else {
                throw CLISpecError.duplicateDependency(dependency.id)
            }
        }

        // References in document order: commands first, then conversions.
        var references: [(reference: String, id: String)] = []
        for info in orderedCommandInfos {
            references += info.dependencies.map { (info.path, $0) }
        }
        for conversion in metadata.conversions {
            references += conversion.dependencies.map { (conversion.label, $0) }
        }
        for reference in references where !catalogIDs.contains(reference.id) {
            throw CLISpecError.unknownDependency(reference: reference.reference, id: reference.id)
        }

        return try metadata.externalDependencies.map { dependency in
            var usedBy: [String] = []
            for reference in references where reference.id == dependency.id && !usedBy.contains(reference.reference) {
                usedBy.append(reference.reference)
            }
            guard !usedBy.isEmpty else { throw CLISpecError.unusedDependency(dependency.id) }
            return CLISpecDocument.ExternalDependency(dependency: dependency, usedBy: usedBy)
        }
    }
}
