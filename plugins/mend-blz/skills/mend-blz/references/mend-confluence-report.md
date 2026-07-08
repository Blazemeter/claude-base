# Mend Confluence unfixed-vulnerabilities report

Mechanics for step 11 of the `mend-blz` fix loop: append a row per unfixed alert to the shared
tracking table on Confluence. One page, shared across every component/run — an accumulating log,
not a per-run replacement.

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

### 2. Append rows to the existing table

The page body is Confluence **storage format** (XHTML). If the table already exists (every run
after the first), append `<tr>` rows just before its closing `</tbody></table>`. If this is the
first-ever write (no table present), append a new table at the end of `body.storage.value`:

```html
<table>
  <thead>
    <tr>
      <th>Repository</th><th>Vulnerability</th><th>Version</th>
      <th>Fix version needed</th><th>Reason</th><th>Date of run</th>
    </tr>
  </thead>
  <tbody>
    <!-- one <tr> per unfixed alert -->
  </tbody>
</table>
```

One `<tr>` per unfixed alert from step 1's triage:

| Column | Source |
|--------|--------|
| Repository | target `repo` (short name, e.g. `a.blazemeter.com`) |
| Vulnerability | `vulnerability.name` (CVE) + `library.name`, e.g. `CVE-2026-2391 (qs)` |
| Version | `library.version` — the vulnerable version found |
| Fix version needed | `fixResolutionText` / `topFix` — the version Mend says resolves it |
| Reason | why it wasn't fixed — breaking major deferred, Jenkins red after 3 attempts, out-of-recipe ecosystem, out-of-scope severity, `pending Mend rescan`, etc. Same substance as the step-10 Notes column, one line. |
| Date of run | today's date, `YYYY-MM-DD` |

**Never delete or rewrite existing `<tr>` rows** — only add new ones. This page is a running log
across every run and every component.

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
    "version": { "number": '"${NEW_VERSION}"', "message": "mend-blz: append unfixed-alerts report" }
  }'
```

`version.number` **must** be exactly `old_version + 1` — Confluence rejects any other value (a stale
or skipped version number means someone/something else edited the page since the GET; re-fetch and
retry once before giving up).

## When to run this step

- Runs at the **end of every** `mend-blz` invocation that reached step 1's triage, whether the run
  finished cleanly, stopped on a red Jenkins build, or found nothing in scope — as long as there is
  at least one alert to report as unfixed. A "no in-scope alerts at all" run has nothing to append;
  skip silently.
- Skipped entirely if the `noconfluence` flag is set.

## Gotchas

- **Full-body PUT, not a patch.** Omitting `body`/`title`/`spaceId` on the PUT clears or 404s the
  page — always carry forward the values read in step 1 for anything you aren't intentionally
  changing.
- **Version conflicts.** If the PUT 409s on version mismatch, re-GET and reapply your new rows to
  the latest body before retrying — don't just bump the version number blindly.
- **Escaping.** The body value is a JSON string containing HTML — escape quotes/newlines correctly:
  actually build the JSON payload with a real JSON encoder (e.g. Python's `json.dumps`), don't hand-quote it in bash.
