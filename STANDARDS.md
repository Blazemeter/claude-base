# Claude marketplace standards

Single source of truth for the three baseline rules every Claude-driven action
in our orgs must follow. Enforced by hooks in `plugins/base-tools/` (client
side) and by reusable GitHub Actions in `.github/workflows/` (server side).

Skill authors: link to this file from your `SKILL.md` so the model has the
rules in context when it works.

---

## 1. JIRA ID in branch names and PR descriptions

Every branch Claude creates, and every PR Claude opens, must reference a JIRA
issue.

- **At PR open time**, at least *one* of the branch name, PR title, or PR body
  must contain a JIRA key matching `[A-Z][A-Z0-9_]+-[0-9]+`
  (e.g. `MOB-49737`, `SECVULN-1508`). The server-side workflow checks all
  three independently and does **not** require the keys to match across them
  — that flexibility is intentional so a single multi-ticket PR can list
  several keys.
- **Branch creation** (`git checkout -b`, `git switch -c`, `git branch <name>`)
  is also gated client-side: the new branch name itself must contain a JIRA
  key. This is stricter than the server check because branch names are the
  primary handle Claude uses to correlate work across repos.
- **Prefer the PR title** when you have a choice — GitHub's automatic
  JIRA-link enrichment keys off the title (e.g. `MOB-49737: revert spring-boot`).

**Why**: lets `gh`, `jira`, and our `multi-repo-ticket-status` skill correlate
work across repos without manual tagging.

**Enforced by**:
- Client: `plugins/base-tools/hooks/enforce-jira-id.sh` (PreToolUse on `Bash`)
- Server: `.github/workflows/jira-id-lint.yml` (required status check)

## 2. `AI_generated` label on JIRA issues created via Claude

Every JIRA issue created by an LLM tool path must carry the label
`AI_generated`. This is the audit hook — without it we can't separate
Claude-filed tickets from human-filed ones.

**Why**: post-hoc audit of LLM-filed work; lets the JIRA Ops team measure
volume and quality of AI-filed tickets, and quickly reverse a bad batch.

**Enforced by**:
- Client: `plugins/base-tools/hooks/inject-ai-generated-label.sh`
  (PreToolUse on `mcp__claude_ai_Atlassian_Rovo__createJiraIssue`)
- Server: nightly audit script (see `scripts/jira_label_audit.py` — planned)
  that adds the label retroactively to any issue created by a `claude-*`
  service account that's missing it.

## 3. Claude attribution on every commit it authors

Every commit Claude creates must include a `Co-Authored-By: Claude …` trailer
in the commit message. The default Claude Code system prompt already appends
this; the hook just guards against drift (e.g. user-supplied messages without
the trailer).

**Why**: `git log --grep="Co-Authored-By: Claude"` becomes a reliable audit
query. Reviewers can spot Claude-authored changes at a glance.

**Enforced by**:
- Client: `plugins/base-tools/hooks/enforce-claude-attribution.sh`
  (PreToolUse on `Bash`, matches `git commit`)
- Server: `.github/workflows/claude-attribution-lint.yml` (required status
  check, only enforced when the PR carries the `ai-generated` label so
  humans aren't blocked).

---

## Safety guardrails

Beyond the three *standards* rules above (which are about process hygiene), the
plugin ships a set of *safety* guardrails: PreToolUse hooks that block
destructive actions Claude should never take autonomously. The point is to save
us from ourselves — when Claude runs unattended, or a tired developer clicks
"yes" at 11pm, these hooks are the backstop.

| Guardrail | Hook | Blocks |
|---|---|---|
| Compute is read-only | `block-ec2-cloud-mutations.sh` | Creating/starting/stopping/terminating/deleting AWS EC2 instances and GCP Compute instances. `describe`/`get`/`list` pass. |
| Datastores are read-only | `block-datastore-mutations.sh` | Destructive/creative DynamoDB, S3, Redis, and Mongo CLI ops (put/delete/drop/flush/rb/rm/upload, `s3api` create/delete/put, `redis-cli` writes, `mongoimport`/`mongorestore`) — even in dev/staging. Reads/downloads/dumps pass. |
| Shared branches are protected | `block-shared-branch-git.sh` | `git push` to `master`/`main`; force push to any shared branch; `git rebase` / `git reset --hard` while on a shared branch (`master`, `main`, `develop`, `staging`, `prod`, `release/*`, `hotfix/*`). |
| No secrets in commits | `block-credentials-in-commit.sh` | `git add`/`git commit` of key/credential files (`id_rsa`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.jks`, `*.keystore`, `*.ppk`, `.env`, AWS `credentials`) and any staged diff matching a secret pattern. |
| No skipping failing tests | `block-test-skips.sh` | Adding `@Disabled`/`@Ignore`, `pytest.mark.skip`, `.skip(`/`xit`/`xdescribe`/`pending` in test files, or `-DskipTests`/`maven.test.skip` in build files — i.e. disabling tests to make CI green. |
| No bypassing hooks | `block-hook-bypass.sh` | `--no-verify` / `git commit -n`, `core.hooksPath` overrides, `HUSKY=0`, `chmod`/`rm` on hook files, and **inlined** `CLAUDE_*_SKIP=`/`CLAUDE_SAFETY_OVERRIDE=` command prefixes. |

**Do not "fix" a hook failure by bypassing it.** A guardrail that fires has
caught something worth a human's attention. Surface the blocked action and let a
human decide — don't reach for `--no-verify`, edit the hook, or inline an
override prefix.

**Server-side complement**: the push/force/rebase rules are guardrails for
*Claude*, not a replacement for GitHub branch protection. Keep `master`/`main`
protected (no force push, required PR review) so the same rules hold for humans
and for any path that doesn't run these hooks.

### Safety override

When a destructive action is genuinely required, a **human** exports
`CLAUDE_SAFETY_OVERRIDE=1` in their shell for that session. Every use is logged
to `${CLAUDE_PLUGIN_DATA}/base-tools/safety-override.log`. This is deliberately
separate from `CLAUDE_STANDARDS_SKIP` (above) so loosening process hygiene and
loosening a safety guardrail are distinct, auditable choices.

The hooks read the override from their **own** environment, so Claude inlining
`CLAUDE_SAFETY_OVERRIDE=1 <command>` as a prefix does **not** work (it only sets
the variable for the child command, not the hook) — and `block-hook-bypass.sh`
explicitly rejects that inline form.

---

## Escape hatch

Set `CLAUDE_STANDARDS_SKIP=1` in the environment to bypass the client-side
*standards* hooks (JIRA ID, attribution, label) for a single session. Safety
guardrails use the separate `CLAUDE_SAFETY_OVERRIDE=1` documented above. **Every skip is logged** to
`${CLAUDE_PLUGIN_DATA}/base-tools/standards-skip.log` and the server-side
GitHub Action still runs at PR time, so abuse is visible. Use only for:

- One-off chores that don't have a JIRA ticket (housekeeping, doc fixes).
- Recovering from a bad regex match — and then fix the regex.

## Owning these standards

This file and the hooks/workflows in this repo are the canonical version. The
dual-repo mirror (PerfectoMobileDev/claude-base ↔ Blazemeter/claude-base)
keeps both orgs in sync. Changes go through the normal claude-base PR review
(6 required CI gates including `verify`).
