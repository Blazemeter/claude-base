#!/usr/bin/env bash
# Stop hook — close-out reminder for STANDARDS rule #5 (JIRA lifecycle).
#
# When Claude finishes a turn on a branch that references a real JIRA key, nudge
# it to keep that issue's status + comment trail current via the `jira-lifecycle`
# skill (the most-missed step: moving to In Review + posting the PR link).
#
# Honors "comment, don't spam": the reminder fires at most once per
# session+branch, deduped by a marker under ${CLAUDE_PLUGIN_DATA}. It is purely
# advisory — always exits 0, never blocks. Pattern borrowed from speccraft's
# Stop close-out reminder.
#
# We do not read stdin (no payload needed) so the hook can never block on a pipe.
set -euo pipefail

# Only meaningful inside a git repo.
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ -z "$branch" ] && exit 0

# Shared branches and detached HEAD carry no per-ticket work to track.
case "$branch" in
  main|master|develop|staging|prod|HEAD) exit 0 ;;
esac

# Extract a real (non-zero) JIRA key from the branch name. Mirrors the pattern
# enforced by enforce-jira-id.sh; an all-zero key is treated as absent.
key="$(printf '%s' "$branch" \
  | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' \
  | grep -vE '^[A-Z][A-Z0-9_]+-0+$' \
  | head -n1 || true)"
[ -z "$key" ] && exit 0

# Dedupe: at most one reminder per session + branch. Best-effort — if the data
# dir or marker can't be written (read-only TMPDIR, permissions), skip dedupe
# and still print. The hook must never block, so directory/marker failures are
# swallowed rather than allowed to trip `set -e`.
data_dir="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
slug="$(printf '%s' "${CLAUDE_SESSION_ID:-nosession}-${branch}" | tr -c 'A-Za-z0-9._-' '_')"
marker="$data_dir/jira-lifecycle-reminded.$slug"
if mkdir -p "$data_dir" 2>/dev/null; then
  [ -f "$marker" ] && exit 0
  : > "$marker" 2>/dev/null || true
fi

cat <<EOF
## claude-base — JIRA lifecycle reminder (STANDARDS rule #5)

This branch references **$key**. Before wrapping up, make sure that issue
reflects the current state of the work via the \`jira-lifecycle\` skill:

- opened a PR? → move **$key** to *In Review* and post the PR link + summary.
- deployed / verified complete? → advance to *Testing* / *Closed*.

The skill is forward-only and idempotent — if **$key** is already at or past the
right stage, it leaves the status alone. Skip entirely if no status change or
comment is warranted.
EOF
exit 0
