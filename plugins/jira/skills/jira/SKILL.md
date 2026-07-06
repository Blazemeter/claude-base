---
name: jira
description: Create and transition Blazemeter MOB Jira tickets — project MOB / board 5348, type Task, custom fields (Product=Blazemeter, Scrum Team=Terra, active sprint), assignee resolved from the repo owner display name, status transitioned to In Review, with a structured description linking the PR and Jenkins build. Load when a flow needs to file or update a MOB ticket.
---

# Create the MOB ticket

Project **MOB**, board **5348**. Auth = `JIRA_EMAIL` + `JIRA_API_TOKEN` (Perforce Atlassian).
Ids below are the known MOB values — treat them as config the caller may override.

- **Type:** Task (`10013`)
- **Product = Blazemeter** — `customfield_10350` (id `21409`)
- **Scrum Team = Terra** — `customfield_10067` (id `21406`)
- **Sprint = active sprint** of board 5348 — `customfield_10020`
- **Assignee = the repo `owner`** — resolve the display name → accountId via `/rest/api/3/user/search?query=<owner>`; if `owner` is empty, fall back to `tcohen`. (Assignee is how ownership is tracked — there's no GitHub reviewer.)
- **Status → `In Review`** — transition id `61`.

## Summary & description

- **Summary:** `<component> Fix Mend vulnerabilities`.
- **Description**, in this order:
  1. Dependencies fixed — one line each `library: <from> → <to>` + severity/CVE.
  2. **PR link** (the real, open PR).
  3. **Jenkins build link** — directly under the PR link.

A `nojira` flag skips ticket create/update entirely.
