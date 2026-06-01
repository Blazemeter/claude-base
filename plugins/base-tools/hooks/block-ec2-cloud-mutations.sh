#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks compute-instance MUTATIONS via the AWS and
# Google Cloud CLIs. Read-only calls (describe/get/list) are always allowed.
# See ../../../STANDARDS.md "Safety guardrails".
#
# Why: spinning up or tearing down instances costs money and can take prod
# capacity offline. Claude gets read access to inspect; humans create/destroy.
#
# Non-zero exit = block. Honors a HUMAN-exported CLAUDE_SAFETY_OVERRIDE=1
# (read from this hook's own environment — Claude inlining the var as a command
# prefix does NOT set it here, so it cannot self-bypass).

set -euo pipefail

LOG_DIR="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/base-tools"
mkdir -p "$LOG_DIR"

payload="$(cat)"
cmd="$(echo "$payload" | jq -r '.tool_input.command // ""')"

if [ "${CLAUDE_SAFETY_OVERRIDE:-0}" = "1" ]; then
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] block-ec2-cloud-mutations OVERRIDE: $cmd" >> "$LOG_DIR/safety-override.log"
  exit 0
fi

reject() {
  echo "claude-base SAFETY guardrail: $1" >&2
  echo "" >&2
  echo "Compute instances are read-only for Claude. Inspecting is fine" >&2
  echo "(aws ec2 describe-*, gcloud compute ... list/describe), but creating," >&2
  echo "starting, stopping, or deleting instances needs a human." >&2
  echo "" >&2
  echo "Ask a human to run it, or — if you ARE the human — export" >&2
  echo "CLAUDE_SAFETY_OVERRIDE=1 in your shell for this session (logged &" >&2
  echo "audited). Do NOT inline it as a command prefix and do NOT try to" >&2
  echo "bypass this hook. See STANDARDS.md 'Safety guardrails'." >&2
  exit 1
}

# --- AWS EC2 ----------------------------------------------------------------
# Blocklist of mutating verb prefixes. Anything else (describe-*, get-*, etc.)
# passes — a blocklist keeps new read-only verbs from being falsely blocked.
ec2_mut='(run|start|stop|terminate|reboot|create|delete|modify|authorize|revoke|associate|disassociate|attach|detach|allocate|release|import|register|deregister|enable|disable|replace|reset|cancel|accept|reject|assign|unassign|purchase|provision|move|bundle|copy|restore|update)-'
if [[ "$cmd" =~ aws[[:space:]]+ec2[[:space:]]+${ec2_mut} ]]; then
  reject "AWS EC2 mutating command blocked."
fi

# --- Google Cloud Compute ---------------------------------------------------
# gcloud compute <resource>[ <sub-group>...] <action>; block mutating actions.
# Resource paths can be nested (e.g. `compute instance-groups managed
# delete-instances`), so allow one OR MORE resource/group tokens before the
# action verb. Verbs cover the hyphenated forms (create-instances,
# delete-instances, recreate-instances, set-*, etc.) as well as the bare ones.
gcp_mut='(create|delete|start|stop|reset|recreate|update|resize|move|suspend|resume|abandon|rollback|create-[a-z-]+|delete-[a-z-]+|update-[a-z-]+|recreate-[a-z-]+|abandon-[a-z-]+|reset-[a-z-]+|rolling-[a-z-]+|add-[a-z-]+|remove-[a-z-]+|set-[a-z-]+|attach-[a-z-]+|detach-[a-z-]+)'
if [[ "$cmd" =~ gcloud[[:space:]]+compute[[:space:]]+([a-z-]+[[:space:]]+)+${gcp_mut}([[:space:]]|$) ]]; then
  reject "Google Cloud Compute mutating command blocked."
fi

exit 0
