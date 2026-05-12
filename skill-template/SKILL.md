---
name: <kebab-case-name>
category: <onboarding|build-test|vcs-pr|issue-mgmt|ci-cd|observability|data-store|security|hooks>
owner: team-<your-team>
permission-tier: <1|2|3>
mcps-used: []
version: 0.1.0
status: experimental
last-reviewed: <YYYY-MM-DD>
---

## Triggers
<!-- Natural-language phrases that should auto-load this skill.
     Be specific. Bad: "logs". Good: "fetch CloudWatch logs for service X around time T". -->
- "..."
- "..."

## Inputs
<!-- What the user/agent must supply. Mark required vs optional. -->
- **<name>** (required) — <what it is>
- **<name>** (optional) — <default behaviour if omitted>

## Steps
<!-- Numbered. Deterministic where possible. Reference the tools/MCPs used at each step. -->
1. ...
2. ...
3. ...

## Side effects
<!-- Be precise. Reviewers gate on this. -->
- Reads: ...
- Writes: ...
- Never touches: ...

## Verification
<!-- How does the user confirm the skill did the right thing? -->
- ...

## Failure modes
<!-- Known limits and what to do when they happen. -->
- **<symptom>** → <action>

## Examples
<!-- 2-3 real invocations. Copy from actual usage, not made-up. -->
### Example 1: <one-line scenario>
**Input:** ...
**Expected:** ...
