// docx-workflow-swift — Layer 3 manifest-driven docx-edit library.
//
// Public surface (see openspec/changes/macdoc-docx-workflow-cli/specs/):
// - Manifest, Step, Anchor, VerifyAssertions       (Codable types)
// - AnchorResolver, AnchorError
// - EditPlanner (internal)
// - Executor, ExecutorResult
// - Verifier, VerifyError
//
// Re-export the foundation surface so callers writing
// `import DocxWorkflowLib` get Edit / OOXMLEdit / WordEdit / LensDocument
// from the consuming code without a second import.
@_exported import WordBuilderSwift

public enum DocxWorkflow {
    public static let version = "0.1.0"
}
