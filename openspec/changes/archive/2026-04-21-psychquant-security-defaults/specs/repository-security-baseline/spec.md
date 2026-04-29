## ADDED Requirements

### Requirement: Organization-level security defaults for new repositories

The PsychQuant GitHub organization SHALL have the following settings enabled so that every newly-created repository inherits baseline hardening without manual configuration:

- `secret_scanning_enabled_for_new_repositories`
- `secret_scanning_push_protection_enabled_for_new_repositories`
- `dependabot_alerts_enabled_for_new_repositories`
- `dependabot_security_updates_enabled_for_new_repositories`
- `dependency_graph_enabled_for_new_repositories`

These flags MUST be verifiable via `gh api /orgs/PsychQuant` returning `true` for each field.

#### Scenario: New repository can be hardened without per-repo configuration change

- **WHEN** a PsychQuant org member creates a new public repository via `gh repo create PsychQuant/<name>` and the release-flow runs `./scripts/audit-security.sh <name>` followed by the explicit `gh api PATCH/PUT` enable commands documented in the audit script
- **THEN** the repository has secret scanning, push protection, Dependabot alerts, Dependabot security updates, and dependency graph all active and the audit script exits `0`

Note: on GitHub free tier the `*_enabled_for_new_repositories` org flags act as policy intent rather than true auto-enablement; new repos still require explicit per-repo PATCH to flip feature status to `enabled`. GHAS-licensed orgs receive auto-enablement instantly, but PsychQuant is on free tier and therefore relies on the release-flow gate in Requirement "Release flow enforces audit before new-package first release".

#### Scenario: Organization settings readback

- **WHEN** `gh api /orgs/PsychQuant --jq '{secret_scanning_enabled_for_new_repositories, secret_scanning_push_protection_enabled_for_new_repositories, dependabot_alerts_enabled_for_new_repositories, dependabot_security_updates_enabled_for_new_repositories, dependency_graph_enabled_for_new_repositories}'` is executed
- **THEN** all five fields return `true`

### Requirement: Public repositories have secret scanning and push protection enabled

Every PsychQuant public repository SHALL have GitHub-native secret scanning enabled and push protection enabled, which MUST block commits containing recognised secret patterns from reaching `main`.

#### Scenario: Public repo exposes secret-scan as enabled

- **WHEN** `gh api /repos/PsychQuant/<repo>/security_and_analysis` is executed against any public repository
- **THEN** the response returns `200` with `secret_scanning.status = "enabled"` and `secret_scanning_push_protection.status = "enabled"`

#### Scenario: Push protection blocks known secret pattern

- **WHEN** a contributor attempts `git push` on a commit containing a recognised secret pattern (e.g. GitHub PAT, AWS access key)
- **THEN** the push is rejected server-side with a message identifying the leaked secret and instructing the contributor to remove it before retrying

### Requirement: Dependabot security updates produce automated pull requests

Every PsychQuant public repository SHALL have Dependabot security updates enabled so that CVE-matching dependency bumps arrive as automated pull requests. Alerts alone are insufficient; the automation-fix layer MUST also be active.

#### Scenario: Security update PR raised after CVE publication

- **WHEN** a CVE is published against a dependency pinned in any PsychQuant public repository
- **THEN** Dependabot opens a pull request within 24 hours proposing the minimal version bump to a patched release

#### Scenario: Automated fixes flag check

- **WHEN** `gh api /repos/PsychQuant/<repo>/automated-security-fixes` is executed
- **THEN** the response body is `{"enabled":true,"paused":false}`

### Requirement: Main branch protection baseline

Every PsychQuant public repository SHALL have `main` branch protection configured with the following settings, which form the minimum baseline:

- `allow_force_pushes = false`
- `allow_deletions = false`
- `required_linear_history = true`
- `required_approving_review_count = 0`

The protection object MUST NOT require pull-request reviews, because the organization is effectively single-maintainer and GitHub forbids approving one's own PR.

#### Scenario: Force-push to main is rejected

- **WHEN** any contributor attempts `git push --force origin main` against any PsychQuant public repository
- **THEN** the remote rejects the push with `protected branch hook declined` or equivalent message

#### Scenario: Main branch deletion is rejected

