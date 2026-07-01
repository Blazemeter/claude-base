#!/usr/bin/env bash
# PreToolUse hook for Bash — the CLIENT-SIDE enforcement of STANDARDS rule #4.
#
# Fires on `gh pr create`. Opening a PR is the ONE universal event every
# workflow shares — a spec-driven pipeline, the bug-fix pipeline, a brand-new
# pipeline someone builds on claude-base, or a developer working by hand. By
# gating the PR (rather than a pipeline-specific "finalize" step), every one of
# them INHERITS the doc-task decision requirement with zero per-pipeline code.
#
# It blocks the PR unless a doc-task DECISION has been recorded for the branch's
# JIRA key. A decision is ANY terminal outcome of the `file-doc-task` skill:
# a ticket filed/updated, "not required" (human said no), or "not applicable"
# (pure refactor / internal change — out of rule #4 scope). The skill writes a
# marker file per key; this hook only checks that one exists.
#
# Matcher (in hooks.json) fires on every Bash call; this script inspects
# tool_input.command and only acts on `gh pr create`.
set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR" 2>/dev/null || true

payload="$(cat)"
cmd="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"

# Only gate PR creation.
[[ "$cmd" =~ gh[[:space:]]+pr[[:space:]]+create ]] || exit 0

# Escape hatch — same contract as the other rule hooks. Every use is logged.
if [ "${CLAUDE_STANDARDS_SKIP:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] require-doc-task-decision SKIP: $cmd" >> "$LOG_DIR/standards-skip.log" 2>/dev/null || true
  exit 0
fi

# Resolve the repo root; if we're not in a git repo there's no branch to gate.
repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ -z "$branch" ] && exit 0

# Extract a real (non-zero) JIRA key from the branch name. An all-zero
# placeholder is treated as absent — rule #1's hook already rejects those, so we
# don't double-report here; we only gate branches that carry a real key.
key="$(printf '%s' "$branch" \
  | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' \
  | grep -vE '^[A-Z][A-Z0-9_]+-0+$' \
  | head -n1 || true)"
[ -z "$key" ] && exit 0

# A decision marker for this key satisfies the gate. The `file-doc-task` skill
# writes it under <repo>/.claude/doc-task-decisions/<KEY>.json at every terminal
# outcome (filed / updated / not-required / not-applicable).
marker="$repo_root/.claude/doc-task-decisions/$key.json"
[ -f "$marker" ] && exit 0

# No decision on record → block the PR and tell Claude how to clear the gate.
{
  echo "claude-base STANDARDS rule #4: no documentation decision recorded for $key."
  echo ""
  echo "Every feature / user-facing PR must first assess customer-doc impact."
  echo "Run the file-doc-task skill before opening the PR — it asks the developer"
  echo "the docs question once, then records the decision so this gate passes:"
  echo ""
  echo "  * needs docs  → files a linked DOC-ready: <feature> ticket"
  echo "  * no docs     → records 'not required' (a valid, complete outcome)"
  echo "  * refactor / internal-only change → records 'not applicable'"
  echo ""
  echo "The skill is idempotent — safe to run early (draft from the design) and"
  echo "again now. It writes .claude/doc-task-decisions/$key.json; once that"
  echo "exists this PR is unblocked."
  echo ""
  echo "Set CLAUDE_STANDARDS_SKIP=1 only for a genuine no-ticket chore (logged & audited)."
} >&2
exit 2
