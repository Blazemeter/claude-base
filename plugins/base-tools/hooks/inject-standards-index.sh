#!/usr/bin/env bash
# SessionStart hook — inject a 1-page primer of the claude-base STANDARDS so the
# five baseline rules and safety guardrails are in context from turn one,
# without the model having to read the full STANDARDS.md every session.
#
# Pattern borrowed from speccraft's always-injected index.md: a short, stable
# summary is injected here; the full text in ../../../STANDARDS.md is the source
# of truth and is read on demand. Keep this primer SHORT and stable — it is
# paid for on every session start.
#
# SessionStart hooks: stdout is appended to the session context. We deliberately
# do not read stdin (matching the no-payload-needed pattern) so the hook can
# never block on a pipe. Always exits 0; this is priming, never a gate.
set -euo pipefail

cat <<'EOF'
## claude-base standards (always-injected primer)

This repo/org runs the claude-base marketplace. Five baseline rules govern every
Claude-driven action; the full text and rationale live in STANDARDS.md.

1. **JIRA ID** — every branch you create and every PR you open must carry a real,
   non-zero JIRA key (`[A-Z][A-Z0-9_]+-[0-9]+`). No placeholders (`MOB-00000`).
   Claude-tooling work goes under the AIDLC Epic MOB-50371.
2. **AI_generated label** — every JIRA issue created via Claude must carry the
   `AI_generated` label (pass it in `additional_fields.labels`).
3. **Claude attribution** — every commit you author includes a
   `Co-Authored-By: Claude` trailer.
4. **Doc task** — feature / user-facing work must assess customer-doc impact and,
   only when needed and human-confirmed, file a linked `DOC-ready:` task via the
   `file-doc-task` skill.
5. **JIRA lifecycle** — keep the related issue's status + comment trail in step
   with the work via the `jira-lifecycle` skill: In Progress on start, In Review
   + PR link on PR open, Testing on deploy, Closed when verified. Forward-only.

**Safety guardrails** (PreToolUse hooks) block, without a human override, the
actions Claude should never take autonomously: compute/datastore mutations,
pushing/forcing/rebasing shared branches, committing secrets, disabling tests,
and bypassing hooks. A guardrail that fires is signal — surface it, don't bypass.

Escape hatches (logged & audited): `CLAUDE_STANDARDS_SKIP=1` for the process
rules above; a human-exported `CLAUDE_SAFETY_OVERRIDE=1` for the safety
guardrails. Read STANDARDS.md before relying on either.
EOF
