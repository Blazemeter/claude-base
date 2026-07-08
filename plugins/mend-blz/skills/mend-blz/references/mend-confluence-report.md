# Mend Confluence unfixed-vulnerabilities report

Mechanics for step 7 of the `mend-blz` fix loop: upsert one row per **currently unfixable**
library into the shared tracking table on Confluence. One page, shared across every
component/run. This is a **manager-facing quick view** — deliberately narrow: only libraries that
genuinely can't be fixed right now, one row each, kept current rather than accumulated.

## What belongs on this page (and what doesn't)

- **Include:** a breaking-major-version fix required, no fix version available upstream at all, or
  the ecosystem is out-of-recipe for `dep-remediation` (ecosystem the skill can't handle at all).
- **Exclude — `pending Mend rescan`:** already fixed on the branch/master, just waiting for Mend's
  next scan to reflect it. Not a real open problem; listing it would be noise on a page meant for a
  quick read.
- **Exclude — out-of-scope severity:** an alert simply not attempted this run because it's outside
  the requested severity scope (e.g. a low/medium alert on a high/critical-only run). That's "not
  attempted," not "can't be fixed" — don't report it here.
- **Primary library only, never the transitive one.** Report the library that actually governs the
  fix per the golden rule (the direct/managed dependency you'd bump in the manifest/BOM) — not some
  inner transitive jar nested inside it that isn't independently actionable. If Mend's alert names a
  transitive artifact, resolve it up to the direct/managed dependency that pulls it in before writing
  the row.

## Page

- **URL:** https://perforce.atlassian.net/wiki/spaces/BLZRD/pages/3332964371/Mend+vuls
- **Page ID:** `3332964371` — config as `confluence.page_id` in `config/jira.json` (blz-claude-orchestrator); treat it as config the caller may override, same as the Jira ids.
- **Base URL:** same Atlassian site as Jira — the `base_url` field of the same jira config blob the **jira** skill already uses for ticket creation (`https://perforce.atlassian.net`), referred to below as `${JIRA_BASE_URL}`. Standalone run without that config → ask the user, same as any other missing config value.

## Auth

Same credentials as the **jira** skill — `JIRA_EMAIL` + `JIRA_API_TOKEN`, HTTP Basic Auth. Confluence
Cloud's REST API v2 accepts the same site-level API token as Jira; no separate credential.

## Read-modify-write (Confluence v2 pages require the FULL body on update, not a diff)

### 1. GET the current page

```bash
curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_BASE_URL}/wiki/api/v2/pages/3332964371?body-format=storage"
```

Response shape (fields needed below):
```json
{
  "id": "3332964371",
  "status": "current",
  "title": "Mend vuls",
  "spaceId": "...",
  "version": { "number": 7 },
  "body": { "storage": { "value": "<existing storage-format HTML>", "representation": "storage" } }
}
```

Capture `title`, `spaceId`, `version.number`, and `body.storage.value` — all four are required for
the PUT below.

### 2. Upsert rows in the existing table

The page body is Confluence **storage format** (XHTML). Table schema:

```html
<table>
  <thead>
    <tr>
      <th>Repository</th><th>Library</th><th>Current version</th><th>Fixed version</th>
      <th>Severity</th><th>Vulnerability</th><th>Reason</th><th>Date</th>
    </tr>
  </thead>
  <tbody>
    <!-- one <tr> per currently-unfixable library -->
  </tbody>
</table>
```

If this is the first-ever write (no table present), append this table at the end of
`body.storage.value`.

**Upsert, don't blindly append. Never write the same (Repository, Library, CVE) twice.** Match
each library from this run's triage against existing `<tr>` rows by **(Repository, Library)**:

- **Match found** → update that row **in place**: union this run's CVEs into its existing
  `Vulnerability` cell (add any newly-seen CVE for this library; a CVE that recurs unfixed is
  simply already there — don't duplicate it), and refresh `Fixed version`, `Severity`, `Reason`,
  and `Date` from this run's data — `Severity` is always overwritten with the current Mend value,
  even if an operator had hand-filled it earlier. Leave every other existing row untouched.
- **No match** → append a new `<tr>`.
- **The rule this exists for:** if a run finds the same library still can't be fixed, that is a
  match — update the existing row's `Date`, do **not** add a second row for it. A brand-new CVE
  against a library that's already on the page also does **not** get its own row — it's added to
  that library's existing `Vulnerability` cell instead.
- A library that's since cleared (fixed, or no longer flagged by Mend) is **not** removed
  automatically by this step — see [Gotchas](#gotchas) on manual cleanup.

This keeps the page at one row per problem library instead of growing a duplicate per run — the
point is a manager can scan it and see current state, not a run-by-run log (the per-run PR/summary
table already serves that audit purpose elsewhere).

| Column | Source |
|--------|--------|
| Repository | target `repo` (short name, e.g. `a.blazemeter.com`) |
| Library | the **primary/direct** library per the golden rule (see above) — not a transitive one |
| Current version | `library.version` — the vulnerable version found |
| Fixed version | `fixResolutionText` / `topFix` — the version Mend says resolves it (if any; blank when no fix version exists upstream) |
| Severity | `cvss3_severity` if present, else `severity` (see the **mend** skill) — uppercase, e.g. `HIGH`. Always set/overwritten from this run's data, on both a new row and an upsert to an existing one — including replacing an operator's hand-filled value, since Mend's own severity is the source of truth once the automated run has it. |
| Vulnerability | the CVE id, as a link: `<a href="https://nvd.nist.gov/vuln/detail/<CVE-ID>"><CVE-ID></a>`. Multiple CVEs against the same library → comma-separate links in **one** cell — union new CVEs into the existing cell on an upsert, never a separate row per CVE. A library alert with no assigned CVE → literal text `no CVE assigned` (no link). |
| Reason | why it can't be fixed — breaking major version required, or no fix version available upstream, or out-of-recipe ecosystem. One line, specific (e.g. "Jackson 3.x required, breaking major incompatible with Spring Boot 3.5 BOM"). |
| Date | today's date, `YYYY-MM-DD` — the date **last confirmed still unfixed**, not first-seen |

### 3. PUT the updated page

```bash
curl -s -X PUT -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JIRA_BASE_URL}/wiki/api/v2/pages/3332964371" \
  -d '{
    "id": "3332964371",
    "status": "current",
    "title": "'"${PAGE_TITLE}"'",
    "spaceId": "'"${SPACE_ID}"'",
    "body": { "representation": "storage", "value": "'"${NEW_BODY_ESCAPED}"'" },
    "version": { "number": '"${NEW_VERSION}"', "message": "mend-blz: upsert unfixed-library report" }
  }'
```

`version.number` **must** be exactly `old_version + 1` — Confluence rejects any other value (a stale
or skipped version number means someone/something else edited the page since the GET; re-fetch and
retry once before giving up).

## When to run this step

- Runs right after the Jenkins gate (step 6), **before** opening the PR or creating the Jira
  ticket — not at the end. Reason: the Jira ticket's description links back to this page when
  there are unfixable libraries, so the page must already reflect this run's rows by the time that
  ticket is created.
- Runs for every `mend-blz` invocation that reached step 1's triage, whether the run finished
  cleanly, stopped on a red Jenkins build, or found nothing in scope — as long as there is at
  least one library from this run that qualifies (see "What belongs on this page"). Nothing
  qualifying → skip silently, no write at all.
- Skipped entirely if the `noconfluence` flag is set — in which case the Jira ticket's description
  also omits the Confluence link.

## Gotchas

- **Full-body PUT, not a patch.** Omitting `body`/`title`/`spaceId` on the PUT clears or 404s the
  page — always carry forward the values read in step 1 for anything you aren't intentionally
  changing.
- **Version conflicts.** If the PUT 409s on version mismatch, re-GET and reapply your new rows to
  the latest body before retrying — don't just bump the version number blindly.
- **Escaping.** The body value is a JSON string containing HTML — escape quotes/newlines correctly:
  actually build the JSON payload with a real JSON encoder (e.g. Python's `json.dumps`), don't hand-quote it in bash.
- **Manual cleanup, for now.** This step does not delete rows for libraries that have since been
  fixed — the page owner removes those by hand. Don't add auto-removal logic without confirming
  the "now fixed" signal is reliable (a cleared Mend alert can also mean "pending rescan," not
  "actually fixed") — that's exactly why this note exists.
- **Migrating an older page.** A page still on the previous 6-column schema (`Repository |
  Vulnerability | Version | Fix version needed | Reason | Date of run`, one row per run) needs a
  one-time manual restructure to the 8-column schema above — that's a one-off cleanup, not
  something this step does automatically.
