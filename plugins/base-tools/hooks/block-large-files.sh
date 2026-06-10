#!/usr/bin/env bash
# PreToolUse hook for Write|Edit — blocks commits of large files that shouldn't
# be in version control. Prevents accidental commits of databases, videos, and
# other binary blobs that bloat the repository. See ../../../STANDARDS.md
# "Safety guardrails".
#
# Thresholds: files >10MB are always blocked; files >1MB are warned.
# Whitelisted: image files (PNG, JPG, GIF) up to 5MB if they look legitimate.
#
# Exit 2 = block. Honors a HUMAN-exported CLAUDE_SAFETY_OVERRIDE=1.

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
file_path="$(echo "$payload" | jq -r '.tool_input.file_path // ""')"
new_string="$(echo "$payload" | jq -r '.tool_input.new_string // .tool_input.content // ""')"

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] block-large-files OVERRIDE: $file_path ($(echo -n "$new_string" | wc -c) bytes)" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

# Estimate file size (in bytes)
file_size=$(echo -n "$new_string" | wc -c)

# Thresholds (in bytes)
HARD_LIMIT=$((10 * 1024 * 1024))   # 10 MB — always block
SOFT_LIMIT=$((1 * 1024 * 1024))    # 1 MB — warn for non-images
IMAGE_LIMIT=$((5 * 1024 * 1024))   # 5 MB — allow images

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "Large files should not be committed to version control. Use external" >&2
  echo "storage (S3, artifact registry, LFS, etc.) instead." >&2
  echo "" >&2
  echo "If this file is intentional, export CLAUDE_SAFETY_OVERRIDE=1 in your" >&2
  echo "shell (logged & audited). Do NOT bypass the hook." >&2
  exit 2
}

# Skip empty files
[ "$file_size" -eq 0 ] && exit 0

# Get file extension (lowercase)
ext="${file_path##*.}"
ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

# --- Hard limit: always block files >10 MB ---
if [ "$file_size" -gt "$HARD_LIMIT" ]; then
  reject "file exceeds 10 MB hard limit ($(( file_size / 1024 / 1024 )) MB: $file_path)"
fi

# --- Soft limit: allow images up to 5 MB; block others >1 MB ---
if [ "$file_size" -gt "$SOFT_LIMIT" ]; then
  case "$ext_lower" in
    png|jpg|jpeg|gif|webp|svg|ico)
      if [ "$file_size" -gt "$IMAGE_LIMIT" ]; then
        reject "image file exceeds 5 MB limit ($(( file_size / 1024 / 1024 )) MB: $file_path)"
      fi
      # Image is OK
      exit 0
      ;;
    *)
      # Non-image >1 MB
      reject "file exceeds 1 MB ($(( file_size / 1024 )) KB: $file_path) — likely binary or data"
      ;;
  esac
fi

exit 0
