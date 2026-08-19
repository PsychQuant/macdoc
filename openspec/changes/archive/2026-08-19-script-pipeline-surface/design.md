## Context

macdoc's script pipeline lifts a `.docx` into an `.mdocx.swift` rebuild script and replays that script back into a `.docx`. The transcode primitives all live together in one module directory of the ooxml-swift package: the script transcoder (importer and exporter), the reverse extractor, the raw part channel, and the part-fidelity comparator.

One member of that family is stranded. The function that orchestrates execute — parse script, pin reference, replay operations, write package, compare parts — lives in che-word-mcp's script-pipeline tool file instead of the shared transcode module. It calls only ooxml-swift primitives, so nothing forces it to live there; it landed there because execute was first needed on the MCP face.

Three consequences follow, and this change addresses all three:

1. The CLI can produce a script (`macdoc word reverse`) but cannot replay one. There is no CLI counterpart to `execute_script`.
2. `che-word-mcp-script-pipeline-tools` states parity is "guaranteed structurally by riding the same ooxml-swift transcoder entry points." That holds for export and coverage. For execute it does not, because the orchestration is not shared.
3. `mdocx-grammar` names `macdoc word render` in two scenarios, but only to illustrate that both the dual-extension and bare-extension filename forms dispatch. No requirement anywhere says what render does.

Separately, the pipeline is undiscoverable. The macdoc plugin skill's subcommand table omits the `word` group entirely, and the che-word-mcp plugin skill never mentions the three script-pipeline tools. Measured behavior also needs stating plainly: a real NTU-REC official form transcodes at 0.0% DSL coverage across all sixteen parts, producing a byte-equal archive rather than readable Swift, because a document containing any rich table drops its whole main part to the raw channel.

## Goals / Non-Goals

**Goals:**

- One implementation of execute orchestration, called by both the CLI and the MCP server.
- The write-ordering constraint currently recorded only as a source comment becomes a normative requirement.
- `macdoc word render` exists and has a written behavioral contract.
- The parity claim in the MCP tools spec matches what the code guarantees.
- A user who installs either plugin can discover the pipeline from its skill, including its fidelity boundary.

**Non-Goals:**

- Closing parity in the other direction. Coverage reporting, the paragraphs-only reverse mode, and oplog-sourced export remain CLI-only in this change.
- Extending the pipeline to pptx or pdf. No transcoder exists for either format.
- Changing the `execute_script` tool schema or response shape. Its handler is reduced to argument parsing; callers observe no difference.
- Making table-bearing documents produce readable DSL. That needs rich-table DSL representation and sub-part degradation in ooxml-swift, both outside this change.
- Registering the `.mdocx` extension with macOS file associations.

## Decisions

### Promote execute orchestration into the shared transcode module

The orchestration function and its result type move from che-word-mcp into the ooxml-swift transcode module, alongside the primitives they already call.

Alternative considered: reimplement execute inside the CLI and leave the MCP copy alone. Rejected because the orchestration encodes a non-obvious constraint — the reference document must be read before the output is written, since output and reference can be the same path — and two copies of an ordering rule drift silently. It would also leave the spec's structural-parity claim false while adding a second place for it to become false.

Alternative considered: have the CLI depend on che-word-mcp. Rejected; that inverts the dependency direction, making a CLI tool depend on an MCP server package.

This promotion crosses a package boundary, not merely a module boundary. `ooxml-swift` is a separate repository consumed by both the CLI and che-word-mcp as a versioned remote dependency, so the move costs a release cycle: tag a new `ooxml-swift` version, then advance the dependency pin in both consumers before either can compile against the promoted entry point. That cost is the reason the orchestration was stranded in che-word-mcp to begin with — execute was needed on the MCP face first, and keeping it local avoided a release. The cost is accepted here because the alternative is two divergent copies of an ordering rule that verification depends on.

### Name the CLI subcommand `render`, not `execute`

`mdocx-grammar` already names `macdoc word render` in shipped spec text. Implementing `execute` would require editing a spec to match new code rather than making code satisfy an existing spec, and would add a third divergence on top of the two being fixed.

This does mean one operation carries two names across faces: `execute_script` on MCP, `word render` on CLI. Accepted deliberately. The MCP name is already shipped in a tool schema that external callers bind to, and renaming it would break them for cosmetic symmetry. The specs will state the correspondence so readers are not left guessing.

### Verification is opt-in and off by default

`macdoc word render` performs byte-equal verification only when the caller names a reference document. Without one it writes the output and reports success.

This mirrors `execute_script`, where the verification verdict rides the response only when verification actually ran — an unconditional empty broken-parts list reads as a false green light to a client that checks only that field. The CLI inherits the same reasoning: silence about verification must mean "not checked", never "checked and clean".

### The write-ordering constraint becomes normative

That the reference must be read before any write is currently a source comment. It moves into the transcode spec as a requirement, because it is the difference between correct verification and self-comparison when a caller passes the same path as both output and reference.

### `swiftify` is a workflow skill inside the macdoc plugin

