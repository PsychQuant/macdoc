## 1. Repository and R Package Skeleton

- [ ] 1.1 Create the future PsychQuant R package repository and standard R package skeleton, following Use a separate PsychQuant R package repository.
- [ ] 1.2 Configure DESCRIPTION, README, license, package namespace, and examples using package name `wordbuilder`, following Name the package `wordbuilder`.

## 2. R API and Swift Generation

- [ ] 2.1 Implement R document builder API with word_document, add_heading, add_paragraph, add_text_run, add_table, and immutable-return builder objects.
- [ ] 2.2 Implement Deterministic Swift code generation for headings, paragraphs, text runs, and plain data-frame tables, following Generate Swift directly instead of routing through macdoc.
- [ ] 2.3 Add escaping and stable formatting tests so identical R document objects produce byte-identical Swift source.

## 3. Render Runner and Artifact Retention

- [ ] 3.1 Implement Swift toolchain preflight that detects `swift` on PATH and fails before output creation when unavailable.
- [ ] 3.2 Implement Render uses persistent Swift package cache keyed by pinned word-builder-swift version, following Use a persistent Swift package cache.
- [ ] 3.3 Implement Generated Swift artifact retention with default retained source paths and caller-specified swift_output paths, following Retain generated Swift by default.

## 4. Tests and Documentation

- [ ] 4.1 Implement MVP test strategy with golden-file code generation tests and explicitly marked integration render/readback tests, following Test generated Swift separately from end-to-end rendering.
- [ ] 4.2 Document macOS-first SystemRequirements, first-run Swift cache behaviour, generated Swift review workflow, and Phase 1 non-goals.
EOF