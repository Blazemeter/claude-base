#!/usr/bin/env bash
# PreToolUse hook for Bash — stops Claude from "fixing" a hook failure by
# bypassing the hooks. Blocks the common escape routes:
#   - git commit/push --no-verify  (and `git commit -n`)
#   - git -c core.hooksPath=...   /  git config core.hooksPath
#   - HUSKY=0 / HUSKY_SKIP_HOOKS
#   - chmod/rm against a hooks/ path or .git/hooks
#   - inlining CLAUDE_STANDARDS_SKIP= / CLAUDE_SAFETY_OVERRIDE= as a command
#     prefix (the override is meant to be EXPORTED by a human, not inlined)
# See ../../../STANDARDS.md "Safety guardrails".
#
# Non-zero exit = block. A human-exported CLAUDE_SAFETY_OVERRIDE=1 (read from
# this hook's own env, not the command string) lets legitimate human use through.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
cmd="$(echo "$payload" | jq -r '.tool_input.command // ""')"

# Inlined override attempts are caught BEFORE honoring the env override, so a
# human exporting the var still works but Claude inlining it does not.
if [[ "$cmd" =~ (^|[[:space:];&|])(CLAUDE_STANDARDS_SKIP|CLAUDE_SAFETY_OVERRIDE)= ]]; then
  echo "claude-base SAFETY guardrail: refusing an inlined override" >&2
  echo "(CLAUDE_STANDARDS_SKIP= / CLAUDE_SAFETY_OVERRIDE= as a command prefix)." >&2
  echo "" >&2
  echo "These overrides exist for HUMANS to export in their own shell, with" >&2
  echo "every use logged. Inlining them is a hook bypass. Surface the blocked" >&2
  echo "action to a human instead of working around the guardrail." >&2
  exit 1
fi

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] block-hook-bypass OVERRIDE: $cmd" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "Don't bypass a failing hook — it fired for a reason. Fix the underlying" >&2
  echo "issue, or surface the block to a human. If a human decides to override," >&2
  echo "they export CLAUDE_SAFETY_OVERRIDE=1 in their shell (logged & audited)." >&2
  exit 1
}

# Boundaries also recognize shell command separators (; & |) so a bypass token
# is not smuggled past with e.g. `git commit --no-verify; git status`.
# --no-verify on commit/push.
if [[ "$cmd" =~ (^|[[:space:];&|])--no-verify([[:space:];&|]|$) ]]; then
  reject "--no-verify skips git hooks — blocked."
fi
# `git commit -n` (short for --no-verify). Matches short-option bundles with n.
if [[ "$cmd" =~ git[[:space:]]+commit ]] && [[ "$cmd" =~ (^|[[:space:];&|])-[a-zA-Z]*n[a-zA-Z]*([[:space:];&|]|$) ]]; then
  reject "'git commit -n' skips hooks — blocked."
fi
# Redirecting / disabling the hooks path.
if [[ "$cmd" =~ core\.hooksPath ]]; then
  reject "overriding core.hooksPath disables repo hooks — blocked."
fi
# Husky escape hatches.
if [[ "$cmd" =~ (^|[[:space:];&|])HUSKY=0([[:space:];&|]|$) ]] || [[ "$cmd" =~ HUSKY_SKIP_HOOKS ]]; then
  reject "disabling Husky hooks (HUSKY=0 / HUSKY_SKIP_HOOKS) — blocked."
fi
# Tampering with hook files.
if [[ "$cmd" =~ (^|[[:space:]])(chmod|rm)[[:space:]] ]] && { [[ "$cmd" =~ hooks/ ]] || [[ "$cmd" =~ \.git/hooks ]]; }; then
  reject "modifying/removing hook files (chmod/rm on a hooks path) — blocked."
fi

exit 0
