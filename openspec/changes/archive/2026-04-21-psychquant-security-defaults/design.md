## Context

PsychQuant is a free-tier GitHub organization with 5 collaborators, 44 public repos, 36 private repos. The macdoc project is the umbrella CLI that imports 12 Swift packages (public) as remote `url:` deps. Each imported package is a potential supply-chain vector: a compromise there flows directly into `~/bin/macdoc` for any user who reinstalls. The audit conducted during PsychQuant/macdoc#80 diagnosis revealed that every public PsychQuant repo has **secret scanning, push protection, and Dependabot security updates disabled**, and newer 2026-03+ extractions (`pdf-to-latex-swift`, `ocr-swift`, `word-builder-swift`, `note-*`) also have **no `main` branch protection at all**. Org-level `*_enabled_for_new_repositories` defaults are all `false`, meaning every future repo inherits zero hardening.

Stakeholders: the primary maintainer (account `kiki830621`, org owner), 4 collaborator accounts, and any end-user who installs `macdoc`. Constraints: must work on free tier (no GHAS purchase), must not break the single-maintainer `gh pr merge --squash --delete-branch` workflow, must not lock out any existing collaborator via sudden 2FA enforcement.

## Goals / Non-Goals

**Goals:**

- Eliminate the all-off security posture for both existing and future PsychQuant public repos.
- Provide a self-service audit mechanism to detect drift (`scripts/audit-security.sh`).
- Document vulnerability reporting contract (`SECURITY.md` at macdoc root).
- Integrate security gate into release flow so new packages cannot ship without baseline hardening.
- Keep single-maintainer squash-merge workflow functional.
- Achieve 80% threat-model coverage on free tier without introducing collaborator friction.

**Non-Goals:**

- Org-wide 2FA requirement (friction > benefit for 5-person solo-led org).
- Private-repo GHAS license (~$245/mo for marginal coverage of research/personal repos).
- Per-repo `SECURITY.md` duplication (single canonical file is sufficient given GitHub org-level display).
- `required_approving_review_count >= 1` on any repo (paralyses single-maintainer merges).
- Automated CI enforcement beyond `audit-security.sh` (no GitHub Action on every push; audit is opt-in pre-release).
- Retroactive fixes for historical `Closes #NNN` trailer anti-pattern (separate follow-up).

## Decisions

### Enable org-level defaults for new repos only

Toggle all five `*_enabled_for_new_repositories` settings on the PsychQuant org via `gh api --method PATCH /orgs/PsychQuant`. This covers `secret_scanning`, `secret_scanning_push_protection`, `dependabot_alerts`, `dependabot_security_updates`, and `dependency_graph`. Alternatives considered: (a) per-repo only — rejected because every new repo would start unhardened again; (b) also enable `advanced_security_enabled_for_new_repositories` — rejected because GHAS is paid and would fail silently without a license.

### Apply baseline branch protection without required reviews

Set `allow_force_pushes=false`, `allow_deletions=false`, `required_linear_history=true`, and `required_approving_review_count=0` on `main` for all public repos. Alternatives: (a) require 1 review — rejected because GitHub forbids self-approval and the org is effectively single-maintainer; (b) match whatever each repo currently has — rejected because newer extractions have no protection; (c) require signed commits — deferred (most commits already use GitHub web-flow signing; retrofitting local signing across 37 repos has low benefit for the churn).

### Skip GHAS license for private repos

Private repos get Dependabot alerts + branch protection only. Secret scanning and push protection require GHAS which costs ~$49/user/month × 5 seats ≈ $245/mo. Alternatives: (a) buy GHAS — rejected because private repos hold research/personal code, not production secrets; (b) migrate sensitive repos to public — rejected because some contain pre-publication research (`article1-*`).

### Place SECURITY.md in macdoc root only

Single `SECURITY.md` at `macdoc/SECURITY.md` serves as canonical vulnerability-reporting contract for the entire ecosystem. Alternatives: (a) per-repo `SECURITY.md` — rejected because 37+ synchronized copies would immediately drift and require CI drift-check infra; (b) put it in `.github/SECURITY.md` at the org level — not supported for orgs without a `.github` repo, and creating one adds maintenance overhead.

### Implement audit script as idempotent gh api loop

`scripts/audit-security.sh` iterates a declarative repo list, queries `gh api` endpoints (`/security_and_analysis`, `/vulnerability-alerts`, `/automated-security-fixes`, `/branches/main/protection`), and prints a pipe-delimited status matrix. Alternatives: (a) use `gh` with `--jq` inline — rejected because the ~10-field output needs custom formatting; (b) write in Swift as a `macdoc audit` subcommand — rejected because infra audit is orthogonal to document conversion; bash stays closer to the actual `gh api` contract.

### Gate new package releases on passing audit

Add a check to `common-release-flow.md`: before running a release script for a new Swift package, the maintainer must run `./scripts/audit-security.sh <repo>` and see all-green. Alternatives: (a) pre-push git hook — rejected because releases happen from many working trees and hooks are easy to bypass; (b) GitHub Action on repo creation — would need org-level workflow template which is a separate setup; deferred.

