---
name: umbrella-open
description: Open a cross-repo umbrella tracking issue and post back-link comments to all child issues. Use when the user wants to coordinate work spanning multiple GitHub repositories (e.g., ooxml-swift + che-word-mcp + plugin-level changes) with a single dashboard.
disable-model-invocation: true
argument-hint: <umbrella-repo> "<title>" <owner/repo#N>...
allowed-tools: Bash(gh *)
---

# Cross-Repo Umbrella Opener

Create an umbrella tracking issue and back-link it to every child issue across repos. Implements the pattern described in [`../../rules/cross-repo-umbrella.md`](../../rules/cross-repo-umbrella.md).

## Usage

```
/umbrella-open <umbrella-repo> "<umbrella-title>" <child-ref>...
```

Where:
- `<umbrella-repo>`: `owner/repo` of where the umbrella lives, typically `PsychQuant/macdoc`
- `<umbrella-title>`: the issue title, quoted. Start with `Tracking: ` by convention
- `<child-ref>`: each child as `owner/repo#N`. At least 1, no upper limit

Example:

```
/umbrella-open PsychQuant/macdoc "Tracking: Manuscript review automation" \
  PsychQuant/ooxml-swift#1 \
  PsychQuant/ooxml-swift#2 \
  PsychQuant/che-word-mcp#5
```

## Execution

You receive the invocation in `$ARGUMENTS`. Follow these steps.

### Step 1: Parse arguments

- `$0` = umbrella repo
- `$1` = umbrella title (already quoted at invocation)
- `$2` onwards = child refs

If fewer than 3 arguments (no children listed), abort and tell the user the command needs at least one child ref.

### Step 2: Validate child issues exist

For each child ref `<owner/repo>#<N>`:

```bash
gh issue view <N> --repo <owner/repo> --json title,state,url
```

Collect title + URL per child. If any child is CLOSED, warn the user and ask whether to proceed. If any child 404s, abort.

### Step 3: Gather umbrella context from the user

Ask the user (use AskUserQuestion tool if available, else plain text):

1. **Purpose paragraph**: 2-3 sentences on why this umbrella exists. What real-world need triggered it? If the user has no input, draft something from the child titles and let them confirm.
2. **Dependency tree (optional)**: if child issues block each other in a specific order, ask for the order. If the user says "none/flat", skip.
3. **End-user trigger (optional)**: a pointer to the originating commits/PRs/downstream repo. Can be blank.

### Step 4: Construct umbrella body

Template:

```markdown
## Purpose

<user-provided paragraph>

## Dependency tree

<ASCII diagram if provided, else skip this section>

## Issue checklist

Order reflects the dependency chain — top items should land first.

- [ ] [`owner/repo#N`](https://github.com/owner/repo/issues/N) — <title from gh issue view>
- [ ] ...

## End-user trigger

<optional pointer, else skip>

## How to use this umbrella

- **When working on a child issue**: open that issue, do the work, close it. **Manually** tick the checkbox here — GitHub does not auto-sync on close.
- **When discovering new cross-cutting work**: add it to the checklist above, and open a new child issue in the right repo, and post a back-link comment on that child (re-run `/umbrella-open` is NOT idempotent; do this manually for additions).

## Non-goals

- Not a replacement for repo-level issues. Children stay in their repos.
- No automatic checkbox sync.
- Not using GitHub Projects v2.
```

### Step 5: Create the umbrella issue

```bash
gh issue create --repo <$0> --title "<$1>" --body "<constructed body>"
```

Capture the returned URL. Parse out the umbrella issue number from the URL.

### Step 6: Post back-link to every child

For each child ref, post a comment:

```bash
gh issue comment <N> --repo <owner/repo> --body "## 🪢 Cross-repo tracking

This issue is part of the **<umbrella-title>** umbrella tracked at [<umbrella-repo>#<number>](<umbrella-url>).

See that issue for the full dependency tree and other related child issues."
```

Track success/failure per child.

### Step 7: Report

Output a summary table:

```
Umbrella: <umbrella-url>
Children back-linked: X/Y

Successes:
  ✓ PsychQuant/ooxml-swift#1
  ✓ PsychQuant/ooxml-swift#2

Failures (if any):
  ✗ PsychQuant/che-word-mcp#5 — 404 not found
```

Then remind the user:

> Next steps:
> - When any child issue closes, **manually** tick its checkbox in the umbrella.
> - To add new children later, edit the umbrella's body + post a back-link comment on the new child.

## Idempotency warnings

- Running this skill twice with the same arguments will create a **duplicate umbrella** and **duplicate back-link comments**. Before re-running, confirm the umbrella doesn't already exist.
- If the user wants to add new children to an existing umbrella (not create a new one), do NOT use this skill. Instead:
  1. `gh issue edit <umbrella-number> --repo <repo>` — append new checklist item
  2. `gh issue comment <new-child-N> --repo <repo>` — post back-link

## Common mistakes to avoid

- **Picking the wrong umbrella repo**: default to `PsychQuant/macdoc` unless the user says otherwise. Don't open umbrellas in binary repos (would become invisible when searching macdoc issues).
- **Forgetting the back-links**: the umbrella without back-links provides no discoverability from child issues. Step 6 is required, not optional.
- **Treating `Tracking:` title prefix as optional**: always include it so umbrella issues are greppable in issue lists.
