## 1. Package and CLI Surface

- [ ] 1.1 Update Package.swift to add the DocxWorkflowLib library target, DocxWorkflowLibTests test target, explicit Word/OOXML dependencies, and the MacDocCLI dependency on DocxWorkflowLib for the Importable workflow library boundary.
- [ ] 1.2 Create Sources/DocxWorkflowLib with public DocxManifest, DocxWorkflowPlanner, DocxWorkflowExecutor, DocxWorkflowVerifier, DocxWorkflowDiffer, and typed error models to Keep workflow logic in `DocxWorkflowLib`.
- [ ] 1.3 Add Sources/MacDocCLI/MacDoc+Docx.swift and register it from Sources/MacDocCLI/MacDoc.swift so the Integrated docx command namespace implements Use `macdoc docx` as the Phase 1 product surface.

## 2. Manifest, Planning, and Safety

- [ ] 2.1 Implement the JSON Codable manifest contract in DocxWorkflowLib with schemaVersion, workflow, steps, checks, and CLI path override resolution to Use JSON-first Codable manifests.
- [ ] 2.2 Implement Safe output write behaviour with preflight validation, missing-anchor failure before writes, existing-output protection, and explicit overwrite handling.
- [ ] 2.3 Implement DocxOperationPlan generation so Plan reports deterministic operations without writing output and Make planning mandatory inside every execution path.

## 3. Workflow Execution

- [ ] 3.1 Implement Build workflow creates new documents from manifest sections, paragraphs, text runs, and tables using word-builder-swift model coverage.
- [ ] 3.2 Implement Patch workflow fills template placeholders with literal `{{name}}` token resolution, zero-match failure, duplicate-match failure, and all-matches opt-in.
- [ ] 3.3 Implement Apply workflow mutates existing documents through ordered steps for replaceText, insertParagraphAfterText, and insertImageAfterText while preserving unchanged OOXML parts.
- [ ] 3.4 Normalize build, patch, and apply plans through shared operation records so implementation preserves Separate build, patch, and apply semantics without creating three unrelated engines.

## 4. Verification and Diff

- [ ] 4.1 Implement Verify enforces manifest checks by OOXML readback for containsText, notContainsText, replacementCount, and readbackSucceeds, following Verify by OOXML readback and manifest checks.
- [ ] 4.2 Implement Diff reports Word-aware document changes by comparing readback summaries for paragraph text additions/removals, table count, image relationship count, and field/equation count where available, following Diff at a Word-aware structural level.

## 5. Tests and Documentation

- [ ] 5.1 Add DocxWorkflowLibTests covering Synthetic fixture policy for docx workflow tests by generating source/template `.docx` fixtures programmatically or using minimal synthetic committed fixtures only.
- [ ] 5.2 Add MacDocCLITests for `macdoc docx --help`, build, patch, apply, plan no-output behaviour, verify pass/fail, diff output, invalid manifest failure, and existing-output protection.
- [ ] 5.3 Update README.md and CONVERSIONS.md with JSON manifest examples, command examples, non-goals for YAML and dxedit, and guidance on when to use `macdoc docx` instead of `macdoc convert --to docx` or che-word-mcp.
