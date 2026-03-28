## 1. Test Infrastructure Setup (test target in Package.swift)

- [x] 1.1 Add `MacDocCLITests` test target to root `Package.swift` with dependency on OOXMLSwift (for minimal programmatic test fixtures generation)
- [x] 1.2 Create `Tests/MacDocCLITests/` directory structure
- [x] 1.3 Implement CLI process runner helper: run macdoc binary, capture stdout/stderr/exit code, return structured result (process-based testing via compiled binary)
- [x] 1.4 Implement programmatic fixture generation: create minimal .docx, .md, .html, .srt, .bib, .tex, .pdf files in temp directory at test setup
- [x] 1.5 Implement output assertion helpers: assertContains, exit code checks, file existence checks
- [x] 1.6 Implement fixture cleanup in test teardown
- [x] 1.7 Verify test target in Package.swift works: `swift test` discovers and runs the test target

## 2. Text-output route coverage (categorized test structure — ConvertRouteTests)

- [x] 2.1 Text-output route coverage: test docx → md route, verify exit success and stdout contains document text
- [x] 2.2 Test docx → html route: verify exit success and stdout contains HTML markup
- [x] 2.3 Test html → md route: verify exit success and stdout contains markdown
- [x] 2.4 Test md → html route: verify exit success and stdout contains HTML
- [x] 2.5 Test srt → html route: verify exit success and stdout contains speaker spans
- [x] 2.6 Test bib → html route: verify exit success and stdout contains APA HTML
- [x] 2.7 Test bib → md route: verify exit success and stdout contains APA markdown
- [x] 2.8 Test bib → json route: verify exit success and stdout contains valid JSON
- [x] 2.9 Test pdf → md route: verify exit success (output verification strategy — lenient for PDFKit)

## 3. Binary-output route coverage (ConvertRouteTests)

- [x] 3.1 Binary-output route coverage: test html → docx route, verify exit success and output file exists with size > 0
- [x] 3.2 Test md → docx route: verify exit success and output file exists
- [x] 3.3 Test pdf → docx route: verify exit success and output file exists
- [x] 3.4 Test tex → docx route: verify exit success and output file exists

## 4. Flag combination coverage (ConvertFlagTests)

- [x] 4.1 Flag combination coverage: test --full flag on md → html, verify stdout contains `<!DOCTYPE html>`
- [x] 4.2 Test --css dark on srt → html: verify stdout contains dark theme CSS
- [x] 4.3 Test --frontmatter on docx → md: verify stdout starts with `---` YAML
- [x] 4.4 Test --output flag: verify file is written to specified path
- [x] 4.5 Test --html-extensions on html → md: verify raw HTML tags preserved

## 5. Error handling coverage (ErrorHandlingTests)

- [x] 5.1 Error handling coverage: test missing input file, verify non-zero exit code and error message
- [x] 5.2 Test unsupported format pair: verify non-zero exit code and error message
- [x] 5.3 Test missing --to flag: verify argument parser error

## 6. Verification

- [x] 6.1 Run full test suite with `swift test` and verify all tests pass
- [x] 6.2 Verify test execution completes in < 30 seconds
