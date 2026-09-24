// The single entry point that turns a dump-help tree, the version output and
// the metadata overlay into the bytes of cli-spec.yaml (PsychQuant/macdoc#72,
// design "One transform shared by the drift test and make cli-spec").

import Foundation

public enum CLISpecGenerator {

    /// Returns the complete cli-spec.yaml text. Throws `CLISpecError` for an
    /// unsupported or malformed dump, an empty version string, or any overlay
    /// cross-reference violation; nothing is skipped silently.
    public static func generate(
        dumpHelpJSON: Data,
        versionOutput: String,
        metadata: CLISpecMetadata
    ) throws -> String {
        let document = try CLISpecBuilder.build(
            dumpHelpJSON: dumpHelpJSON,
            versionOutput: versionOutput,
            metadata: metadata
        )
        return YAMLEmitter.emit(document.yamlNode, headerComments: headerComments(for: document, metadata: metadata))
    }

    /// The five header lines required by "Code-first authority and
    /// generated-file header".
    static func headerComments(for document: CLISpecDocument, metadata: CLISpecMetadata) -> [String] {
        let provenance = metadata.provenance
        return [
            "cli-spec.yaml — \(document.tool.name) CLI specification (schema_version \(CLISpecDocument.schemaVersion))",
            "GENERATED FILE — do not edit by hand. Regenerate: \(provenance.regenerate)",
            "Authority: \(provenance.authority)",
            "Project metadata overlay: \(provenance.overlay)",
            "Contract: \(provenance.contract)",
        ]
    }
}
