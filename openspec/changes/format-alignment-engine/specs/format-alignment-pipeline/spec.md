## ADDED Requirements

### Requirement: Single-path rebuild pipeline

The system SHALL provide a single pipeline from a reference docx to a rebuilt docx: `macdoc word reverse <docx> --to-mdocx <script>` produces an executable rebuild script, and executing that script SHALL produce a docx whose XML part set is byte-equal to the reference (Stage B). No manual intermediate steps are permitted on this path.

#### Scenario: reference rebuilds byte-equal

- **GIVEN** a reference docx with N XML parts
- **WHEN** `word reverse` produces a script and the script is executed
- **THEN** the rebuilt docx contains the same part paths and every XML part is byte-equal to the reference

### Requirement: Dual-track acceptance — byte-equal floor and DSL coverage score

Acceptance SHALL be measured on two independent axes: (1) **byte-equal pass** per Stage A (per-part) and Stage B (full part set) — a regression floor that MUST hold from the first release of the raw channel onward; (2) **DSL-form coverage %** — bytes rebuilt through the typed DSL channel divided by total XML bytes, reported per part and aggregated over all XML parts. A change that raises coverage SHALL NOT break byte equality; upgrades that cannot maintain byte equality stay on the raw channel.

#### Scenario: raw-to-DSL upgrade keeps the floor

- **GIVEN** a passing Stage B baseline where run formatting rides the raw channel
- **WHEN** run-level extraction upgrades run formatting to the DSL channel
- **THEN** Stage A and Stage B still pass and the aggregate DSL coverage % strictly increases

##### Example: coverage arithmetic

- **GIVEN** document.xml = 70,000 bytes rebuilt via DSL and 10,000 via raw; styles.xml = 20,000 bytes all raw
- **WHEN** coverage is computed
- **THEN** document.xml coverage = 87.5%, styles.xml = 0%, aggregate = 70,000 / 100,000 = 70%

### Requirement: Stage C zip-container equality is out of contract

The acceptance contract SHALL NOT require zip-container byte equality (entry order, compression parameters, timestamps). Stage B (part-set equality) is the final acceptance stage. Tooling MAY normalize containers when comparing; documentation SHALL state the exemption and its rationale (zip-library internals; Word resave does not preserve container bytes).

#### Scenario: container differences do not fail acceptance

- **WHEN** a rebuilt docx has identical part contents but different zip entry ordering than the reference
- **THEN** Stage B passes

### Requirement: Template fixture policy

Real reference documents SHALL live outside version control in `test-files/templates/` and be resolved via the `MACDOC_TEMPLATE_DIR` environment gate with `XCTSkip` fallback. At least one synthetic CJK two-column template SHALL be generated programmatically in the committed test suite so CI exercises the pipeline without shipping private documents.

#### Scenario: CI runs without private fixtures

- **WHEN** the suite runs on a machine without `MACDOC_TEMPLATE_DIR`
- **THEN** real-template tests skip loudly and the synthetic-template pipeline tests still run and assert Stage A/B
