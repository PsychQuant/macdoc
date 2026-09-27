## ADDED Requirements

### Requirement: docx apply commits its output only through the certified transaction

`macdoc docx apply <manifest> --input <baseline> --output <output>` SHALL delegate to `DocxWorkflowLib.CertifiedTransaction.apply`. It SHALL NOT write the output path through any other route.

Before delegating, and before the manifest is even decoded, the output path and (when given) the `--certificate` destination SHALL be subject to `CertifiedTransaction.apply`'s pre-flight checks (see `docx-mutation-certification`'s "Pre-flight destination checks..." Requirement). Additionally, when `--certificate` is given, its path SHALL NOT refer to the same file — per `CertifiedTransaction.filesAreIdentical(_:_:)` — as the manifest argument itself; this fourth conflict is checked by the CLI, since `CertifiedTransaction` is never given the manifest's file path. Any of these failing SHALL exit non-zero, write nothing, and report the reason on stderr in Traditional Chinese — regardless of whether the manifest's steps and `verify` block would otherwise have caused a success or a failure.

On success, it SHALL exit 0 and report the output path on stderr.

On failure, it SHALL exit non-zero, leave the output path exactly as it was before the call, and report on stderr:

- the failure kind: gate violation, verify failure, baseline changed, intent unavailable, output path is a directory, output path is a symbolic link, certificate destination invalid, certificate destination conflicts with another path (the output, the baseline, the rejected-candidate path, or the manifest), metadata-preservation failure, or commit failed;
- the rejected-candidate path, when there is one.

When the output path already exists (and is not a directory) at commit time, its POSIX permissions, ACL and extended attributes SHALL be carried over onto the newly-written output — but NOT its modification time, since the content changed — so re-running `apply` against an output the caller had deliberately restricted does not silently widen it back to the process's default. A brand-new output SHALL be unaffected by this and keep its own default permissions.

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

##### Example: Certificate directory removed between pre-flight and write

| Step | Detail |
|---|---|
| GIVEN | `--certificate /tmp/certs/cert.json`, where `/tmp/certs/` exists and is writable when `apply` starts |
| GIVEN | the manifest's one `insert_paragraph` step and its baseline are otherwise valid |
| WHEN | `/tmp/certs/` is removed after the candidate has been committed to `out.docx` but before the certificate write is attempted (a race) |
| THEN | `out.docx` exists with the applied change, stderr contains `已寫入: out.docx` |
| AND | stderr also contains a warning naming `/tmp/certs/cert.json` and the write failure |
| AND | the exit code is non-zero, and no file exists at `/tmp/certs/cert.json` |

#### Scenario: Certificate path equal to the output, baseline, or manifest path fails before any write

- **WHEN** `--certificate` names the same file as `--output`, as `--input`, or as the manifest argument
- **THEN** the exit code is non-zero, the colliding file's bytes are unchanged, no candidate or output file is created, and stderr uses the `錯誤：` convention naming the conflicting path
- **AND** stderr does not report the output as written

##### Example: Certificate path typo'd to match --output

| Step | Detail |
|---|---|
| GIVEN | `macdoc docx apply manifest.json --input baseline.docx --output out.docx --certificate out.docx` |
| GIVEN | the manifest's steps and baseline would otherwise apply successfully |
| WHEN | `apply` runs |
| THEN | the exit code is non-zero, `out.docx` does not exist afterward |
| AND | stderr names `out.docx` as conflicting with `輸出路徑（--output）`, and does not contain `已寫入` |

#### Scenario: Certificate path colliding with --output only by case is caught after commit, on a case-insensitive filesystem

- **WHEN** `--output` and `--certificate` differ only by case, on a case-insensitive filesystem, and neither path exists before the call — so the pre-flight check in the "Certificate path equal to the output..." Scenario above cannot see the collision (there is nothing on disk yet to compare devices/inodes against)
- **THEN** the transaction itself still succeeds and commits: `out.docx` exists as a valid `.docx`, and stderr reports it as written (`已寫入`)
- **AND** the certificate is not written at the colliding path
- **AND** the exit code is non-zero, because the certificate could not be written as requested
- **AND** this Scenario is skipped, with a stated reason, when run on a case-sensitive filesystem

##### Example: `--output Out.docx --certificate out.docx`, neither existing beforehand

| Step | Detail |
|---|---|
| GIVEN | a temporary directory on a case-insensitive filesystem (detected by creating a mixed-case file and checking whether its lowercased name resolves to it — not by querying volume attributes) |
| GIVEN | `macdoc docx apply manifest.json --input baseline.docx --output Out.docx --certificate out.docx`, and neither `Out.docx` nor `out.docx` exists before the call |
| WHEN | `apply` runs |
| THEN | the exit code is non-zero |
| AND | stderr contains `已寫入` naming `Out.docx` |
| AND | `Out.docx`'s first four bytes are the ZIP signature `PK\x03\x04`, not certificate JSON |

#### Scenario: Output path that is a symbolic link is rejected without touching its target

- **WHEN** `--output` names a path that is itself a symbolic link to an unrelated file
- **THEN** the exit code is non-zero, stderr names the symlink case (`符號連結`) and suggests using the real path instead
- **AND** the symlink itself still resolves to the same target afterward
- **AND** the target file's bytes are unchanged
- **AND** stderr does not report the output as written

##### Example: `--output` aliases an unrelated file via symlink

| Step | Detail |
|---|---|
| GIVEN | `real-target.docx` holding arbitrary content, and `out-symlink.docx` a symbolic link pointing at it |
| GIVEN | `macdoc docx apply manifest.json --input baseline.docx --output out-symlink.docx`, and the manifest would otherwise apply successfully |
| WHEN | `apply` runs |
| THEN | the exit code is non-zero |
| AND | `out-symlink.docx` is still a symbolic link, still pointing at `real-target.docx` |
| AND | `real-target.docx`'s bytes are exactly what they were before the call |

#### Scenario: Overwriting an existing output at the CLI preserves its permissions, extended attributes and creation date

- **WHEN** `--output` names an existing file with non-default POSIX permissions and a custom extended attribute, and `apply` succeeds
- **THEN** the exit code is 0
- **AND** the resulting file's POSIX permissions equal the pre-existing file's
- **AND** the custom extended attribute still reads back with its original value
- **AND** the file's creation date is unchanged

##### Example: `0640` output with a custom extended attribute survives `apply`

| Step | Detail |
|---|---|
| GIVEN | an existing `out.docx` with POSIX permissions `0640`, a custom extended attribute, and a fixed creation date |
| GIVEN | `macdoc docx apply manifest.json --input baseline.docx --output out.docx`, and the manifest would otherwise apply successfully |
| WHEN | `apply` runs |
| THEN | the exit code is 0 |
| AND | `out.docx`'s POSIX permissions are still `0640` |
| AND | the custom extended attribute is still present with its original value |
| AND | `out.docx`'s creation date is unchanged |

#### Scenario: A metadata-copy failure at the CLI rejects the commit rather than widen permissions

- **WHEN** `--output` names an existing file that becomes unreadable to `copyfile(3)` (for example its permissions are `0`) before `apply`'s commit step, while the manifest would otherwise apply successfully
- **THEN** the exit code is non-zero
- **AND** stderr does not report the output as written
- **AND** the old output's bytes are byte-for-byte unchanged (once read access is restored to check)
