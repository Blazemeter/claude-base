---
name: file-doc-task
description: File or update a documentation-planning JIRA task for a customer-facing feature, using the documentation team's standard template. Idempotent create-or-update — safe to run early (draft a DOC-ready ticket from the specs/design to guide development) and again at finalize (reconcile the description against what was actually shipped). For FEATURE or USER-FACING work the skill first asks once whether the change needs customer-facing documentation, and only creates the ticket if it does. Also use when a developer explicitly asks to "create a doc task", "file a docs ticket", "DOC-ready ticket", "update the doc task", or hand work off to the documentation team. Do NOT use for pure refactors, internal-only fixes, or build/dependency chores.
allowed-tools: Read, Bash(gh *), mcp__claude_ai_Atlassian_Rovo__getJiraIssue, mcp__claude_ai_Atlassian_Rovo__createJiraIssue, mcp__claude_ai_Atlassian_Rovo__editJiraIssue, mcp__claude_ai_Atlassian_Rovo__createIssueLink
---

# file-doc-task

Implements **STANDARDS rule #4**: feature / user-facing work must assess whether
it needs customer-facing documentation, and — only when it does — file a linked
documentation-planning JIRA task using the doc team's standard template.

The created ticket is for the **documentation team to plan from**; it is *not*
the documentation itself.

## Idempotent — create or update

This skill is **create-or-update**, not create-or-skip. It is safe to run more
than once for the same feature, by design:

- **No ticket yet** → file a new `DOC-ready:` ticket.
- **Ticket exists but is stale** (its description no longer reflects what was
  actually built, or fields that were open questions are now answerable) →
  **update** the existing ticket in place via `editJiraIssue`.
- **Ticket exists and is current** → link to it and stop (no edit).

This idempotency is what makes the two invocation points below safe — the
finalize pass reconciles the early draft rather than duplicating it.

## Two invocation points

A pipeline may call this skill at either or both of these points. The decision
gate in the next section asks the docs question **only once** — once a ticket
(or a recorded "no") exists, later runs skip straight to reconcile.

1. **Early — draft from specs (optional, recommended for spec-driven work).**
   Right after the design/tasks are reviewed and locked but before/while code is
   written. The ticket is drafted from the **intended** behavior in the specs
   and design, so it is available early to guide development and hold the work
   accountable to a stated customer outcome. The PR may not exist yet — record
   `Pull request / repo link` as `pending` and add a matching open question.
2. **Finalize — reconcile to as-built (always).** After the PR is opened. If a
   draft ticket already exists, fetch it and **update** it so the description
   reflects what was actually shipped (and fill in the now-known PR link). If no
   early draft was created (e.g. a resumed pipeline, or a non-spec-driven
   workflow), this pass creates the ticket fresh — same as a single finalize-only
   call.

## When to use

- A spec-driven workflow has reviewed and locked its design/tasks and wants an
  **early draft** to guide development (e.g. the SDD pipeline, right after its
  Step 4 spec-review gate).
- A development workflow has just finished a **feature** or **user-facing
  change** and opened a PR (e.g. the SDD pipeline `finish` phase, the bug-fix
  pipeline `finalize` phase for a user-visible fix) — to create or **reconcile**
  the ticket.
- A developer explicitly asks to create or update a doc task / DOC-ready ticket
  / hand off to the docs team.

## When NOT to use

- Pure refactors, internal-only fixes, test-only changes, build/CI/dependency
  chores. These are out of scope for STANDARDS rule #4 — skip silently.

## The decision gate (do this first)

1. **Classify the change.** If it is not a feature or user-facing change, stop —
   this skill does not apply.

