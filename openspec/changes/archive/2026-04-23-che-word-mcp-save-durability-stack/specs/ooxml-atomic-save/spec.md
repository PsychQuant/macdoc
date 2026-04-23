## ADDED Requirements

### Requirement: DocxWriter.write performs atomic-rename save

The `ooxml-swift` `DocxWriter.write(_ document: WordDocument, to url: URL)` SHALL be a transactional write: either the target file at `url` ends up containing the complete new bytes, OR the target file remains exactly as it was before the call. No partial-write or zero-length intermediate state SHALL be visible at `url` at any point during the call.

The implementation SHALL use the atomic-rename pattern: write the new bytes to a temp file at `url.appendingPathExtension("tmp.<UUID>")`, call `FileHandle.synchronize()` to flush kernel buffers to disk, then call `FileManager.default.replaceItemAt(url, withItemAt: tempURL, ...)` to atomically replace the target. The temp file SHALL be cleaned up via `defer` on every exit path (success, throw, or panic) to prevent orphan temp files accumulating in the target directory.

The pre-emptive `removeItem(at: url)` call that exists in pre-v0.13.2 `DocxWriter.write` (line 19-21) SHALL be removed.

#### Scenario: Successful save replaces target atomically

- **WHEN** `DocxWriter.write(doc, to: url)` is called with a non-empty `doc` and `url` that already contains a 169584-byte original docx
- **THEN** after the call returns, the file at `url` contains the new bytes (SHA256 differs from original)
- **AND** at no observable point during the call did the file at `url` have size 0 or contain partial bytes

#### Scenario: Throw mid-write preserves original

- **WHEN** `DocxWriter.write(doc, to: url)` is called and `ZipHelper.zipToData` throws an error before write completes
- **THEN** the file at `url` still contains the original 169584 bytes (SHA256 unchanged)
- **AND** no `<url>.tmp.<UUID>` orphan file remains in the target directory

#### Scenario: Process killed mid-write preserves original

- **WHEN** `DocxWriter.write(doc, to: url)` is invoked in a subprocess and the subprocess is sent SIGKILL after `synchronize()` but before `replaceItemAt`
- **THEN** after the parent process inspects the directory, the file at `url` still contains the original bytes
- **AND** at most one orphan `<url>.tmp.<UUID>` file may remain (cleanup-on-throw cannot run after SIGKILL, but original is intact)

#### Scenario: Fresh write to non-existent path

- **WHEN** `DocxWriter.write(doc, to: url)` is called with a `url` that does not yet exist
- **THEN** after the call, the file at `url` exists and contains the new bytes
- **AND** the parent directory of `url` is NOT modified (no other files appear)

##### Example: 169584 → 170000 byte save

Given an original docx of 169584 bytes at `/tmp/test.docx`:
- Before call: `Data(contentsOf: url).count == 169584`, SHA256 = `<original_hash>`
- Call: `try DocxWriter.write(modifiedDoc, to: url)` where `modifiedDoc` serializes to 170000 bytes
- After call: `Data(contentsOf: url).count == 170000`, SHA256 = `<new_hash>`
- During call: any external observer reading `/tmp/test.docx` either sees 169584-byte original or 170000-byte new bytes; never sees 0-byte file or 50000-byte partial

### Requirement: DocxWriter.write supports cross-volume rename via Foundation fallback

When `tempURL` and target `url` reside on different filesystem mount points (uncommon but possible — e.g., `/tmp` on root volume vs target on a network mount), atomic POSIX `rename()` is not available. `DocxWriter.write` SHALL delegate to `FileManager.default.replaceItemAt` which internally detects this case and falls back to copy-then-delete. The atomicity guarantee degrades from kernel-level atomic to "best-effort" in this case, but the no-data-loss invariant SHALL be preserved (original bytes remain readable until the new bytes are fully copied).

#### Scenario: Cross-volume save delegates to copy-fallback

- **WHEN** `DocxWriter.write(doc, to: networkURL)` is called where `networkURL` is on a different mount than `temporaryDirectory`
- **THEN** the call succeeds (returns without throw)
- **AND** the file at `networkURL` contains the new bytes after the call
- **AND** if the call throws partway, the file at `networkURL` still contains either the full original or the full new bytes (no partial copy state)
