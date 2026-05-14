#!/usr/bin/env bash
# PostToolUse hook for Write|Edit — appends an audit line per file change.
#
# Wired up in ../hooks.json. Stdin receives the tool-call payload as JSON.
# Writes to ${CLAUDE_PLUGIN_DATA}/audit.log so the log survives plugin upgrades.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
LOG_FILE="$LOG_DIR/audit.log"
mkdir -p "$LOG_DIR"

payload="$(cat)"
tool="$(echo "$payload" | jq -r '.tool_name // "unknown"')"
target="$(echo "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // "n/a"')"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "[$ts] $tool $target" >> "$LOG_FILE"
