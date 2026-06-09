#!/usr/bin/env bash
# PreToolUse hook for Write|Edit — blocks the call if obvious secret patterns
# appear in the new content. Exit 2 = block; exit 0 = allow.
#
# This is illustrative, not exhaustive. Replace with `gitleaks --pipe` or
# similar for production-grade scanning.

set -euo pipefail

payload="$(cat)"
content="$(printf '%s' "$payload" | python3 -c 'import sys,json; ti=json.load(sys.stdin).get("tool_input",{}); print(ti.get("new_string") or ti.get("content") or "")')"

# Patterns to block (case-insensitive). Tune for your project.
# Patterns target *assignments* / actual secret material, not bare env-var
# names — `aws_secret_access_key` appears legitimately in docs.
patterns=(
  'AKIA[0-9A-Z]{16}'                                # AWS access key id
  'aws_secret_access_key[[:space:]]*=[[:space:]]*[^[:space:]]+'  # AWS secret assignment
  '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----'
  'xox[baprs]-[0-9a-zA-Z-]{10,}'                    # Slack tokens
  'glpat-[0-9A-Za-z_-]{20,}'                        # GitLab personal access tokens
  'ghp_[0-9A-Za-z]{36,}'                            # GitHub personal access tokens
)

for re in "${patterns[@]}"; do
  if printf '%s' "$content" | grep -E -i -q -e "$re"; then
    echo "base-tools hook: blocked — content matches secret pattern /$re/" >&2
    echo "If this is a false positive, edit plugins/base-tools/hooks/block-secrets-on-write.sh." >&2
    exit 2
  fi
done

exit 0
