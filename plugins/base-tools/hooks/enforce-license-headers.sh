#!/usr/bin/env bash
# PreToolUse hook for Write|Edit — enforces license/copyright headers in new
# source files. Detects when a new source file is created without a standard
# license header. Skips config, data, and generated files. See
# ../../../STANDARDS.md "Safety guardrails".
#
# Exit 2 = block. Honors a HUMAN-exported CLAUDE_SAFETY_OVERRIDE=1.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
file_path="$(echo "$payload" | jq -r '.tool_input.file_path // ""')"
content="$(echo "$payload" | jq -r '.tool_input.new_string // .tool_input.content // ""')"

# We can't reliably detect if a file is "new" from PreToolUse context alone
# (Edit could be creating or modifying). So we check if the file appears to be
# a source file AND looks like it's being created (short, no existing history).
# A better approach: check if it's a source file and has NO header whatsoever.

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] enforce-license-headers OVERRIDE: $file_path" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

[ -z "$content" ] && exit 0

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "New source files must include a license/copyright header at the top." >&2
  echo "Add one of the following (adjust as needed for your project):" >&2
  echo "" >&2
  echo "  // Copyright YYYY Company Name. All rights reserved." >&2
  echo "  // Licensed under the Apache License, Version 2.0 ..." >&2
  echo "" >&2
  echo "or" >&2
  echo "" >&2
  echo "  # Copyright YYYY Company Name" >&2
  echo "  # SPDX-License-Identifier: Apache-2.0" >&2
  echo "" >&2
  echo "If this file is intentional, export CLAUDE_SAFETY_OVERRIDE=1 in your" >&2
  echo "shell (logged & audited)." >&2
  exit 2
}

# Get file extension (lowercase)
ext="${file_path##*.}"
ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
base_name=$(basename "$file_path")

# --- Skip non-source files ---
# Config, data, build, generated files don't need headers
case "$ext_lower" in
  # Data & config
  json|yaml|yml|xml|toml|ini|conf|config|properties|env)
    exit 0
    ;;
  # Build & test fixtures
  txt|csv|md|markdown|rst|adoc|asciidoc)
    exit 0
    ;;
  # Generated/template files
  generated|min|map|lock|svg|ico)
    exit 0
    ;;
  # Non-source extensions
  ""|bin|pdf|zip|tar|gz|bz2)
    exit 0
    ;;
esac

# Skip files by name pattern
case "$base_name" in
  Makefile|Dockerfile|docker-compose.yml|package.json|package-lock.json)
    exit 0
    ;;
  *.min.js|*.min.css|.env.example|Gemfile|*.lock|*.gradle)
    exit 0
    ;;
  # Test fixtures, examples
  example*|fixture*|mock*|stub*)
    exit 0
    ;;
esac

# --- Source file extensions that need headers ---
case "$ext_lower" in
  # JavaScript/TypeScript
  js|jsx|ts|tsx|mjs|cjs)
    ;;
  # Python
  py|pyw)
    ;;
  # Java
  java)
    ;;
  # Go
  go)
    ;;
  # Ruby
  rb)
    ;;
  # C/C++/C#
  c|cpp|cc|cxx|h|hpp|cs)
    ;;
  # Rust
  rs)
    ;;
  # Shell
  sh|bash|zsh|ksh)
    ;;
  # Other languages
  php|swift|kotlin|groovy|scala|pl|pm|lua|vim|r|R)
    ;;
  # If we got here and it's not a recognized source file, skip it
  *)
    exit 0
    ;;
esac

# --- Check for license/copyright headers ---
# Look for common patterns in the first 10 lines
first_lines=$(echo "$content" | head -10)

# Common license header patterns:
# - "Copyright" (anywhere in first 10 lines)
# - "SPDX-License-Identifier"
# - "Licensed under"
# - License abbreviation (Apache-2.0, MIT, GPL, BSD, etc.)
if echo "$first_lines" | grep -qiE '(copyright|spdx-license-identifier|licensed under|apache|mit|gpl|bsd)'; then
  # Has a license header
  exit 0
fi

# No license header found — reject
reject "new source file $file_path missing license/copyright header (found in first 10 lines)"
