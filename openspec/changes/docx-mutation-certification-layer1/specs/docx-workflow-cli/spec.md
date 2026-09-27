## ADDED Requirements

### Requirement: docx apply commits its output only through the certified transaction

`macdoc docx apply <manifest> --input <baseline> --output <output>` SHALL delegate to `DocxWorkflowLib.CertifiedTransaction.apply`. It SHALL NOT write the output path through any other route.

Before delegating, and before the manifest is even decoded, the output path and (when given) the `--certificate` destination SHALL be subject to `CertifiedTransaction.apply`'s pre-flight checks (see `docx-mutation-certification`'s "Pre-flight destination checks..." Requirement). Either failing SHALL exit non-zero, write nothing, and report the reason on stderr in Traditional Chinese — regardless of whether the manifest's steps and `verify` block would otherwise have caused a success or a failure.

On success, it SHALL exit 0 and report the output path on stderr.

On failure, it SHALL exit non-zero, leave the output path exactly as it was before the call, and report on stderr:

- the failure kind: gate violation, verify failure, baseline changed, intent unavailable, output path is a directory, or certificate destination invalid;
- the rejected-candidate path, when there is one.

Any thrown error that is not a `CertificationError` (for example a missing or malformed manifest file, or an existing Executor failure unrelated to certification) SHALL also be reported on stderr with the same Traditional Chinese `錯誤：` prefix, and SHALL exit non-zero. This does not change the underlying error's cause — only the CLI's presentation of it.

The optional `--certificate <path>` flag SHALL write the certificate JSON to that path in both the success and the failure case, PROVIDED its destination passed the pre-flight check above. If the certificate write itself fails after that check passed (a race), `apply` SHALL still report the transaction's own outcome exactly as it would have without `--certificate` (the success message on a successful transaction, or the failure kind and rejected-candidate path on a failed one), SHALL additionally report the certificate-write failure on stderr, and SHALL exit non-zero even when the underlying transaction succeeded — so a caller does not treat a certificate file that was not actually written as ground truth.

#### Scenario: Certificate flag writes the JSON on success

- **WHEN** `macdoc docx apply manifest.json --input baseline.docx --output out.docx --certificate cert.json` succeeds
- **THEN** `out.docx` exists, the exit code is 0, and `cert.json` decodes with `status` `layer1Verified`

#### Scenario: Failing verify leaves no output

- **WHEN** the manifest's `verify` block asserts a count the result does not meet and `out.docx` did not exist before the call
- **THEN** the exit code is non-zero, `out.docx` does not exist, and stderr names the verify failure and the rejected-candidate path

#### Scenario: Invalid certificate destination fails before any write

- **WHEN** `--certificate` names a path whose parent directory does not exist, regardless of whether the manifest's steps and `verify` block would otherwise have succeeded or failed
- **THEN** the exit code is non-zero, `out.docx` does not exist, no file exists at the certificate path, stderr uses the `錯誤：` convention, and stderr does not report the output as written

#### Scenario: Output path that is an existing directory fails before any write

- **WHEN** `--output` names a path that already exists and is a directory
- **THEN** the exit code is non-zero, and the directory and everything in it are unchanged

#### Scenario: Certificate write failing after a successful commit still exits non-zero

- **WHEN** the certificate destination passes pre-flight validation, the underlying transaction succeeds, and the certificate write itself then fails
- **THEN** stderr reports the output path as written, stderr also reports the certificate-write failure, and the exit code is non-zero
