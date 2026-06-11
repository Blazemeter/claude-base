---
name: file-doc-task
description: File a documentation-planning JIRA task for a customer-facing feature, using the documentation team's standard template. Use at the end of a development workflow (after a PR is opened) for FEATURE or USER-FACING work — the skill first asks whether the change needs customer-facing documentation, and only creates the ticket if it does. Also use when a developer explicitly asks to "create a doc task", "file a docs ticket", "DOC-ready ticket", or hand work off to the documentation team. Do NOT use for pure refactors, internal-only fixes, or build/dependency chores.
allowed-tools: Read, Bash(gh *), mcp__claude_ai_Atlassian_Rovo__getJiraIssue, mcp__claude_ai_Atlassian_Rovo__createJiraIssue, mcp__claude_ai_Atlassian_Rovo__createIssueLink
---

# file-doc-task

Implements **STANDARDS rule #4**: feature / user-facing work must assess whether
it needs customer-facing documentation, and — only when it does — file a linked
documentation-planning JIRA task using the doc team's standard template.

The created ticket is for the **documentation team to plan from**; it is *not*
the documentation itself.

## When to use

- A development workflow has just finished a **feature** or **user-facing
  change** and opened a PR (e.g. the SDD pipeline `finish` phase, the bug-fix
  pipeline `finalize` phase for a user-visible fix).
- A developer explicitly asks to create a doc task / DOC-ready ticket / hand off
  to the docs team.

## When NOT to use

- Pure refactors, internal-only fixes, test-only changes, build/CI/dependency
  chores. These are out of scope for STANDARDS rule #4 — skip silently.
- When a doc task for this feature already exists (check first — see step 2).

## The decision gate (do this first)

1. **Classify the change.** If it is not a feature or user-facing change, stop —
   this skill does not apply.

2. **Ask the developer explicitly:**

   > "This looks customer-facing. Does it require customer-facing
   > documentation (release note, user/admin guide, API reference)?
   > [yes / no]"

   - If the answer is **no** → do not create a ticket. Record the decision in
     the dev workflow output (e.g. "Docs: not required — confirmed by
     <author>") and stop.
   - If **yes** → continue.

   Never decide "yes" on the developer's behalf. The whole point of the gate is
   that a human confirms customer impact.

3. **Check for an existing doc task** to avoid duplicates. Search for an open
   issue titled `DOC-ready: <feature>` linked to the engineering ticket. If one
   exists, link to it and stop.

## Creating the ticket

4. **Load the config** from `policy/doc-task.yaml` (project key, issue type,
   link type, default component/assignee). If the project key is still the
   unset placeholder, STOP and tell the developer the doc-task project must be
   configured first — do not guess a project.

5. **Load the template** from `references/doc-task-template.md` and build the
   description using **exactly** that structure and authoring rules. The rules
   are load-bearing — especially:
   - Plain English, active voice.
   - **Do not invent** UI text, behavior, steps, defaults, limits, permissions,
     supported environments, or unsupported scenarios.
   - Any field you cannot source → leave the placeholder and add a matching line
     under **Internal notes** as an open question. Never fabricate.

6. **Source the fields** from the workflow context:
   - `Related engineering ticket` → the MOB ticket driving the work.
   - `Engineering SME` → assignee of that ticket.
   - `Pull request / repo link` → the PR the workflow just opened
     (`gh pr view --json url`).
   - `Design or spec` / `Confluence` → from the SDD design doc or linked spec, if any.

7. **Create the issue** via `createJiraIssue`:
   - **Summary:** `DOC-ready: <customer-facing feature name>`
   - **Label:** `ready-for-docs` (the base-tools `inject-ai-generated-label`
     hook adds `AI_generated` automatically — do not remove it).
   - **Project / issue type:** from `policy/doc-task.yaml`.
   - **Description:** the filled template from step 5.

8. **Link it** to the engineering ticket via `createIssueLink` using the link
   type in `policy/doc-task.yaml` (default: `relates to`).

9. **Report back** the new doc-task key, its URL, and a one-line list of any
   fields left as open questions so the developer/docs team knows what's
   missing.

## Output

```
Doc task filed: <DOC-KEY> — DOC-ready: <feature>
  Linked to: <MOB-KEY> (<link type>)
  Open questions for docs (<n>): <comma-separated field names, or "none">
```

If the gate answer was "no":

```
Doc task: not required — confirmed by <author> for <MOB-KEY>.
```

## Notes

- This skill **creates a planning ticket only**. It does not write docs, edit
  Confluence, or modify the engineering ticket beyond the link.
- It is safe to run more than once — step 3's duplicate check prevents double
  filing.
- Pipelines should call this in their finalize phase but must honor the gate:
  a "no" is a valid, complete outcome.

## Related

- `references/doc-task-template.md` — the exact ticket structure and rules.
- `policy/doc-task.yaml` — deployment-specific JIRA project/issue-type config.
- STANDARDS.md rule #4 — the rule this skill enforces.