The new skill lives with the macdoc plugin rather than becoming its own plugin. A plugin in this marketplace is a distribution unit wrapping a binary or an MCP server; swiftify ships neither, composing capabilities from two existing plugins instead. A separate plugin would need a version and a marketplace entry while shipping no artifact.

The macdoc plugin is chosen over the che-word-mcp plugin because the transcoder's canonical home is macdoc — the MCP tools are documented as riding the CLI's code path, not the reverse — and because the CLI work in this change lands there.

This makes macdoc the first plugin in the marketplace with two skills. The existing one-skill-per-plugin arrangement is descriptive of what has been built so far, not a rule.

### Division of labor across the three skill documents

The swiftify skill owns the workflow: which command to run in what order, how to read a coverage report, and what the output can and cannot be used for. The two existing skills own their own surfaces as reference material — the macdoc skill documents the `word` subcommand group, the che-word-mcp skill documents the three tools. Neither restates the workflow.

Without this split the same pipeline gets described three times and the descriptions drift, which is the failure this repository has already recorded in the sibling issue about a plugin shipping with no skill at all.

## Implementation Contract

**Behavior**

A user who has an `.mdocx.swift` script can rebuild the `.docx` from the command line, and can ask for proof that the rebuild is byte-identical to a reference document.

**Interface**

A `render` subcommand joins `reverse` under `macdoc word`. It takes the script path as its argument, requires an output path option for the `.docx` to write, and accepts an optional reference-document option that turns on byte-equal verification. It accepts scripts named with either the dual `.mdocx.swift` form or the bare `.mdocx` form, per the existing dispatch requirement in `mdocx-grammar`.

The promoted orchestration API keeps the shape the MCP handler already relies on: it takes a script path, an output path, and an optional reference path, and returns a result carrying the written path, an optional verification verdict, and the list of parts that failed comparison. The verdict is absent, not false, when no reference was supplied.

**Failure modes**

- Missing script file, or missing reference file when one is named: fail before writing anything, naming the path that was not found.
- Script that does not parse: surface the transcoder's location-bearing reason rather than a generic parse error.
- Existing output file: refuse unless overwrite is requested, consistent with how `word reverse` guards its output.
- Verification mismatch: exit non-zero and name the parts that differ. A mismatch is a reportable outcome, not a crash.
- No reference supplied: no verdict is printed. Absence of a verdict must not be presentable as a pass.

Error text is Traditional Chinese and status lines go to stderr, per this repository's CLI conventions. The written-path status line follows the existing convention used by `word reverse`. Because `.docx` is binary, output goes to a file and never to stdout.

**Acceptance criteria**

- Running reverse on a document and then render on the resulting script, with the original as reference, reports every part byte-equal and exits zero.
- The same round trip on the NTU-REC form fixture behaves identically despite 0.0% DSL coverage: the raw channel is what makes the byte-equal floor hold, so a fully raw script must still replay correctly.
- Rendering a script whose name uses the bare `.mdocx` form succeeds.
- Rendering without a reference writes the output, prints no verdict, and exits zero.
- Rendering against a deliberately altered reference exits non-zero and names at least one differing part.
- The MCP `execute_script` tool returns the same JSON shape as before this change for the same inputs, including the absence of verdict fields when no reference is passed.
- Both plugin skills mention the pipeline; the macdoc skill's subcommand table includes the `word` group.

**Scope boundary**

In scope: the promoted API, the render subcommand, the MCP handler reduction, the four spec edits, three skill documents, and the plugin version bumps.

Out of scope: any change to what `word reverse` produces, to DSL upgrade eligibility, or to the coverage computation. This change moves and documents behavior; it does not alter transcode results.

## Risks / Trade-offs

- Promoting the orchestration touches a package consumed by both the CLI and a shipped MCP binary → the promoted function keeps its existing signature and semantics, so the MCP handler reduction is a call-site change rather than a behavior change; the MCP acceptance criterion above pins the response shape.
- Documentation that omits the fidelity boundary would leave users expecting readable Swift and receiving a large single-line archive → the boundary, with the measured 0.0% figure, is required content in both the workflow skill and the tool reference, and is stated as a non-promise rather than a caveat.
- Two names for one operation across faces could confuse readers → both specs state the correspondence explicitly rather than leaving it inferable.
- A second skill in the macdoc plugin sets a precedent that could invite unbounded skill growth there → the division-of-labor decision above fixes what each document owns, so a future skill has to justify its own scope rather than overlap.

## Migration Plan

The promoted API ships as a minor `ooxml-swift` release: it adds public API and removes none, so existing consumers remain source-compatible. Both consumers advance their dependency pin to that release; until they do, neither compiles against the promoted entry point. Tagging that release pushes to a shared remote and is confirmed with the maintainer before it happens.

No data migration and no user-visible breakage. The MCP tool contract is unchanged, so existing callers need no action. Rollback is reverting the change; the promoted function can return to che-word-mcp without altering behavior, since only its location changes.

Plugin version bumps follow this repository's rule that shell-only edits bump the plugin version while the binary version moves only when a binary repository publishes a release. The skill and CLI work here is shell-side for the macdoc plugin.

## Open Questions

None blocking. The deferred parity items are recorded as non-goals rather than open questions, since the decision to defer them was made explicitly.
