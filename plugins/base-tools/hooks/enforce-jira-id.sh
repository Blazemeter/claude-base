#!/usr/bin/env bash
# PreToolUse hook for Bash — enforces JIRA ID presence on branch creation,
# new-branch pushes, and `gh pr create` commands. See ../../../STANDARDS.md rule 1.
#
# Matchers (in hooks.json) fire on every Bash call; this script then inspects
# tool_input.command and only acts on the relevant subcommands.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
cmd="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"

# Escape hatch — log every use so abuse is auditable.
if [ "${CLAUDE_STANDARDS_SKIP:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] enforce-jira-id SKIP: $cmd" >> "$LOG_DIR/standards-skip.log"
  exit 0
fi

# JIRA key pattern — matches any uppercase project key with a numeric suffix.
JIRA_RE='[A-Z][A-Z0-9_]+-[0-9]+'
# Placeholder pattern — an all-zero numeric suffix (MOB-00000, MOB-0, …).
# These satisfy JIRA_RE but point at no real issue, so they must be rejected.
PLACEHOLDER_RE='^[A-Z][A-Z0-9_]+-0+$'

# True (exit 0) when $1 contains at least one *real* (non-all-zero) JIRA key.
# Extracts every key it can find and checks that at least one is not a placeholder.
# Note: the first grep is neutralized with `|| true` and the empty case is guarded
# explicitly, so the function never trips `set -e` regardless of call context — the
# only non-zero it returns is its own deliberate "no real key" verdict.
has_real_jira_key() {
  local keys
  keys="$(printf '%s' "$1" | grep -oE "$JIRA_RE" || true)"
  [ -n "$keys" ] || return 1
  printf '%s\n' "$keys" | grep -qvE "$PLACEHOLDER_RE"
}

reject() {
  echo "claude-base STANDARDS rule 1: $1" >&2
  echo "" >&2
  echo "Every branch and PR Claude opens must reference a JIRA issue, e.g." >&2
  echo "  git checkout -b MOB-12345-fix-foo" >&2
  echo "  gh pr create --title 'MOB-12345: fix foo' --body '...'" >&2
  echo "" >&2
  echo "See STANDARDS.md at the root of claude-base, or set" >&2
  echo "CLAUDE_STANDARDS_SKIP=1 if this is a no-ticket chore (logged & audited)." >&2
  exit 2
}

reject_placeholder() {
  echo "claude-base STANDARDS rule 1: $1" >&2
  echo "" >&2
  echo "'MOB-00000' (or any all-zero key) is a placeholder, not a real issue —" >&2
  echo "work tracked against it has no Jira traceability. Create the task FIRST," >&2
  echo "then reference its real key:" >&2
  echo "" >&2
  echo "  * Claude-tooling work (claude-base / reporting-claude) lives under the" >&2
  echo "    AIDLC Epic MOB-50371 — create a child Task and link it via" >&2
  echo "    customfield_10014=MOB-50371 (the 'jira' skill does this for you)." >&2
  echo "  * Then: gh pr create --title 'MOB-<real>: …' …" >&2
  echo "" >&2
  echo "Set CLAUDE_STANDARDS_SKIP=1 only for a genuine no-ticket chore (logged & audited)." >&2
  exit 2
}

# --- Branch creation ---------------------------------------------------------
# Matches: git checkout -b NAME, git switch -c NAME, git branch NAME [start]
branch_name=""
if [[ "$cmd" =~ git[[:space:]]+checkout[[:space:]]+-b[[:space:]]+([^[:space:]]+) ]]; then
  branch_name="${BASH_REMATCH[1]}"
elif [[ "$cmd" =~ git[[:space:]]+switch[[:space:]]+-c[[:space:]]+([^[:space:]]+) ]]; then
  branch_name="${BASH_REMATCH[1]}"
elif [[ "$cmd" =~ git[[:space:]]+branch[[:space:]]+([^[:space:]-][^[:space:]]*) ]]; then
  # Skip when first non-flag arg is actually a list/delete flag combo; the
  # regex above already excludes leading-dash args, so this is a real name.
  branch_name="${BASH_REMATCH[1]}"
fi

if [ -n "$branch_name" ]; then
  if ! [[ "$branch_name" =~ $JIRA_RE ]]; then
    reject "branch name '$branch_name' does not contain a JIRA key."
  elif ! has_real_jira_key "$branch_name"; then
    reject_placeholder "branch name '$branch_name' only carries a placeholder JIRA key."
  fi
fi

# --- New-branch push ---------------------------------------------------------
# Matches: git push -u origin NAME, git push --set-upstream origin NAME
push_branch=""
if [[ "$cmd" =~ git[[:space:]]+push[[:space:]]+(.*[[:space:]])?(-u|--set-upstream)[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]+) ]]; then
  push_branch="${BASH_REMATCH[3]}"
fi

if [ -n "$push_branch" ]; then
  if ! [[ "$push_branch" =~ $JIRA_RE ]]; then
    reject "push branch '$push_branch' does not contain a JIRA key."
  elif ! has_real_jira_key "$push_branch"; then
    reject_placeholder "push branch '$push_branch' only carries a placeholder JIRA key."
  fi
fi

# --- gh pr create ------------------------------------------------------------
if [[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+create ]]; then
  # Check the whole command string — covers --title, --body, --body-file=…,
  # and HEREDOCs that get inlined into the command.
  if ! [[ "$cmd" =~ $JIRA_RE ]]; then
    reject "gh pr create call does not contain a JIRA key in title or body."
  elif ! has_real_jira_key "$cmd"; then
    reject_placeholder "gh pr create call references only a placeholder JIRA key."
  fi
fi

exit 0
