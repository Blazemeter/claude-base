#!/usr/bin/env bash
# PreToolUse hook for Bash — enforces the `Co-Authored-By: Claude` trailer on
# every `git commit -m …` invocation. See ../../../STANDARDS.md rule 3.
#
# Matches HEREDOC-style messages too because Claude Code inlines the heredoc
# into tool_input.command before invoking the shell.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
cmd="$(printf '%s' "$payload" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"

if [ "${CLAUDE_STANDARDS_SKIP:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] enforce-claude-attribution SKIP: $cmd" >> "$LOG_DIR/standards-skip.log"
  exit 0
fi

# Only inspect commands that actually create a commit.
if ! [[ "$cmd" =~ git[[:space:]]+commit ]]; then
  exit 0
fi

# Amend / no-edit / fixup paths re-use an existing message — let them through.
if [[ "$cmd" =~ --amend ]] && [[ "$cmd" =~ --no-edit ]]; then
  exit 0
fi
if [[ "$cmd" =~ --fixup ]]; then
  exit 0
fi

# Reject only when -m / -F is used (the message is on the command line). If
# neither is present, $EDITOR opens — we can't validate that path, and Claude
# Code never takes it interactively anyway.
#
# Matches short-option BUNDLES containing m or F (so `-am`, `-ma`, `-aF` all
# count, not just bare `-m`), plus the long --message / --file forms.
if ! [[ "$cmd" =~ (^|[[:space:]])(-[a-zA-Z]*[mF][a-zA-Z]*|--message|--file)([[:space:]=]|$) ]]; then
  exit 0
fi

# Case-insensitive match — accommodates both `Co-Authored-By:` and the GitHub
# canonical `Co-authored-by:`.
if echo "$cmd" | grep -qiE 'Co-Authored-By:[[:space:]]*Claude'; then
  exit 0
fi

echo "claude-base STANDARDS rule 3: commit message is missing the" >&2
echo "  Co-Authored-By: Claude <noreply@anthropic.com>" >&2
echo "trailer. The default Claude Code system prompt appends this — if you" >&2
echo "stripped it, please add it back so 'git log --grep' can find Claude" >&2
echo "authored commits." >&2
echo "" >&2
echo "Set CLAUDE_STANDARDS_SKIP=1 to bypass (logged & audited)." >&2
exit 2
