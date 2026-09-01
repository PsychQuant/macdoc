## 1. RED Acceptance

- [x] 1.1 Implement the **Prove behavior with synthetic metadata-only archives** test contract in `Tests/MacDocCLITests/NotabilityContainerDetectionTests.swift`: generate payload-free ZIP fixtures for `.ntb` and renamed `.note`, then verify the **Modern Notability container rejection coverage** scenarios are RED because the compiled CLI lacks the exact modern-generation diagnostic and no-output guarantee.

## 2. Container Detection and Routing

- [x] 2.1 Implement **Classify from normalized ZIP entry names without extracting payloads** and **Classify Notability container generation from ZIP entry metadata** in `Sources/NotabilityContainerDetection/NotabilityContainerDetector.swift`, including legacy precedence, modern detection, unknown fallback, and a direct ZIPFoundation dependency in `Package.swift`; verify focused unit assertions classify synthetic entry sets and `swift package describe --type json` succeeds without changing the resolved ZIPFoundation revision.
- [x] 2.2 Implement **Gate both HTML and PDF note routes before converter construction** and **Reject modern FlatBuffers note conversion precisely and before output** in `Sources/MacDocCLI/MacDoc+Convert.swift`; verify `.note` and `.ntb` HTML/PDF compiled cases emit the exact diagnostic, empty stdout, non-zero exit, and leave destinations absent while existing legacy note smoke tests remain green.
- [x] 2.3 Bound and independently validate EOCD discovery, central-directory size/records, entry count, entry path length, and enumeration completeness; reject unsafe unknown `.ntb` containers locally without leaking their path while preserving legacy unknown `.note` diagnostics.
- [x] 2.4 Isolate detector tests in a lightweight package target rather than linking the full `MacDocCLI` executable target into XCTest.

## 3. Support Boundary Documentation

- [x] [P] 3.1 Implement **Qualify documentation rather than overstate support** and **State the Notability generation support boundary** in `README.md` and `CONVERSIONS.md`; verify a documentation regression finds legacy plist-based `.note`, detected-but-not-supported modern `.ntb`, and an explicit statement that FlatBuffers replay is not implemented.

## 4. Verification

- [x] 4.1 Run the complete phase-0 acceptance: focused Notability tests, existing Note HTML/PDF smoke tests, root `swift test`, `spectra validate detect-notability-ntb-container`, dependency and privacy checks, and `git diff --check`; record exact results and confirm no real Notability fixture or payload content is added.

### Verification evidence (2026-08-13)

- RED: `swift test --filter NotabilityContainerDetectionTests` — 3 tests, 3 expected diagnostic failures before implementation.
- Focused GREEN: `swift test --filter NotabilityContainerDetectionTests` — 8 tests, 0 failures.
- Legacy smoke: `swift test --filter 'NoteHTMLConvertTests|NotePDFConvertTests'` — 3 tests, 0 failures, 1 existing single-page density skip.
- Full root: `swift test` — 53 tests, 0 failures, 3 environment/fixture skips.
- Spectra: `spectra validate detect-notability-ntb-container` — valid; analyze reports no Critical/Warning findings (one non-blocking concrete-example suggestion).
- Dependency: `swift package describe --type json` succeeded; `Package.resolved` remained byte-unchanged at SHA-256 `030f6531a76e1284444677ace153951a7f5e861b363d155fe3c7a339a3735f03`, including ZIPFoundation 0.9.20 revision `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`.
- Privacy and packaging: no `.ntb`, `.note`, `noteBundle`, media, or private payload fixture was added; tests create only fixed synthetic metadata bytes in the temporary directory.
- Hygiene: changed source/test/docs privacy scan and `git diff --check` passed.

### Verification addendum (2026-08-24)

- Security RED: over-limit entry/path cases classified as modern and malformed `.ntb` fell through to the legacy parser, which disclosed its basename.
- Security GREEN: 17 focused `NotabilityContainerDetectionTests`, including a 256 MiB sparse missing-EOCD file, a damaged second local header, aligned and non-canonical EOCD-in-comment redirects, cross-disk central entries, ZIP64 version without classic sentinels, metadata bounds, and local unknown `.ntb` rejection — 0 failures.
- Regression RED: making `MacDocCLITests` depend directly on `MacDocCLI` caused an unrelated `WordRenderTests` SIGSEGV while initializing `WordDocument`.
- Regression GREEN: `NotabilityContainerDetection` is now a lightweight shared target; #148 tests retain direct unit coverage without loading the executable target into XCTest.
- Full root GREEN after a clean build with verified prerequisite #164 temporarily overlaid: 48 XCTest (0 failures, 4 fixture/environment skips) plus 26 Swift Testing tests (0 failures). The overlay was aborted after verification and is not part of #148.
