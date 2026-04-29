#!/usr/bin/env bash
# audit-security.sh — PsychQuant repo security baseline auditor
#
# Queries GitHub for the security posture of PsychQuant repos and prints a
# pipe-delimited status matrix. Exits non-zero on any baseline failure.
#
# Baselines:
#   public  — secret scanning + push protection + Dependabot alerts +
#             Dependabot security updates + branch protection (force-push
#             blocked, deletion blocked, linear history) on main.
#   private — Dependabot alerts + branch protection only (no GHAS license
#             on free-tier org, so secret scanning is not available).
#
# Tracked in PsychQuant/macdoc#80 via Spectra change
# `psychquant-security-defaults`. Baseline details in macdoc/SECURITY.md.

set -euo pipefail

ORG="PsychQuant"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_LIST="${SCRIPT_DIR}/_phase2-targets.txt"
PHASE3_PUBLIC_LIST="${SCRIPT_DIR}/_phase3-public.txt"
PHASE3_PRIVATE_LIST="${SCRIPT_DIR}/_phase3-private.txt"

FAIL=0

usage() {
  cat <<EOF
Usage:
  $0                         Audit all Phase 2 + Phase 3 targets (default)
  $0 <repo>                  Audit a single repo (auto-detects public/private)
  $0 --list <file>           Audit repos listed one-per-line in <file>
  $0 --help                  Show this message
Environment: requires \`gh\` CLI authenticated against an account with read
access to PsychQuant org.
EOF
}

require_gh_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "error: gh CLI is not authenticated. Run \`gh auth login\` first." >&2
    exit 64
  fi
}

is_private_repo() {
  local repo="$1"
  local priv
  priv=$(gh api "/repos/${ORG}/${repo}" --jq '.private' 2>/dev/null || echo "unknown")
  [[ "$priv" == "true" ]]
}

audit_one() {
  local repo="$1"
  local private_repo=false
  is_private_repo "$repo" && private_repo=true

  local sec secret_scan push_prot sec_updates alerts prot_json branch_prot
  sec=$(gh api "/repos/${ORG}/${repo}" --jq '.security_and_analysis // {}' 2>/dev/null || echo '{}')
  secret_scan=$(echo "$sec" | jq -r '.secret_scanning.status // "disabled"')
  push_prot=$(echo "$sec" | jq -r '.secret_scanning_push_protection.status // "disabled"')
  sec_updates=$(echo "$sec" | jq -r '.dependabot_security_updates.status // "disabled"')

  if gh api "/repos/${ORG}/${repo}/vulnerability-alerts" >/dev/null 2>&1; then
    alerts="enabled"
  else
    alerts="disabled"
  fi

  prot_json=$(gh api "/repos/${ORG}/${repo}/branches/main/protection" 2>/dev/null || echo '{}')
  if echo "$prot_json" | jq -e '.url' >/dev/null 2>&1; then
    # Note: `// fallback` treats false as falsy in jq, so we cannot use it for
    # boolean fields where `false` is the desired baseline value. Read the raw
    # value and check existence separately.
    local afp alo lin
    afp=$(echo "$prot_json" | jq -r 'if has("allow_force_pushes") then .allow_force_pushes.enabled | tostring else "missing" end')
    alo=$(echo "$prot_json" | jq -r 'if has("allow_deletions") then .allow_deletions.enabled | tostring else "missing" end')
    lin=$(echo "$prot_json" | jq -r 'if has("required_linear_history") then .required_linear_history.enabled | tostring else "missing" end')
    if [[ "$afp" == "false" && "$alo" == "false" && "$lin" == "true" ]]; then
      branch_prot="OK"
    else
      branch_prot="PARTIAL"
    fi
  else
    branch_prot="MISSING"
  fi

  local status="OK" tier
  if $private_repo; then
    tier="private"
    # Free-tier orgs cannot apply branch protection to private repos (needs Pro).
    # Only check Dependabot alerts for private repos.
    if [[ "$alerts" != "enabled" ]]; then status="FAIL"; fi
    printf '%-32s | %-8s | %-9s | %-8s | %-9s | %-8s | %-12s\n' \
      "$repo" "N/A" "N/A" "$alerts" "N/A" "N/A(tier)" "${tier}(${status})"
  else
    tier="public"
    if [[ "$secret_scan" != "enabled" ]]; then status="FAIL"; fi
    if [[ "$push_prot" != "enabled" ]]; then status="FAIL"; fi
    if [[ "$alerts" != "enabled" ]]; then status="FAIL"; fi
    if [[ "$sec_updates" != "enabled" ]]; then status="FAIL"; fi
    if [[ "$branch_prot" != "OK" ]]; then status="FAIL"; fi
    printf '%-32s | %-8s | %-9s | %-8s | %-9s | %-8s | %-12s\n' \
      "$repo" "$secret_scan" "$push_prot" "$alerts" "$sec_updates" "$branch_prot" "${tier}(${status})"
  fi

  if [[ "$status" == "FAIL" ]]; then FAIL=1; fi
  return 0
}

print_header() {
  printf '%-32s | %-8s | %-9s | %-8s | %-9s | %-8s | %-12s\n' \
    "REPO" "SECRET" "PUSH-PROT" "ALERTS" "SEC-UPDT" "BRANCH" "TIER(STATUS)"
  printf -- '------------------------------------------------------------------------------------------------------------\n'
}

audit_list_file() {
  local list="$1"
  if [[ ! -f "$list" ]]; then
    echo "error: target list not found: $list" >&2
    exit 64
  fi
  while IFS= read -r repo; do
    [[ -z "$repo" || "$repo" =~ ^# ]] && continue
    audit_one "$repo"
  done < "$list"
}

require_gh_auth

case "${1:-}" in
  --help|-h)
    usage
    exit 0
    ;;
  --list)
    if [[ -z "${2:-}" ]]; then
      echo "error: --list requires a file path" >&2
      exit 64
    fi
    print_header
    audit_list_file "$2"
    ;;
  "")
    print_header
    audit_list_file "$PHASE2_LIST"
    audit_list_file "$PHASE3_PUBLIC_LIST"
    audit_list_file "$PHASE3_PRIVATE_LIST"
    ;;
  *)
    print_header
    audit_one "$1"
    ;;
esac

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "✓ All audited repos meet baseline"
  exit 0
else
  echo "✗ One or more repos failed baseline; see FAIL rows above"
  exit 1
fi
