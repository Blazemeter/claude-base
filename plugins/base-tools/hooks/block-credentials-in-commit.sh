#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks staging/committing key & credential FILES
# and commits whose staged diff contains secret material. See
# ../../../STANDARDS.md "Safety guardrails".
#
# Complements block-secrets-on-write.sh (which guards Write/Edit content): this
# one guards `git add` / `git commit`, catching files that already exist on disk
# (e.g. an id_rsa the user dropped into the repo, or a .env created by tooling).
#
# This file intentionally contains literal secret REGEX patterns, so it is
# allowlisted in scripts/validate.py (SCAN_EXCLUDE_FILES) and .gitleaks.toml.
#
# Exit 2 = block. Honors a HUMAN-exported CLAUDE_SAFETY_OVERRIDE=1.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
cmd="$(echo "$payload" | jq -r '.tool_input.command // ""')"

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] block-credentials-in-commit OVERRIDE: $cmd" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

# Only act on git add / git commit.
is_add=0; is_commit=0
[[ "$cmd" =~ git[[:space:]]+add ]] && is_add=1
[[ "$cmd" =~ git[[:space:]]+commit ]] && is_commit=1
if [ "$is_add" = 0 ] && [ "$is_commit" = 0 ]; then
  exit 0
fi

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "Key files (id_rsa, *.pem, *.key, *.pfx, *.p12, *.jks, *.keystore," >&2
  echo "*.ppk), .env files, AWS 'credentials' files, and any staged content" >&2
  echo "matching a secret pattern must not be committed." >&2
  echo "" >&2
  echo "Remove the file/secret from the index (git restore --staged <f>), add" >&2
  echo "it to .gitignore, and move real secrets to your secret manager. If this" >&2
  echo "is a deliberate test fixture, export CLAUDE_SAFETY_OVERRIDE=1 (logged)." >&2
  exit 2
}

is_forbidden_path() {
  local base
  base="$(basename "$1")"
  case "$base" in
    id_rsa|id_dsa|id_ecdsa|id_ed25519|credentials) return 0 ;;
    .env|.env.*) return 0 ;;
    *.pem|*.key|*.pfx|*.p12|*.jks|*.keystore|*.ppk) return 0 ;;
  esac
  return 1
}

# --- git add <paths> : check the literal path arguments ---------------------
if [ "$is_add" = 1 ]; then
  read -ra _toks <<< "$cmd"
  _seen_add=0 _prev=""
  for t in "${_toks[@]}"; do
    if [ "$_seen_add" = 1 ]; then
      case "$t" in
        -*) ;;  # skip flags
        *) if is_forbidden_path "$t"; then reject "refusing to 'git add' key/credential file: $t"; fi ;;
      esac
    fi
    if [ "$_prev" = "git" ] && [ "$t" = "add" ]; then _seen_add=1; fi
    _prev="$t"
  done
fi

# --- git commit : inspect the staged tree -----------------------------------
if [ "$is_commit" = 1 ]; then
  staged="$(git diff --cached --name-only 2>/dev/null || true)"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if is_forbidden_path "$f"; then
      reject "staged key/credential file blocked from commit: $f"
    fi
  done <<< "$staged"

  # Scan added lines of the staged diff for secret material.
  patterns=(
    'AKIA[0-9A-Z]{16}'
    'aws_secret_access_key[[:space:]]*=[[:space:]]*[^[:space:]]+'
    '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----'
    'xox[baprs]-[0-9a-zA-Z-]{10,}'
    'glpat-[0-9A-Za-z_-]{20,}'
    'ghp_[0-9A-Za-z]{36,}'
  )
  diff_content="$(git diff --cached -U0 2>/dev/null || true)"
  added="$(printf '%s\n' "$diff_content" | grep '^+' || true)"
  if [ -n "$added" ]; then
    for re in "${patterns[@]}"; do
      if printf '%s' "$added" | grep -Eiq "$re"; then
        reject "staged content matches secret pattern /$re/"
      fi
    done
  fi
fi

exit 0
