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

# The createJiraIssue MCP tool reads labels ONLY from tool_input.additional_fields.labels
# (there is no top-level `labels` param — the schema is additionalProperties:false, so a
# top-level `labels` is dropped/rejected and the label never lands on the ticket). Check
# additional_fields.labels first; also tolerate the legacy tool_input.labels /
# tool_input.fields.labels shapes so older payloads don't false-block.
has_label="$(
  printf '%s' "$payload" | python3 -c '
import sys, json
ti = json.load(sys.stdin).get("tool_input", {}) or {}
af = ti.get("additional_fields") or {}
labels = (
    list(af.get("labels") or [])
    + list(ti.get("labels") or [])
    + list((ti.get("fields") or {}).get("labels") or [])
)
print("yes" if any(str(l).lower() == "ai_generated" for l in labels) else "")
'
)"

if [ -n "$has_label" ]; then
  exit 0
fi

echo "claude-base STANDARDS rule 2: this createJiraIssue call is missing the" >&2
echo "'AI_generated' label. Labels go under additional_fields.labels (the MCP" >&2
echo "tool has no top-level 'labels' param). Add it there and retry, e.g." >&2
echo "" >&2
echo '  { ..., "additional_fields": { "labels": ["AI_generated", <your other labels>] } }' >&2
echo "" >&2
echo "This is how the JIRA Ops team audits Claude-filed tickets. See" >&2
echo "STANDARDS.md at the root of claude-base. Set CLAUDE_STANDARDS_SKIP=1" >&2
echo "to bypass (logged & audited)." >&2
exit 2
