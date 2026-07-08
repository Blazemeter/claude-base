---
name: jira
description: Create and transition a Jira ticket for any calling flow — the project, board, issue type, custom fields, assignee-resolution rule, target status, and summary/description are all caller-supplied config, not baked into this skill. This skill only knows the generic Jira Cloud REST mechanics. Load when a flow needs to file or update a Jira ticket and can supply that config (see the **mend-blz** skill for a concrete example — it supplies the Blazemeter MOB config).
---

# Create/transition a Jira ticket

Generic mechanics only. Every project-specific value lives in **caller-supplied config** — this
skill doesn't know or assume a project key, board, issue type, or field ids. See the **mend-blz**
skill for a concrete example (it drives this skill with a MOB-specific config block).

Auth = `JIRA_EMAIL` + `JIRA_API_TOKEN`, HTTP Basic Auth against the caller's `base_url`
(e.g. `https://perforce.atlassian.net`).

## Caller config contract

| Field | Meaning |
|-------|---------|
| `base_url` | the Atlassian site, e.g. `https://perforce.atlassian.net` |
| `project_key` | e.g. `MOB` |
| `board_id` | board to resolve the active sprint from, if `sprint_field` is set |
| `issue_type_id` | numeric issue type id (e.g. Task) |
| `custom_fields` | map of `customfield_XXXX` → value/id to set on create |
| `sprint_field` | customfield id for Sprint; when set, resolve and use board `board_id`'s active sprint |
| `assignee` | display name to resolve to accountId via `/rest/api/3/user/search?query=<name>`; caller supplies the fallback to use when empty |
| `target_status` | status name the ticket should land in after create |
| `transition_id` | numeric transition id for `target_status` (transition ids are per-project workflow — the caller looks this up or hardcodes a known value) |
| `summary` | the fully-built summary string |
| `description_lines` | ordered list of lines/blocks to compose into the description |
| `skip` | when true, skip create/update entirely (the caller's own opt-out flag, e.g. `nojira`) |

## Create

1. If `skip` is set, stop — no ticket is created.
2. If `sprint_field` is set, resolve the active sprint of `board_id` and include it in
   `custom_fields` under that field id.
3. Resolve `assignee`: look up the display name via `/rest/api/3/user/search?query=<assignee>`; if
   `assignee` is empty, use the caller's fallback instead.
4. `POST /rest/api/3/issue` with `project_key`, `issue_type_id`, `summary`, the composed
   description (see below), the resolved assignee accountId, and all `custom_fields`.

## Description

Compose the description from `description_lines`, in the order given — don't reorder or drop
lines. Callers typically order this as: work-specific detail first, then a link to the PR (if
any), then a link to the CI build (if any) directly under the PR link.

## Transition

After create, if `target_status` is set: call the transitions endpoint for the new issue and
apply `transition_id`. If the caller didn't already confirm `transition_id` is valid for this
workflow, fetch available transitions first and match by `target_status` name rather than
trusting a stale id blindly.
