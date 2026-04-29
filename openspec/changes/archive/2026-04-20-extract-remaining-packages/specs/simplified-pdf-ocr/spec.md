## ADDED Requirements

### Requirement: Implementation location

The `simplified-pdf-ocr` capability SHALL be implemented in the Swift package located at the GitHub repository `PsychQuant/pdf-to-latex-swift` (Swift Package Identity `pdf-to-latex-swift`, product `PDFToLaTeXCore`), consumed by macdoc via `.package(url: "https://github.com/PsychQuant/pdf-to-latex-swift.git", from: "0.1.0")` in `Package.swift`. The capability SHALL NOT be implemented inline inside the macdoc repository (`packages/pdf-to-latex-swift/` as a local `path:` dependency) or via any other local-only mechanism.

#### Scenario: Clean clone of macdoc resolves the simplified-pdf-ocr implementation from the remote repository

- **WHEN** a new developer executes `git clone https://github.com/PsychQuant/macdoc.git && cd macdoc && swift package resolve`
- **THEN** the resolved `Package.resolved` SHALL include an entry for `pdf-to-latex-swift` with `kind: remoteSourceControl` and `location: https://github.com/PsychQuant/pdf-to-latex-swift.git`
- **AND** no `packages/pdf-to-latex-swift/` directory SHALL exist in the macdoc working tree after resolution (SPM resolves entirely from remote)

#### Scenario: macdoc `Package.swift` does not declare a local path dependency on pdf-to-latex-swift

- **WHEN** a reviewer inspects macdoc's `Package.swift`
- **THEN** the file SHALL NOT contain `.package(name: "pdf-to-latex-swift", path: "packages/pdf-to-latex-swift")` or any equivalent local `path:` dependency for pdf-to-latex-swift
- **AND** it SHALL contain `.package(url: "https://github.com/PsychQuant/pdf-to-latex-swift.git", from: "0.1.0")` (or a later semver-compatible version)
