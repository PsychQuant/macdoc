## Why

PsychQuant org-wide security gaps surfaced via PsychQuant/macdoc#78 verification and audited in PsychQuant/macdoc#80: all 37+ public Swift/TeX/MCP repos lack secret scanning + push protection, newer extractions (2026-03+ — `pdf-to-latex-swift`, `ocr-swift`, `word-builder-swift`, `note-*`) have **no branch protection at all**, and org defaults are all OFF so every new repo inherits zero hardening. Supply-chain risk for the macdoc-chain (12 downstream Swift deps consumed via `~/bin/macdoc`) is material: a single compromised dep could pollute end-user binaries, and PR #89's `Closes #79.` trailer anti-pattern shows force-push blocking is also currently unreliable on newly-extracted repos.

## What Changes

- **Org-level defaults turned ON** (`PsychQuant` org settings):
  - `secret_scanning_enabled_for_new_repositories`
  - `secret_scanning_push_protection_enabled_for_new_repositories`
  - `dependabot_alerts_enabled_for_new_repositories`
  - `dependabot_security_updates_enabled_for_new_repositories`
  - `dependency_graph_enabled_for_new_repositories`
- **Retroactive baseline hardening** on ~37 existing public Swift/TeX/MCP repos:
  - Secret scanning + push protection
  - Dependabot security updates (automated CVE fix PRs; alerts are already ON most repos)
  - Branch protection on `main`: `allow_force_pushes=false`, `allow_deletions=false`, `required_linear_history=true`, `required_approving_review_count=0`
- **Private repos** (~14) receive only free features: Dependabot alerts + branch protection. Secret scanning skipped (requires GHAS license).
- **New `SECURITY.md`** at `macdoc/` root — single canonical vulnerability-reporting doc for the entire ecosystem. Not duplicated per-repo.
- **New `macdoc/scripts/audit-security.sh`** — idempotent audit script that queries `gh api` for each target repo and reports drift. Matches existing `scripts/build-metallib.sh` pattern.
- **Updated `.claude/rules/common-release-flow.md`** — new Swift package releases must pass audit-security before tag push.

## Non-Goals

- **Org-wide 2FA requirement**: org has 5 collaborators; enforcing would immediately lock any without 2FA. Personal 2FA is already in place for the primary maintainer; marginal additional security does not justify collaborator-friction.
- **Private-repo GHAS license** (~$245/mo for 5 seats on free tier org): private repos like `apa-bib-*`, `PawSpace`, `vibe-mixing`, `contact-book` hold research code / personal projects, not production secrets. Free-tier features (Dependabot + branch protection) cover 80% of the threat model.
- **Per-repo `SECURITY.md` copies**: would require CI drift-check and 30+ synchronized copies. Single canonical doc at macdoc root is discoverable through GitHub org default.
- **`required_approving_review_count >= 1`**: would block the current single-maintainer `gh pr merge --squash --delete-branch` workflow. GitHub forbids approving your own PR, so this setting paralyses solo orgs.
- **Migrating to GitHub Enterprise / paid plan**: out of scope. All changes must work on current free tier.
- **Breaking fixes on existing `Closes #NNN` trailer-auto-close anti-pattern**: tracked in a separate follow-up. This change does not try to retroactively prevent IDD gate bypass.

## Capabilities

### New Capabilities

- `repository-security-baseline`: GitHub repo security settings (secret scanning, push protection, Dependabot alerts + security updates) + `main` branch protection defaults + org-level defaults for new repos + audit tooling (`scripts/audit-security.sh`) + contributor-facing documentation (`SECURITY.md`) + release-flow integration.

### Modified Capabilities

(none — this introduces a new capability, no existing spec has requirements about GitHub repo security settings.)

## Impact

- **Affected specs**: 1 new capability — `repository-security-baseline`.
- **Affected code**:
  - New file: `macdoc/SECURITY.md` (vulnerability reporting contract).
  - New file: `macdoc/scripts/audit-security.sh` (drift detection).
  - Modified file: `~/Developer/che-claude-config/rules/common-release-flow.md` (add audit-security gate to release checklist).
- **Affected systems** (config-only, no code commits):
  - `PsychQuant` org settings (5 defaults + dependency graph).
  - ~37 public PsychQuant repos: `macdoc`, `ooxml-swift`, `word-to-md-swift`, `common-converter-swift`, `word-builder-swift`, `pdf-to-latex-swift`, `ocr-swift`, `note-core-swift`, `note-to-pdf-swift`, `note-to-html-swift`, `markdown-swift`, `marker-swift`, `biblatex-apa-swift`, `che-word-mcp`, `che-pdf-mcp`, `che-ical-mcp`, `che-apple-mail-mcp`, `che-duckdb-mcp`, `che-logic-pro-mcp`, `che-latex-mcp`, `che-svg-mcp`, `che-telegram-bot-mcp`, `che-telegram-all-mcp`, `che-xcode-mcp`, `che-zotero-mcp`, `che-cn2tw-mcp`, `che-things-mcp`, `Paw`, `paw-monitor`, `GiftHub`, `MacLaw`, `pptx-swift`, `nougat-swift`, `autoresearch-swift`, `safari-browser`, `che-msg`, `che-biblatex-mcp`, `biblatex-apa-swift`, `psychquant-claude-plugins`, `sdd-starter`.
  - ~14 private PsychQuant Swift repos (partial hardening only).
- **Affected dependencies**: none (pure infra configuration, no `Package.swift` or `package.json` changes).
- **End-user impact**: zero code path changes to `macdoc` CLI or any MCP tool. Only visible change is GitHub's UI showing "Security" tab populated and "Report a vulnerability" button active on all public repos.
