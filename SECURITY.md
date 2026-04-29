# Security Policy

This document is the canonical vulnerability-reporting contract for the **`PsychQuant` Swift package ecosystem** — everything published under `github.com/PsychQuant/*-swift` or consumed transitively by [`macdoc`](https://github.com/PsychQuant/macdoc). It replaces per-repo `SECURITY.md` copies (which would drift) with a single discoverable source. GitHub automatically surfaces this file in every PsychQuant repo's Security tab via the org-level default lookup.

## Reporting a vulnerability

**Preferred channel**: open a [private security advisory](https://github.com/PsychQuant/macdoc/security/advisories/new) against the `macdoc` repository. This starts a private conversation visible only to PsychQuant maintainers and the reporter.

**Backup channel**: email `mr.no.one01@gmail.com` with subject line beginning `[PsychQuant-security]`. Please do *not* open a public issue for security concerns — public issues are indexed immediately and the vulnerability becomes exploitable before a fix lands.

Include in your report:
- Affected repository name(s) and the minimum version you tested against.
- The vulnerability class (secret leak, SSRF, path traversal, deserialization, supply-chain, etc.).
- A minimal reproduction — ideally a failing test or a short script.
- Your proposed severity (informational / low / medium / high / critical).

## What you can expect

| Step | SLA |
|------|-----|
| Initial acknowledgement that report was received | **72 hours** |
| First triage & severity confirmation | **7 days** |
| Target fix release for high/critical findings | **30 days** from acknowledgement |
| CVE coordination (if requested) | via GitHub Security Advisory |

We credit reporters by name in the fix release notes unless you request anonymity.

## Supported versions

| Package class | Supported | Policy |
|---------------|-----------|--------|
| `macdoc` main branch | ✅ | Fixes land on `main`; published via GitHub Release tags. |
| `*-swift` packages consumed by `macdoc` (latest `v0.x`) | ✅ | Latest minor on each `0.x` line gets security patches. |
| `*-swift` packages consumed by `macdoc` (older `v0.x`) | ⚠️ | Best-effort only; upgrade recommended. |
| Private/research repos (`article*`, `*-kids-website`, `PawSpace`, etc.) | ❌ | Out of scope; pre-publication or personal code. |

## Hardening baseline (applied since 2026-04)

Every PsychQuant public repository consumed by `macdoc` has the following GitHub-native protections enabled. Use `macdoc/scripts/audit-security.sh` to verify any repo still meets the baseline:

- **Secret scanning** — GitHub detects known API key / token patterns in commits and blocks merges containing them.
- **Push protection** — developers are notified at `git push` time if a commit contains a recognised secret, with option to review or bypass (bypass is audit-logged).
- **Dependabot alerts** — open CVE notifications on pinned dependencies.
- **Dependabot security updates** — automated PRs proposing the minimal version bump to fix known CVEs.
- **Main branch protection baseline**:
  - `allow_force_pushes=false` — no rewriting published history.
  - `allow_deletions=false` — main branch cannot be deleted remotely.
  - `required_linear_history=true` — merges must be squash or rebase, no merge commits.
  - `required_approving_review_count=0` — reviews are not blocking (single-maintainer org); other controls above cover the attack surface.

## Private-repo policy

Private PsychQuant repositories (research code like `article*`, personal apps like `PawSpace`, `vibe-mixing`) receive only the **free-tier subset** of the baseline: **Dependabot alerts only**. Two GitHub features are unavailable on the free tier for private repos:

- **Secret scanning + push protection** require a GitHub Advanced Security (GHAS) license (~$49/user/month × 5 seats ≈ $245/mo) — not purchased for the free-tier org. Contributors are expected to self-audit for committed secrets before pushing.
- **Branch protection on `main`** requires GitHub Pro (paid tier) — also not purchased. Force-push to private `main` is therefore NOT blocked at the GitHub level; contributors rely on convention and not ever running `git push --force origin main`.

This means: if a secret is committed to a private repo, it will *not* be detected automatically; and if someone force-pushes over `main` in a private repo, GitHub will allow it. Rotate credentials before commit rather than after, and never use `--force` against a shared `main` branch.

## Merge policy

All PsychQuant public repos enforce:

1. **Squash merges only** (`gh pr merge --squash --delete-branch`). Merge commits are blocked by `required_linear_history=true`.
2. **No force-push to `main`**. If you need to rewrite history locally, do it on a feature branch and open a fresh PR.
3. **No PR self-approval required**, because the org is effectively single-maintainer; GitHub forbids approving your own PR anyway.

Bypassing any of these baselines requires updating `~/Developer/che-claude-config/rules/common-release-flow.md` and documenting why in a new PR against `macdoc`.

## Scope

**In scope**:
- All PsychQuant Swift packages consumed directly or transitively by `macdoc`.
- `macdoc` itself (CLI binary distributed via `~/bin/macdoc`).
- `che-word-mcp`, `che-pdf-mcp`, and other MCPs listed in the hardening baseline.
- The `audit-security.sh` script — if it has a bug, report it here too.

**Out of scope**:
- Claude Code plugins that wrap these packages (report to [`PsychQuant/psychquant-claude-plugins`](https://github.com/PsychQuant/psychquant-claude-plugins)).
- Third-party Swift packages (e.g. `apple/swift-argument-parser`) — report upstream.
- Social engineering of maintainers, rate-limiting GitHub APIs, or other non-code attacks.

## Changelog

| Date | Change | Verification |
|------|--------|--------------|
| 2026-04-19 | Hardening baseline applied via `psychquant-security-defaults` Spectra change (Phase 1 org defaults, Phase 2 macdoc-chain 12 repos, Phase 3 remaining 39 repos, Phase 4 tooling + docs). Tracked in [`PsychQuant/macdoc#80`](https://github.com/PsychQuant/macdoc/issues/80). | Re-run `./scripts/audit-security.sh` from the `macdoc` repo root; should exit `0` with all-green matrix. |
