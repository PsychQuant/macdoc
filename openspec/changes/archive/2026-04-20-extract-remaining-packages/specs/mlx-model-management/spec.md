## ADDED Requirements

### Requirement: Implementation location

The `mlx-model-management` capability SHALL be implemented in the Swift package located at the GitHub repository `PsychQuant/ocr-swift` (Swift Package Identity `ocr-swift`, product `OCRCore`), consumed by macdoc via `.package(url: "https://github.com/PsychQuant/ocr-swift.git", from: "0.1.0")` in `Package.swift`. The capability SHALL NOT be implemented inline inside the macdoc repository (`packages/ocr-swift/` as a local `path:` dependency) or via any other local-only mechanism.

#### Scenario: Clean clone of macdoc resolves the MLX-model-management implementation from the remote repository

- **WHEN** a new developer executes `git clone https://github.com/PsychQuant/macdoc.git && cd macdoc && swift package resolve`
- **THEN** the resolved `Package.resolved` SHALL include an entry for `ocr-swift` with `kind: remoteSourceControl` and `location: https://github.com/PsychQuant/ocr-swift.git`
- **AND** no `packages/ocr-swift/` directory SHALL exist in the macdoc working tree after resolution (SPM resolves entirely from remote)

#### Scenario: macdoc `Package.swift` does not declare a local path dependency on ocr-swift

- **WHEN** a reviewer inspects macdoc's `Package.swift`
- **THEN** the file SHALL NOT contain `.package(name: "OCRSwift", path: "packages/ocr-swift")` or any equivalent local `path:` dependency for ocr-swift
- **AND** it SHALL contain `.package(url: "https://github.com/PsychQuant/ocr-swift.git", from: "0.1.0")` (or a later semver-compatible version)
