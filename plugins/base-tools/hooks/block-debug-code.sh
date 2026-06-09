#!/usr/bin/env bash
# PreToolUse hook for Write|Edit — blocks debug statements that should not be
# committed. Detects print() / console.log / debugger / pdb.set_trace() / etc.
# in source files. Allows intentional logging in dedicated log files and test
# utilities. See ../../../STANDARDS.md "Safety guardrails".
#
# Exit 2 = block. Honors a HUMAN-exported CLAUDE_SAFETY_OVERRIDE=1.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
file_path="$(echo "$payload" | jq -r '.tool_input.file_path // ""')"
content="$(echo "$payload" | jq -r '.tool_input.new_string // .tool_input.content // ""')"

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] block-debug-code OVERRIDE: $file_path" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

[ -z "$content" ] && exit 0

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "Debug statements (console.log, pdb.set_trace, debugger, etc.) should" >&2
  echo "not be committed — they belong in dev branches or IDE sessions." >&2
  echo "" >&2
  echo "If this is a logging utility, debug module, or test utility, export" >&2
  echo "CLAUDE_SAFETY_OVERRIDE=1 in your shell (logged & audited)." >&2
  exit 2
}

# Get file extension (lowercase)
ext="${file_path##*.}"
ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
base_name=$(basename "$file_path")
base_lower=$(echo "$base_name" | tr '[:upper:]' '[:lower:]')

# --- Allow debug statements in debug-specific files ---
# These are meant to contain debug utilities or logging, not production code
case "$base_lower" in
  *debug*|*logger*|*log*.js|*log*.ts|*log.py|*log*.go|*logging*.py|*console*.ts)
    # Debug utility file; allow debug patterns
    exit 0
    ;;
esac

# --- JavaScript / TypeScript ---
if [[ "$ext_lower" =~ ^(js|jsx|ts|tsx)$ ]]; then
  # console.log, console.debug, console.warn, console.error (in non-error context)
  if echo "$content" | grep -Eq '(^|[^a-zA-Z])console\.(log|debug)\('; then
    reject "console.log/debug() found in $file_path"
  fi
  # debugger statement
  if echo "$content" | grep -Eq '(^|[^a-zA-Z])debugger([^a-zA-Z]|$)'; then
    reject "debugger statement found in $file_path"
  fi
  # .only() and .skip() in test files (should be caught elsewhere, but also here)
  if [[ "$file_path" =~ \.(test|spec)\.(js|jsx|ts|tsx)$ ]]; then
    if echo "$content" | grep -Eq '(describe|it|test|xit|fit|xdescribe)\.only\('; then
      reject ".only() found in test file $file_path — should use .skip() for isolation"
    fi
  fi
fi

# --- Python ---
if [[ "$ext_lower" == "py" ]]; then
  # print() calls (except in __main__ or test contexts, and except log/debug context)
  if [[ ! "$file_path" =~ (__main__|test_|_test\.py|tests\.py) ]]; then
    if echo "$content" | grep -Eq '(^|[^a-zA-Z#])print\('; then
      reject "print() found in $file_path — use logging instead"
    fi
  fi
  # pdb.set_trace() / breakpoint()
  if echo "$content" | grep -Eq 'pdb\.set_trace\(\)|breakpoint\('; then
    reject "pdb.set_trace()/breakpoint() found in $file_path"
  fi
fi

# --- Java ---
if [[ "$ext_lower" == "java" ]]; then
  # System.out.println / System.err.println (not in test files)
  if [[ ! "$file_path" =~ (Test\.java|Tests\.java) ]]; then
    if echo "$content" | grep -Eq 'System\.(out|err)\.println\('; then
      reject "System.out/err.println() found in $file_path — use logger instead"
    fi
  fi
fi

# --- Ruby ---
if [[ "$ext_lower" == "rb" ]]; then
  # puts, p, print (in non-test, non-script context)
  if [[ ! "$file_path" =~ (_spec\.rb|_test\.rb|bin/|script/) ]]; then
    if echo "$content" | grep -Eq '(^|[[:space:]])p\(|^[[:space:]]*puts[[:space:]]'; then
      reject "puts/p found in $file_path — use logger instead"
    fi
  fi
  # require 'pry' / binding.pry
  if echo "$content" | grep -Eq "binding\.pry|require[[:space:]]+.pry"; then
    reject "pry breakpoint found in $file_path"
  fi
fi

# --- Go ---
if [[ "$ext_lower" == "go" ]]; then
  # fmt.Println, log.Println (outside test files)
  if [[ ! "$file_path" =~ _test\.go$ ]]; then
    if echo "$content" | grep -Eq 'fmt\.Println\(|fmt\.Printf\('; then
      reject "fmt.Println/Printf found in $file_path — use proper logging"
    fi
  fi
fi

# --- General patterns ---
# debugger; (multiple languages use this)
if echo "$content" | grep -Eq '(^|[[:space:]])debugger[[:space:]]*;'; then
  reject "debugger; statement found in $file_path"
fi

# TODO/FIXME with urgent tone (less strict, just a warning pattern)
# Intentionally skip this for now — too noisy

exit 0
