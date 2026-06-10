#!/usr/bin/env bash
# PreToolUse hook for mcp__claude_ai_Atlassian_Rovo__createJiraIssue — blocks
# the create call if the `AI_generated` label is missing from the payload, and
# tells Claude exactly how to retry. See ../../../STANDARDS.md rule 2.
#
# Why block-and-retry instead of silently mutating the payload? Hooks have a
# stable contract for blocking with a stderr message that Claude reads on the
# next turn; in-place mutation of tool input is not portable across Claude
# Code versions. The retry is one extra LLM turn — fine for a JIRA create.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"

if [ "${CLAUDE_STANDARDS_SKIP:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] inject-ai-generated-label SKIP" >> "$LOG_DIR/standards-skip.log"
  exit 0
fi

# Labels live under tool_input.labels (an array). Some Rovo MCP shapes nest
# fields under tool_input.fields.labels — handle both.
has_label="$(
  printf '%s' "$payload" | python3 -c '
import sys, json
ti = json.load(sys.stdin).get("tool_input", {}) or {}
labels = list(ti.get("labels") or []) + list((ti.get("fields") or {}).get("labels") or [])
print("yes" if any(str(l).lower() == "ai_generated" for l in labels) else "")
'
)"

if [ -n "$has_label" ]; then
  exit 0
fi

echo "claude-base STANDARDS rule 2: this createJiraIssue call is missing the" >&2
echo "'AI_generated' label. Add it to the labels array and retry, e.g." >&2
echo "" >&2
echo '  { ..., "labels": ["AI_generated", <your other labels>] }' >&2
echo "" >&2
echo "This is how the JIRA Ops team audits Claude-filed tickets. See" >&2
echo "STANDARDS.md at the root of claude-base. Set CLAUDE_STANDARDS_SKIP=1" >&2
echo "to bypass (logged & audited)." >&2
exit 2
