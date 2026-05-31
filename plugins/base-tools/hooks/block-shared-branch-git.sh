#!/usr/bin/env bash
# PreToolUse hook for Bash — protects shared branches from rewrite/clobber:
#   - push to master/main (any push, force or not)
#   - force push (-f / --force / --force-with-lease) to ANY shared branch
#   - git rebase while on a shared branch
#   - git reset --hard while on a shared branch
# Shared = master, main, develop[ment], staging, prod[uction], release/*, hotfix/*.
# See ../../../STANDARDS.md "Safety guardrails".
#
# Non-zero exit = block. Honors a HUMAN-exported CLAUDE_SAFETY_OVERRIDE=1.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
cmd="$(echo "$payload" | jq -r '.tool_input.command // ""')"

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] block-shared-branch-git OVERRIDE: $cmd" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

# Only act on git commands at all.
[[ "$cmd" =~ (^|[[:space:]])git([[:space:]]|$) ]] || exit 0

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "Shared branches (master, main, develop, staging, prod, release/*," >&2
  echo "hotfix/*) are protected from rewrite/clobber. Open a PR from a feature" >&2
  echo "branch instead of pushing/force-pushing/rebasing a shared branch." >&2
  echo "" >&2
  echo "If a human truly needs this, export CLAUDE_SAFETY_OVERRIDE=1 in your" >&2
  echo "shell (logged & audited). Do NOT --no-verify or otherwise bypass the" >&2
  echo "hook. Server-side branch protection should enforce this too." >&2
  exit 1
}

# Current branch (empty if not in a work tree / detached).
cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

is_shared() {
  local b="$1"
  [[ "$b" =~ ^(master|main|develop|development|staging|production|prod)$ ]] && return 0
  [[ "$b" =~ ^(release|hotfix)/ ]] && return 0
  return 1
}

# Does the command text explicitly mention a shared branch token?
mentions_shared=0
if [[ "$cmd" =~ (^|[[:space:]:/])(master|main|develop|development|staging|production|prod)([[:space:]]|$) ]]; then
  mentions_shared=1
fi
if [[ "$cmd" =~ (^|[[:space:]])(release|hotfix)/ ]]; then
  mentions_shared=1
fi
mentions_master_main=0
if [[ "$cmd" =~ (^|[[:space:]:/])(master|main)([[:space:]]|$) ]]; then
  mentions_master_main=1
fi

cur_shared=0
if [ -n "$cur" ] && is_shared "$cur"; then cur_shared=1; fi

# --- git push ---------------------------------------------------------------
if [[ "$cmd" =~ git[[:space:]]+push ]]; then
  is_force=0
  if [[ "$cmd" =~ (^|[[:space:]])(-f|--force|--force-with-lease)([[:space:]=]|$) ]]; then
    is_force=1
  fi

  # Rule A: never plain-push master/main (explicit ref, or implicitly the
  # current branch when nothing else is specified).
  if [ "$mentions_master_main" = 1 ]; then
    reject "push to master/main blocked."
  fi
  if [ "$cur" = "master" ] || [ "$cur" = "main" ]; then
    reject "push while on '$cur' targets a protected branch — blocked."
  fi

  # Rule B: force push to any shared branch.
  if [ "$is_force" = 1 ] && { [ "$cur_shared" = 1 ] || [ "$mentions_shared" = 1 ]; }; then
    reject "force push to a shared branch blocked."
  fi
fi

# --- git rebase -------------------------------------------------------------
if [[ "$cmd" =~ git[[:space:]]+rebase ]] && [ "$cur_shared" = 1 ]; then
  reject "git rebase while on shared branch '$cur' rewrites its history — blocked."
fi

# --- git reset --hard -------------------------------------------------------
if [[ "$cmd" =~ git[[:space:]]+reset ]] && [[ "$cmd" =~ (^|[[:space:]])--hard([[:space:]]|$) ]] && [ "$cur_shared" = 1 ]; then
  reject "git reset --hard while on shared branch '$cur' discards commits — blocked."
fi

exit 0