- **WHEN** any contributor attempts `git push origin :main` against any PsychQuant public repository
- **THEN** the remote rejects the deletion with `protected branch hook declined`

#### Scenario: Linear history enforced

- **WHEN** a contributor attempts to merge a pull request using a non-squash merge method that would introduce a merge commit
- **THEN** GitHub blocks the merge and requires squash or rebase instead

### Requirement: Private repositories receive free-tier hardening

Every PsychQuant private repository SHALL have Dependabot alerts enabled. Secret scanning, push protection, and branch protection SHALL NOT be required on private repos because the free tier does not license GHAS for private repositories and branch protection on private repos requires GitHub Pro (paid tier).

#### Scenario: Private repo receives free-tier alert coverage

- **WHEN** `gh api /repos/PsychQuant/<private-repo>/vulnerability-alerts` is executed
- **THEN** the response returns HTTP `204 No Content`, indicating Dependabot alerts are enabled

#### Scenario: Private repo branch protection is out of scope on free tier

- **WHEN** an operator attempts `gh api --method PUT /repos/PsychQuant/<private-repo>/branches/main/protection`
- **THEN** the response returns HTTP `403 Forbidden` with message "Upgrade to GitHub Pro or make this repository public to enable this feature", and the audit tooling classifies this as expected-out-of-scope rather than a baseline failure

### Requirement: Vulnerability-reporting contract is discoverable

The `macdoc` repository SHALL contain a root-level `SECURITY.md` file that states the vulnerability-reporting contact, preferred disclosure method, and acknowledgement-time commitment for the entire PsychQuant-swift ecosystem. The file SHALL be the single canonical source; per-repo duplication is forbidden to avoid drift.

#### Scenario: SECURITY.md present at macdoc root

- **WHEN** a user browses `https://github.com/PsychQuant/macdoc` in a web browser
- **THEN** GitHub displays a "Security policy" link in the sidebar pointing to `macdoc/SECURITY.md`

#### Scenario: SECURITY.md content covers required sections

- **WHEN** the `macdoc/SECURITY.md` file is opened
- **THEN** the file contains headed sections for (a) reporting-contact, (b) disclosure-expectations with acknowledgement time, (c) supported-versions policy, and (d) merge-policy statement referring to linear-history + squash-only

### Requirement: Audit tooling detects drift

The `macdoc` repository SHALL contain an executable script at `scripts/audit-security.sh` that queries GitHub for the security posture of a declarative list of target repositories and prints a pipe-delimited status matrix per repo. The script MUST be idempotent (safe to re-run) and MUST exit with non-zero status if any target repo fails the baseline.

#### Scenario: Audit passes when baseline is met

- **WHEN** `./scripts/audit-security.sh` is executed after Phase 2 completion with `macdoc` and the 12 macdoc-chain repos as targets
- **THEN** the script prints one row per repo, all rows show `OK` for each of secret-scan, push-protection, dependabot-alerts, security-updates, branch-protection, and the script exits with status `0`

#### Scenario: Audit fails when a repo regresses

- **WHEN** `./scripts/audit-security.sh` is executed and any target repository has at least one security feature disabled or branch protection missing
- **THEN** the script prints the failing repo row highlighted with `FAIL` in at least one column, lists the missing features, and exits with non-zero status

### Requirement: Release flow enforces audit before new-package first release

The release-flow documentation at `~/Developer/che-claude-config/rules/common-release-flow.md` SHALL require that any new Swift package intended for `PsychQuant/<name>-swift` must pass `./scripts/audit-security.sh <name>` before its first tagged release is published. Existing packages releasing a subsequent version SHALL re-run the audit at the maintainer's discretion.

#### Scenario: First release of a new package blocked without audit pass

- **WHEN** a maintainer prepares the first release of a new PsychQuant Swift package
- **THEN** the release-flow checklist requires a passing audit-security run against the new repo as a precondition, and the maintainer is directed to fix any failing baseline before tagging `v0.1.0`

#### Scenario: Subsequent releases include audit as recommended step

- **WHEN** a maintainer prepares a non-first release (e.g., `v0.2.0` onward) of an existing package
- **THEN** the release-flow checklist lists `audit-security.sh` as a recommended pre-release step without blocking the release on it