### Phased rollout in 4 stages

Phase 1: org-level defaults (single `gh api PATCH` call). Phase 2: macdoc-chain 12 repos (hardest to revert, impacts end users). Phase 3: remaining ~25 public PsychQuant repos. Phase 4: documentation + audit script + release-flow integration. Alternatives: (a) all-at-once — rejected because we'd discover any breakage across 37 repos simultaneously; (b) reverse order — rejected because docs first without implementation means empty promises.

## Risks / Trade-offs

- **Risk**: Enabling Dependabot security updates triggers a wave of auto-PRs on repos with old pinned dependencies (e.g., `note-core-swift@0.1.3`, `ooxml-swift@0.7.0`). → **Mitigation**: enable on one repo first (`markdown-swift` — smallest surface), observe PR count and CI impact, then roll out to the rest. Disable if noise is unmanageable; re-enable after clearing backlog.

- **Risk**: `required_linear_history=true` breaks non-squash merges if anyone accidentally uses `gh pr merge --merge`. → **Mitigation**: the team already uses squash exclusively; linear enforcement makes this explicit. Document in `SECURITY.md` under "Merge policy".

- **Risk**: Secret scanning reveals historical leaked credentials committed in git history before push-protection was enabled. → **Mitigation**: expected and desirable. Each finding gets triaged: rotate if still valid, mark as revoked if already handled. Not a blocker to rollout.

- **Risk**: The 5 collaborators may have pushed directly to `main` historically; `allow_force_pushes=false` could surprise them. → **Mitigation**: force-push was already blocked on `macdoc` and `ooxml-swift` (per audit); the baseline is consistent with existing behaviour, not new.

- **Risk**: `gh api` org-level endpoint requires org owner permission. If executor is not owner, Phase 1 fails with 403. → **Mitigation**: verified via `/orgs/PsychQuant` response that `kiki830621` is org owner; document this requirement in tasks.md so it's not a surprise mid-rollout.

- **Risk**: `security_and_analysis` endpoint returned 404 during audit — could mean feature-unavailable rather than feature-off. → **Mitigation**: tasks include a pre-check step that re-queries the endpoint after enabling org defaults; if still 404, fall back to per-repo enable via UI settings panel and document the limitation.

- **Trade-off**: No org-wide 2FA means a compromised collaborator credential can still push to private repos. Accepted because the threat model is supply-chain from public deps, not insider threat.

- **Trade-off**: `audit-security.sh` is opt-in (not enforced per push). Accepted because the release-flow gate catches the highest-stakes cases (new version tags) and the script is idempotent so any maintainer can re-run it.

## Migration Plan

**Pre-flight**: verify `kiki830621` has org owner role via `gh api /orgs/PsychQuant/memberships/kiki830621`. Fail fast if not.

**Phase 1 — Org defaults** (single repo-agnostic PATCH):
```
gh api --method PATCH /orgs/PsychQuant \
  -F secret_scanning_enabled_for_new_repositories=true \
  -F secret_scanning_push_protection_enabled_for_new_repositories=true \
  -F dependabot_alerts_enabled_for_new_repositories=true \
  -F dependabot_security_updates_enabled_for_new_repositories=true \
  -F dependency_graph_enabled_for_new_repositories=true
```
Verify by re-reading `/orgs/PsychQuant` and confirming all five flags are `true`.

**Phase 2 — macdoc-chain hardening**: loop over `common-converter-swift`, `word-to-md-swift`, `word-builder-swift`, `pdf-to-latex-swift`, `ocr-swift`, `note-core-swift`, `note-to-pdf-swift`, `note-to-html-swift`, `ooxml-swift`, `markdown-swift`, `marker-swift`, `biblatex-apa-swift`. For each: enable security features, apply branch protection. Validate by re-running `audit-security.sh` and confirming the per-repo matrix is all green.

**Phase 3 — remaining public repos**: same loop, different list (~25 entries).

**Phase 4 — institutionalise**:
1. Write `macdoc/SECURITY.md` (vulnerability reporting template).
2. Write `macdoc/scripts/audit-security.sh` (idempotent auditor).
3. Update `common-release-flow.md` with audit-security gate.

**Rollback**: every Phase is a `gh api` call. Rollback is symmetric: set flag back to `false`, delete branch protection, disable security features per-repo. Document rollback one-liner in `SECURITY.md`.

## Open Questions

None remaining — all 7 open questions surfaced in diagnosis were resolved during /spectra-discuss:
1. 2FA enforcement → no.
2. Branch protection strictness → baseline above, no req reviews.
3. Private repos GHAS → skip.
4. SECURITY.md placement → macdoc root only.
5. Audit script location → `macdoc/scripts/audit-security.sh`.
6. Rollout batching → 4 phases as above.
7. Verification criterion → `audit-security.sh` shows all-green per repo.
