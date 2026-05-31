#!/usr/bin/env bash
# PreToolUse hook for Write|Edit — stops Claude from disabling or skipping tests
# to make CI green. Blocks build-level test disabling anywhere, and test-skip
# annotations when the edited file looks like a test. See ../../../STANDARDS.md
# "Safety guardrails".
#
# A hook can't read intent — a legitimately quarantined flaky test looks the
# same as a cover-up. So this blocks and asks a human to confirm via the
# override; it does not silently allow.
#
# Non-zero exit = block. Honors a HUMAN-exported CLAUDE_SAFETY_OVERRIDE=1.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
content="$(echo "$payload" | jq -r '.tool_input.new_string // .tool_input.content // ""')"
file_path="$(echo "$payload" | jq -r '.tool_input.file_path // ""')"

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] block-test-skips OVERRIDE: $file_path" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

[ -z "$content" ] && exit 0

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "Don't disable or skip failing tests to get CI green — fix the test or" >&2
  echo "the code under test. If a test must be quarantined (e.g. a tracked" >&2
  echo "flaky), a human should confirm: export CLAUDE_SAFETY_OVERRIDE=1 in your" >&2
  echo "shell (logged & audited) and reference the tracking ticket in the diff." >&2
  exit 1
}

# --- Build-level test disabling (any file) ----------------------------------
if echo "$content" | grep -Eq -- '-DskipTests|-Dmaven\.test\.skip|<skipTests>[[:space:]]*true|<maven\.test\.skip>[[:space:]]*true|maven\.test\.skip[[:space:]]*=[[:space:]]*true'; then
  reject "build config disables test execution (skipTests / maven.test.skip)."
fi

# --- Test-skip annotations (only when the file looks like a test) -----------
is_test_file=0
case "$file_path" in
  *Test.java|*Tests.java|*TestCase.java|*IT.java) is_test_file=1 ;;
  *_test.py|*test_*.py|*_spec.rb) is_test_file=1 ;;
  *.test.js|*.test.jsx|*.test.ts|*.test.tsx) is_test_file=1 ;;
  *.spec.js|*.spec.jsx|*.spec.ts|*.spec.tsx) is_test_file=1 ;;
  */test/*|*/tests/*|*/__tests__/*|*\\test\\*|*\\tests\\*) is_test_file=1 ;;
esac

if [ "$is_test_file" = 1 ]; then
  # Java / JUnit
  if echo "$content" | grep -Eq '(^|[^A-Za-z@])@(Disabled|Ignore)([^A-Za-z]|$)'; then
    reject "test-skip annotation (@Disabled/@Ignore) added to a test file."
  fi
  # Python pytest / unittest
  if echo "$content" | grep -Eq '@(pytest\.mark\.skip|pytest\.mark\.skipif|unittest\.skip)|pytest\.skip\(|\.skipTest\('; then
    reject "test-skip marker (pytest.mark.skip / unittest.skip) added to a test file."
  fi
  # JS / TS (jest, mocha, jasmine)
  if echo "$content" | grep -Eq '(^|[^A-Za-z.])(xit|xdescribe|pending)\(|(it|describe|test)\.skip\(|\.skip\('; then
    reject "test-skip marker (.skip/xit/xdescribe/pending) added to a test file."
  fi
fi

exit 0
