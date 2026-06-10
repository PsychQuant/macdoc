## ADDED Requirements

### Requirement: Layer 4 callers consume the re-exported Edit surface via emit-direct, not via parallel Swift shim modules

`word-builder-swift` SHALL support the Layer 4 caller pattern (per `ooxml-edit-isomorphism-foundation` ADR-009) wherein a non-Swift code generator (e.g., the R package `r-wordbuilder` per PsychQuant/macdoc#88) emits `.swift` source files that import `WordBuilderSwift` directly and consume `LensDocument` + `Edit` / `OOXMLEdit` / `WordEdit` cases. The `word-builder-swift` package SHALL NOT add any Layer 4-specific Swift shim module (e.g., `RWordBuilderShim`, `Layer4Helpers`, or similar) to wrap or thin out the Layer 3 surface; Layer 4 emitters consume the existing 5-method `LensDocument` API + the re-exported Edit cases directly.

This Requirement codifies the contract so that future Layer 4 emitters (R, Python, JavaScript, etc.) have a normative anchor describing what they emit AGAINST.

#### Scenario: Emitted Swift source compiles against unchanged WordBuilderSwift surface

- **GIVEN** a Layer 4 emitter (e.g., `r-wordbuilder`) that generates `.swift` source consuming `LensDocument` + `WordEdit` cases
- **WHEN** the emitted file is compiled in a Swift environment with `WordBuilderSwift` v1.0.0+ as a dependency
- **THEN** the file MUST compile and run without requiring any additional Swift module beyond `WordBuilderSwift` itself

#### Scenario: word-builder-swift package surface does not grow Layer 4 helpers

- **WHEN** word-builder-swift v1.0.x patch releases are inspected
- **THEN** the public surface MUST NOT include types or functions named `*Shim` / `*Helper` / `*Bridge` / `*Layer4*` introduced to ease Layer 4 emitter authoring
- (Layer 4 emitters that need helpers SHALL ship their own utility Swift code in their own repos, NOT push it upstream into word-builder-swift.)

##### Example: r-wordbuilder Layer 4 consumption pattern

- **GIVEN** the R pipeline:
  ```r
  wb_document() %>%
    wb_paragraph("Hello") %>%
    wb_export("out.swift")
  ```
- **WHEN** the emitted `out.swift` is compiled
- **THEN** it MUST contain only `import Foundation` and `import WordBuilderSwift` as imports
- **AND** the body MUST use only types/functions from `WordBuilderSwift` v1.0.0's public surface (`LensDocument`, `WordDocument`, `Paragraph`, `DocxReader`, `DocxWriter`, `WordEdit`, `OOXMLEdit`, etc.)
- **AND** the body MUST NOT reference any type named `*Shim` / `*Helper` from `WordBuilderSwift`
