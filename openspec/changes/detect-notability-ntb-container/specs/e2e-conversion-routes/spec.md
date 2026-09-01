## ADDED Requirements

### Requirement: Modern Notability container rejection coverage

The E2E suite SHALL invoke the compiled macdoc executable with synthetic metadata-only modern Notability ZIP archives. It SHALL verify the exact unsupported-generation diagnostic, non-zero exit, empty stdout, and absent destination for HTML and PDF without committing or reading a private Notability fixture.

#### Scenario: Compiled .ntb HTML rejection

- **WHEN** the compiled command receives a synthetic `.ntb` containing `noteBundle` for HTML output
- **THEN** the command returns the exact modern-container diagnostic and creates no output directory

#### Scenario: Compiled .ntb PDF rejection

- **WHEN** the compiled command receives the same synthetic `.ntb` for PDF output
- **THEN** the command returns the exact modern-container diagnostic and creates no PDF file

#### Scenario: Compiled renamed .note rejection

- **WHEN** the synthetic modern archive is renamed with a `.note` suffix and requested as HTML
- **THEN** the command returns the modern-container diagnostic rather than the legacy missing-session diagnostic

#### Scenario: Compiled unsafe unknown .ntb rejection

- **WHEN** the compiled command receives a malformed or metadata-over-limit `.ntb`
- **THEN** the command returns the fixed safe-classification diagnostic without an input path and creates no destination