2. **Check for a prior decision** so the gate is asked only once across the
   early + finalize passes. This skill has **no Jira search/JQL tool** — only
   `getJiraIssue`, which requires a key — so detection of an existing ticket is
   limited to these in-tools means, in order:
   - The caller passes a known doc-task key (e.g. `.sdd-meta.json`'s `doc_task`)
     → skip the question and go to **Reconcile an existing ticket** below. This
     is the reliable path; spec-driven pipelines persist the key on the early
     pass precisely so the finalize pass can find it.
   - Otherwise, if you know the engineering ticket key, fetch it with
     `getJiraIssue` and inspect its issue links for one titled
     `DOC-ready: <feature>`. If found, treat its key as the doc-task key and go
     to **Reconcile an existing ticket**.
   - The caller passes a recorded "no" (docs previously confirmed not required)
     → stop silently; do not re-ask.
   - Otherwise (first run, no key, no linked ticket found) → ask the gate in
     step 3. Because there is no search fallback, callers that may run this
     skill more than once **must** persist and pass back the doc-task key to
     avoid duplicate filings.

3. **Ask the developer explicitly** (only when there is no prior decision):

   > "This looks customer-facing. Does it require customer-facing
   > documentation (release note, user/admin guide, API reference)?
   > [yes / no]"

   - If the answer is **no** → do not create a ticket. Record the decision in
     the dev workflow output (e.g. "Docs: not required — confirmed by
     <author>") and stop. Later passes see this and skip silently.
   - If **yes** → continue to **Creating the ticket**.

   Never decide "yes" on the developer's behalf. The whole point of the gate is
   that a human confirms customer impact.

## Reconcile an existing ticket

Run this when step 2 found an existing `DOC-ready:` ticket — either via a
passed-in key or via a `DOC-ready:` link discovered on the engineering ticket
(there is no Jira search tool). The goal is to keep the one ticket current,
never to file a second one.

1. **Fetch it** with `getJiraIssue` (description + labels + links).
2. **Rebuild the description** from the current workflow context using the same
   template and authoring rules as a fresh create (see *Creating the ticket*) —
   in the finalize pass this means describing **as-built** behavior and filling
   the now-known `Pull request / repo link`, resolving open questions that the
   implementation has answered.
3. **Compare** the rebuilt description to the existing one:
   - **Materially stale** (behavior, customer impact, PR link, or previously
     open questions have changed) → `editJiraIssue` to update the description.
     Preserve the `ready-for-docs` and `AI_generated` labels and the existing
     link to the engineering ticket. Do not change the summary unless the
     customer-facing feature name itself changed.
   - **Already current** → make no edit; just confirm the link.
   Never fabricate to fill a gap — unsourced fields stay as open questions under
   *Internal notes*, exactly as on create.
4. **Report back** the ticket key, its URL, whether you updated or left it
   unchanged, and any remaining open questions.

## Creating the ticket

1. **Load the config** from `policy/doc-task.yaml` (project key, issue type,
   link type, default component/assignee). If the project key is still the
   unset placeholder, STOP and tell the developer the doc-task project must be
   configured first — do not guess a project.

2. **Load the template** from `references/doc-task-template.md` and build the
   description using **exactly** that structure and authoring rules. The rules
   are load-bearing — especially:
   - Plain English, active voice.
   - **Do not invent** UI text, behavior, steps, defaults, limits, permissions,
     supported environments, or unsupported scenarios.
   - Any field you cannot source → leave the placeholder and add a matching line
     under **Internal notes** as an open question. Never fabricate.

3. **Source the fields** from the workflow context:
   - `Related engineering ticket` → the MOB ticket driving the work.
   - `Engineering SME` → assignee of that ticket.
   - `Pull request / repo link` → the PR the workflow just opened
     (`gh pr view --json url`). On an **early draft** there is no PR yet — record
     `pending` and add a matching open question under *Internal notes*; the
     finalize reconcile pass fills it in.
   - `Design or spec` / `Confluence` → from the SDD design doc or linked spec, if any.
   - On an **early draft**, describe the **intended** behavior from the specs and
     design — not as-built — and lean on *Internal notes* open questions for
     anything the implementation hasn't settled yet.

4. **Create the issue** via `createJiraIssue`:
   - **Summary:** `DOC-ready: <customer-facing feature name>`
   - **Labels:** include **both** `ready-for-docs` **and** `AI_generated` under
     `additional_fields.labels` — e.g.
     `additional_fields: { "labels": ["ready-for-docs", "AI_generated"] }`.
     `createJiraIssue` has no top-level `labels` param; labels passed anywhere
     else are silently dropped and never land on the ticket. The rule-2
     `inject-ai-generated-label` hook *blocks* the call and forces a retry if
     `AI_generated` is missing — so add it up front rather than relying on
     auto-injection.
   - **Project / issue type:** from `policy/doc-task.yaml`.
   - **Description:** the filled template from step 2.

5. **Link it** to the engineering ticket via `createIssueLink` using the link
   type in `policy/doc-task.yaml` (default: `relates to`).

6. **Report back** the new doc-task key, its URL, and a one-line list of any
   fields left as open questions so the developer/docs team knows what's
   missing.

## Output

On create (new ticket — early draft or finalize):

```
Doc task filed: <DOC-KEY> — DOC-ready: <feature> [draft from specs | as-built]
  Linked to: <MOB-KEY> (<link type>)
  Open questions for docs (<n>): <comma-separated field names, or "none">
```

On reconcile (ticket already existed):

```
Doc task [updated | unchanged — already current]: <DOC-KEY> — DOC-ready: <feature>
  Linked to: <MOB-KEY> (<link type>)
  Open questions for docs (<n>): <comma-separated field names, or "none">
```

If the gate answer was "no":

```
Doc task: not required — confirmed by <author> for <MOB-KEY>.
```

## Notes

- This skill **creates or updates a planning ticket only**. It does not write
  docs, edit Confluence, or modify the engineering ticket beyond the link.
- It is **idempotent** — safe to run more than once. The prior-decision check
  (gate step 2) routes repeat runs to reconcile instead of double-filing, and
  asks the human docs question only once.
- Spec-driven pipelines may call it **early** (draft from specs, to guide
  development) and **at finalize** (reconcile to as-built). Simpler workflows can
  call it once at finalize. Either way, honor the gate: a "no" is a valid,
  complete outcome.

## Related

- `references/doc-task-template.md` — the exact ticket structure and rules.
- `policy/doc-task.yaml` — deployment-specific JIRA project/issue-type config.
- STANDARDS.md rule #4 — the rule this skill enforces.
