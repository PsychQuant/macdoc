## ADDED Requirements

### Requirement: Rendering understanding is probe-verified registry knowledge

The system SHALL maintain a render-effect registry (docs/render-effect-registry.md) mapping typed payload fields to rendering effects. Each entry SHALL name: the payload field, the measurable observable, the predicted direction of change, the expected magnitude with its ECMA-376 unit conversion, the tolerance, the verifying probe test name, and its status. An entry's status SHALL be `verified` only while its perturbation probe passes; entries without a passing probe SHALL be marked `unverified`. The registry SHALL NOT contain effect claims that have no corresponding probe.

#### Scenario: Verified entry carries measured evidence

- **WHEN** a perturbation probe for a registry entry passes
- **THEN** the registry row for that entry records status `verified` together with the measured observable value and the measurement date

#### Scenario: Unverifiable entry stays honest

- **WHEN** an effect cannot be demonstrated by a passing probe (for example, unstable line detection on grid-snapped text)
- **THEN** the registry row records status `unverified` with the failure mode, and the tolerance is NOT loosened to force a pass

### Requirement: Perturbation probes verify predicted rendering effects

For each `verified` registry entry, the test suite SHALL provide a perturbation probe gated behind `RUN_WORD_INTEGRATION=1`. The probe SHALL build a baseline docx via typed operations, build a perturbed docx differing in exactly one payload field, render both through live Microsoft Word, measure the entry's observable on both renders, and assert that the change matches the predicted direction exactly and the predicted magnitude within the entry's tolerance. A failing probe SHALL name its registry entry. Without the gate or without Word, probes SHALL skip loudly.

#### Scenario: Line-pitch probe verifies docGrid understanding

- **GIVEN** a baseline document whose section sets `docGridType` `lines` with `docGridLinePitch` 360 (twips) and body text spanning at least 5 lines
- **WHEN** the probe renders the baseline and a perturbed copy with `docGridLinePitch` 480 and measures the median baseline-to-baseline distance on page 1 of each
- **THEN** the measured line pitch of the perturbed render exceeds the baseline's, and the increase is within tolerance of the predicted 6.0 pt (= (480 − 360) / 20)

#### Scenario: Direction mismatch fails the probe

- **WHEN** a probe measures an observable change whose direction contradicts the registry prediction
- **THEN** the probe fails (not skips) and the failure message names the registry entry

#### Scenario: Probes skip loudly off the maintainer machine

- **WHEN** the suite runs without `RUN_WORD_INTEGRATION=1` or without Microsoft Word installed
- **THEN** every probe reports a skip with the reason rather than passing or failing silently

### Requirement: Slotted rebuilds carry render-level acceptance

Executing a slotted rebuild script with new content SHALL preserve the document's rendered structure relative to the reference render: equal page count, equal page box, and substituted-page median line pitch within tolerance of the corresponding reference page. Pages containing no substituted content SHALL remain pixel-equal within the visual-diff harness threshold. The acceptance SHALL be gated behind both `RUN_WORD_INTEGRATION=1` and the real-template fixture gate, skipping loudly when either is absent.

#### Scenario: New slot content does not disturb layout structure

- **GIVEN** the real JPA template's slotted rebuild script with one designated slot
- **WHEN** the script executes with sentinel content of comparable length and both the reference and the rebuilt docx render through Word
- **THEN** page count and page box are equal, the substituted page's median line pitch is within tolerance of the reference page's, and every untouched page passes the pixel-ratio threshold
