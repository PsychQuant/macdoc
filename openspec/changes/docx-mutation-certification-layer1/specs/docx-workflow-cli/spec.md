## ADDED Requirements

### Requirement: docx apply commits its output only through the certified transaction

`macdoc docx apply <manifest> --input <baseline> --output <output>` SHALL delegate to `DocxWorkflowLib.CertifiedTransaction.apply`. It SHALL NOT write the output path through any other route.

On success, it SHALL exit 0 and report the output path on stderr.

On failure, it SHALL exit non-zero, leave the output path exactly as it was before the call, and report on stderr:

- the failure kind: gate violation, verify failure, baseline changed, or intent unavailable;
- the rejected-candidate path, when there is one.

The optional `--certificate <path>` flag SHALL write the certificate JSON to that path in both the success and the failure case.

#### Scenario: Certificate flag writes the JSON on success

- **WHEN** `macdoc docx apply manifest.json --input baseline.docx --output out.docx --certificate cert.json` succeeds
- **THEN** `out.docx` exists, the exit code is 0, and `cert.json` decodes with `status` `layer1Verified`

#### Scenario: Failing verify leaves no output

- **WHEN** the manifest's `verify` block asserts a count the result does not meet and `out.docx` did not exist before the call
- **THEN** the exit code is non-zero, `out.docx` does not exist, and stderr names the verify failure and the rejected-candidate path
