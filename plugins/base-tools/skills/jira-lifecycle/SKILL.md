---
name: jira-lifecycle
description: Keep a related JIRA issue's status and comment trail in step with AI-driven work so the lifecycle is visible in JIRA metrics. Idempotent, forward-only transitions at each lifecycle point — move to In Progress when work starts, add progress comments for meaningful updates, post the PR link + summary when a PR opens (no status change), move to In Review when CI passes, move to Testing when on Staging, and Closed when verified on Production. Use whenever a Claude workflow acts on a related JIRA key (MOB-1234, SECVULN-99, …) at any of those points, or when a developer asks to "move the ticket to in progress / in review", "post the PR link on the ticket", or "close the ticket". Do NOT use when there is no related JIRA issue, and do NOT use to create issues.
allowed-tools: Read, Bash(gh *), mcp__claude_ai_Atlassian_Rovo__getJiraIssue, mcp__claude_ai_Atlassian_Rovo__getTransitionsForJiraIssue, mcp__claude_ai_Atlassian_Rovo__transitionJiraIssue, mcp__claude_ai_Atlassian_Rovo__addCommentToJiraIssue
---

# jira-lifecycle

Implements **STANDARDS rule #5**: every Claude-driven workflow that acts on a
related JIRA issue must keep that issue's **status** and **comment trail** in
step with the work, so AI throughput and stage-by-stage cycle time are
measurable from JIRA.

This skill transitions an **existing** issue and adds comments. It never creates
an issue (file the ticket first — rule #1).

## The lifecycle

| Lifecycle point | Move status to | Comment |
|---|---|---|
| `start` — Claude begins work on the related issue | **In Progress** | what's being attempted, by which workflow |
| `update` — a meaningful decision / blocker / finding | *(no change)* | the progress update |
| `pr` — a PR was opened | *(no change)* | PR link + summary (what changed, repo/branch, how to verify) |
| `ci` — the change passed CI | **In Review** | CI is green; moving to review |
| `staging` — deployed and tested on Staging | **Testing** | deployed to Staging; testing started |
| `done` — verified on Production | **Closed** | outcome + links to merged PR / release |

Callers invoke the skill once per point as the work reaches it, passing the JIRA
key and the point (`start` | `update` | `pr` | `ci` | `staging` | `done`).

## When to use

- A workflow has just **started** work tied to a JIRA key → `start`.
- A workflow hit a **meaningful update** worth recording → `update`.
- A workflow **opened a PR** for the work → `pr` (posts the link only, no status change).
- The change **passed CI** → `ci`.
- The change was **deployed and tested on Staging** → `staging`.
- Work is **verified on Production** → `done`.
- A developer explicitly asks to move/transition the ticket, post the PR link,
  or close it.

## When NOT to use

- There is **no related JIRA issue** — nothing to transition; stop silently.
- You need to **create** an issue — out of scope (use the `jira` skill / rule #1).
- The work is unrelated to any tracked ticket (one-off chores).

## How to run

1. **Resolve the related JIRA key.** Take it from the caller, the branch name,
   or the PR. No key → stop silently (nothing to do).

2. **Load the config** from `policy/jira-lifecycle.yaml`: the `stages` map
   (each stage's `status` name and numeric `transition_id`), `forward_only`, and
   the lifecycle `order`. Map the requested point to its stage:
   - `start` → `in_progress`
   - `ci` → `in_review`
   - `staging` → `in_testing`
   - `done` → `closed`
   - `update` → no stage (comment only)
   - `pr` → no stage (comment only — posts the PR link without transitioning)

3. **Fetch current state** with `getJiraIssue` (status + key). Use it for the
   forward-only check and to avoid redundant transitions.

4. **Decide the transition (forward-only).** If `forward_only` is true:
   - First, map the issue's **current status name** to its stage in `order` by
     matching it against each `stages.*.status` value. If the current status
     does **not** match any configured stage (e.g. a custom workflow status like
     "Blocked" or "Reopened"), treat it as **unmapped**: skip the transition
     entirely, add the comment anyway, and report the status as
     "unknown/unmapped — transition skipped". This is the safe fallback; never
     guess a position or move the issue based on an unmapped status.
   - If the current status maps to a stage that is **at or past** the target
     stage in `order`, do **not** transition — skip straight to the comment.
   - Never move an issue backwards. Re-running a point whose status is already
     set is a no-op on status.

5. **Transition if needed.** If a status change is warranted:
   - If the stage's `transition_id` is the unset placeholder (`__UNSET__`) —
     e.g. an `in_testing` stage on a workflow with no such status — **skip the
     transition**, add the comment anyway, and note in your report that the
     status was left unchanged (stage unset).
   - Otherwise call `getTransitionsForJiraIssue` to confirm the configured ID is
     currently available, then `transitionJiraIssue` with that numeric ID. If
     the ID isn't offered, report the mismatch rather than guessing a name.

6. **Add the comment** via `addCommentToJiraIssue`, using the shape for the
   point (below). For `pr`, gather PR details with `gh pr view --json url,title,headRefName,baseRefName` (or take them from the caller). Add a
   comment only when there is real signal — don't post empty "still working"
   noise.

7. **Report back** the key, the resulting status (or "unchanged — already at/past
   target" / "unchanged — stage unset"), and whether a comment was added.

## Comment shapes

Keep comments short, factual, and machine-skimmable. Do not invent detail you
can't source.

- **start**
  ```
  🤖 Work started by Claude (<workflow / skill name>).
  Scope: <one line on what's being attempted>.
  ```
- **update**
  ```
  🤖 Update: <the decision / blocker / finding>.
  ```
- **pr** (the load-bearing one for metrics — always include the link; no status change)
  ```
  🤖 PR opened: <PR url>
  <PR title> — <repo>@<headRef> → <baseRef>
  Summary: <what changed, 1–2 lines>.
  Verify: <how to verify, if known>.
  ```
- **ci**
  ```
  🤖 CI passed; moving to In Review.
  ```
- **staging**
  ```
  🤖 Deployed to Staging; testing started.
  ```
- **done**
  ```
  🤖 Verified on Production. Merged: <PR url> · Release: <link if any>.
  Outcome: <one line>.
  ```

## Output

```
JIRA lifecycle [<point>]: <KEY>
  Status: <new status> | unchanged — already at/past target | unchanged — stage unset
  Comment: added | skipped (no new signal)
```

## Notes

- **Idempotent and forward-only.** Safe to re-run a point; it won't move the
  issue backwards or double-transition.
- **Status mapping is org-config**, never hardcoded — it lives in
  `policy/jira-lifecycle.yaml`. A stage left unset there is skipped (comment
  still added), so this skill works unchanged across JIRA workflows that lack an
  **In Testing** status.
- This skill **only** transitions status and adds comments on an existing issue.
  It does not create issues, edit other fields, or touch Confluence.

## Related

- `policy/jira-lifecycle.yaml` — status names + numeric transition IDs per org.
- STANDARDS.md rule #5 — the rule this skill enforces.
- STANDARDS.md rule #1 — every branch/PR references a real JIRA key (the key this
  skill transitions).
