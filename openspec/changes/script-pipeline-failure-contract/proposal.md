## Problem

The script-execution surface (`execute_script` on the MCP face, `macdoc word render` on the CLI face) has two defects that share one shape: a caller can be told a rebuild succeeded when it did not, and a caller can lose a file they did not agree to overwrite.

1. **A failed byte-equal verification is reported as a successful tool call.** `execute_script` returns `verified: false` plus a `broken_parts` list inside a normal success response. Nothing sets the MCP error flag. A caller that checks only whether the call succeeded reads a failed verification as a pass. The CLI face does not share this defect — it exits non-zero.

2. **The overwrite gate exists on only one of the two faces, and the write happens before verification on both.** `macdoc word render` refuses to clobber an existing output file unless the caller passes an overwrite request. `execute_script` has no such gate and overwrites silently. Separately, both faces write the rebuilt package to the final output path *before* comparing it against the reference, so a verification failure destroys whatever was at that path.

Together these mean the worst case is silent and unrecoverable: a caller asks for a verified rebuild, the rebuild diverges from the reference, the original file at the output path is already gone, and the response says the call succeeded.

## Root Cause

Both defects trace to the same structural fact, from opposite directions.

**Defect 1** is a verdict being treated as data rather than as result-state. The verdict rides in the response payload, and no layer converts a false verdict into a failure signal. The spec that governs this tool encodes the defect verbatim — it requires that on a false verdict the response name the broken parts, and says nothing about signalling failure. So this is not code diverging from its spec; it is a spec written to describe what the code already did.

**Defect 2** is protection bolted onto one wrapper rather than placed in the shared entry point. The previous change promoted script-execution orchestration into a single shared function precisely so both faces would behave identically. That promotion guarantees parity for everything *inside* the shared function. The overwrite gate was never moved inside it — it stayed in the CLI command — so by construction it fell outside the parity guarantee. The claim "the two faces are identical because they share an implementation" was true and still permitted this divergence, because a guard on the wrapper is not part of the implementation the faces share.

The destructive write ordering is a third, independent consequence: the entry point writes to the final path and then reads that same path back to compare. There is no point at which a failed verification can decline to publish, because publication already happened.

## Proposed Solution

Four changes, all landing in or below the shared entry point so neither face can drift again.

1. **Move the overwrite gate into the shared entry point.** The entry point gains an overwrite parameter defaulting to refuse. The CLI overwrite flag and a new MCP overwrite parameter both map onto it. Neither face keeps its own gate. A future third consumer inherits the protection without doing anything.

2. **Restructure to write-temp, verify, then move.** The entry point writes the rebuilt package to a temporary path in the same directory as the requested output, compares that temporary package against the reference, and moves it into place only when there is no verdict or the verdict passes. Same-directory placement keeps the final move atomic; a temporary file elsewhere would degrade the move into a cross-filesystem copy. A failed verification therefore leaves the output path exactly as it was — untouched if a file was there, absent if none was.

3. **Make the written path optional in the result.** When nothing was committed, the result reports no written path rather than naming a path it did not write. This mirrors the rule the result type already follows for the verdict, where absent means "did not happen" rather than "happened and was false". The MCP response omits the key entirely in that case, matching how it already omits the verdict fields. The CLI announces the write only after the verdict is known, instead of announcing it first and then failing.

4. **Convert a false verdict into a tool error.** `execute_script` raises rather than returns when verification fails, and the error names the differing parts. This matches what the CLI face already does.

## Non-Goals

- **Preserving the structured broken-parts list on the MCP failure path.** Raising an error routes the response through a handler that renders errors as plain text, so the differing parts survive as a readable message rather than as JSON. Keeping both the error signal and the structured payload would require changing the shared tool-dispatch layer so a handler can set the error flag while still returning a JSON body — a change that touches every tool in the server, which is out of proportion to this fix. That restructuring is recorded as its own issue rather than folded in here: PsychQuant/che-word-mcp#182.
- **Changing the two faces' command and tool names.** They remain deliberately different, as already settled.
- **Adding an overwrite gate to the reverse or export direction.** This change is scoped to the execution direction.

## Success Criteria

- A verification failure through the MCP face is reported as a failed tool call, and the failure text names each differing part.
- Neither face writes to the output path when verification fails: an existing file at that path is unchanged, and no file appears where none existed.
- Both faces refuse to overwrite an existing output file unless the caller explicitly asks, and the refusal happens before the rebuild work is done.
- The overwrite gate is reachable from exactly one place in the source; removing the CLI-side check does not weaken the CLI's behavior.
- A caller supplying one path as both output and reference still gets a verdict compared against the pre-write contents, and now also keeps that file intact when the verdict fails.
- The result carries no written path when nothing was committed, and the MCP response omits the corresponding key.

## Impact

- Affected specs: ooxml-script-transcode, che-word-mcp-script-pipeline-tools, mdocx-grammar, swiftify-workflow
- Affected code:
  - Modified:
    - packages/ooxml-swift/Sources/OOXMLSwift/Transcode/ScriptPipelineExecute.swift
    - packages/ooxml-swift/Tests/OOXMLSwiftTests/ScriptPipelineExecuteTests.swift
    - mcp/che-word-mcp/Sources/CheWordMCP/ScriptPipelineTools.swift
    - mcp/che-word-mcp/Sources/CheWordMCP/Server.swift
    - mcp/che-word-mcp/Tests/CheWordMCPTests/ScriptPipelineParityTests.swift
    - mcp/che-word-mcp/Package.swift
    - Sources/MacDocCLI/MacDoc+Word+Render.swift
    - Tests/MacDocCLITests/WordRenderTests.swift
    - Package.swift
    - plugins/macdoc/skills/macdoc/SKILL.md
    - plugins/macdoc/skills/swiftify/SKILL.md
    - plugins/che-word-mcp/skills/che-word-mcp/SKILL.md
  - New: (none)
  - Removed: (none)

Both behavior changes are breaking for existing callers and ship together in one release so callers absorb the disruption once.
