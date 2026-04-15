# Cross-Repo Umbrella Issue Tracking

macdoc spans multiple git repositories (`packages/*`, `mcp/*`, plus sibling PsychQuant repos like `psychquant-claude-plugins`, `collaborations_tatsuma`, `che-apple-mail-mcp`). When a task, bug, or feature touches 2+ repos, use the **umbrella issue pattern** to avoid fragmentation across issue trackers.

## When to use

- A single user-visible workflow requires changes in 2+ repos
- A bug in one binary blocks downstream work in another (e.g., `ooxml-swift` parser coverage blocks `che-word-mcp` markdown export helpers, which block a plugin-level `/archive-mail` milestone routing feature)
- You want a single dashboard to see cross-repo progress
- You find yourself switching between 3+ GitHub issue tabs to understand the state of one "effort"

Do **not** use for single-repo tasks. A normal issue in the owning repo suffices.

## Pattern

1. **Pick umbrella repo**: usually `PsychQuant/macdoc` (this monorepo), since it already spans `packages/` + `mcp/`. Fallback: whichever repo "owns" the originating workflow.
2. **Open child issues** first, in each affected repo, using normal issue tracking. Each child should stand alone semantically.
3. **Open the umbrella issue** in the umbrella repo titled `Tracking: <high-level goal>`.
4. **In the umbrella body**, include:
   - **Purpose** — 2-3 sentences on the originating real-world need
   - **Dependency tree** — ASCII diagram showing which child issues block which (if applicable)
   - **Issue checklist** — `- [ ]` markdown checkboxes, one per child, with full owner/repo#N link
   - **End-user trigger** — optional pointer to the real commits / repo that surfaced the need
   - **How to use this umbrella** — instructions for closing children + updating checklist
5. **Back-link every child** — post a comment on each child issue pointing to the umbrella

Use the `/umbrella-open` skill to mechanize steps 3-5. See [`.claude/skills/umbrella-open/SKILL.md`](../skills/umbrella-open/SKILL.md).

## Maintenance

- **No automatic checkbox sync**: GitHub does not un-check umbrella items when a child closes. When you close a child issue, **manually edit the umbrella** to tick the checkbox.
- **New children join the same umbrella**: don't open a second parallel umbrella. Edit the existing umbrella's body to add the new child + post its back-link.
- **Re-running `/umbrella-open` creates duplicates**: idempotency is not automatic. Only run on first setup.

## Reference implementation

[`PsychQuant/macdoc#75`](https://github.com/PsychQuant/macdoc/issues/75) — *Tracking: Manuscript review automation*, tracks 12 child issues across 4 repos (`ooxml-swift`, `che-word-mcp`, `psychquant-claude-plugins`, `che-apple-mail-mcp`). Created 2026-04-15 during tatsuma taxometric paper archive work.

## Non-goals

- Does not replace repo-level issue tracking. Children stay in their repos so external users still find them via repo search.
- No GitHub Projects v2 automation. Umbrellas are plain markdown checklists for simplicity.
- Not every cross-cutting comment needs an umbrella. Use judgment: if the work is one back-and-forth comment chain, skip the umbrella.
