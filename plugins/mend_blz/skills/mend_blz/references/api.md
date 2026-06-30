# Mend API reference (Blazemeter)

The Mend (formerly WhiteSource) REST API (v1.3) used by the `mend_blz` skill.

## Base URL & auth

- **Base URL:** `${MEND_URL}/api/v1.3` → `https://saas-eu.whitesourcesoftware.com/api/v1.3`.
- **Auth:** all calls are POSTs with a JSON body. Every request body MUST include `userKey` and `orgToken`:
  ```json
  { "requestType": "...", "userKey": "${MEND_USER_KEY}", "orgToken": "${MEND_ORG_TOKEN}", ... }
  ```
- `MEND_ORG_TOKEN` is the Blazemeter org token, exported under both names `Blazemeter` and `Blazemeter_GHC` (same value — see SKILL.md "Credentials"). No org selection logic.
- All three credentials come from environment / `~/.claude/team-config.md`. **Never echo them.**

## Endpoints used

### 1. `getOrganizationProjectVitals` — find the project token

```bash
curl -s -X POST "${MEND_URL}/api/v1.3" \
  -H "Content-Type: application/json" \
  -d '{
    "requestType": "getOrganizationProjectVitals",
    "userKey":  "'"${MEND_USER_KEY}"'",
    "orgToken": "'"${MEND_ORG_TOKEN}"'"
  }'
```

Response shape:
```json
{ "projectVitals": [ { "name": "a.blazemeter.com", "token": "abc123...", "lastUpdated": "..." }, ... ] }
```

**Matching logic (in order):**
1. Exact case-insensitive name match against the component/repo name.
2. Substring match either direction (`repo in name` OR `name in repo`).
3. If still no match — abort and list the first 10 project names so the user can spot a naming mismatch.

### 2. `getProjectAlertsByType` — fetch vulnerability alerts

```bash
curl -s -X POST "${MEND_URL}/api/v1.3" \
  -H "Content-Type: application/json" \
  -d '{
    "requestType":  "getProjectAlertsByType",
    "userKey":      "'"${MEND_USER_KEY}"'",
    "projectToken": "'"${PROJECT_TOKEN}"'",
    "alertType":    "SECURITY_VULNERABILITY"
  }'
```

Response shape (truncated — real field names as returned by saas-eu):
```json
{
  "alerts": [
    {
      "type":      "SECURITY_VULNERABILITY",
      "status":    "OPEN",
      "date":      "2026-02-12",
      "directDependency": true,
      "vulnerability": {
        "name":          "CVE-2026-2391",
        "severity":      "low",
        "score":         3.7,
        "cvss3_severity": "medium",
        "cvss3_score":   5.3,
        "topFix":        { "...": "fix object" },
        "allFixes":      [ "..." ],
        "fixResolutionText": "Upgrade to qs 6.10.6"
      },
      "library": {
        "name":       "qs",
        "artifactId": "qs-6.10.5.tgz",
        "groupId":    "qs",
        "version":    "6.10.5",
        "type":       "javascript/Node.js"
      }
    }
  ]
}
```

## Field notes (verified against the live API)

- **Severity is lowercase** (`"low"`, `"medium"`, `"high"`, `"critical"`). **Always compare case-insensitively** — a case-sensitive `== "HIGH"` silently misses real alerts. There are two severities: legacy `severity` and `cvss3_severity`/`cvss3_score` (prefer cvss3 when present).
- **Fix info** is `fixResolutionText` (human string), plus `topFix` / `allFixes` (structured). There is **no** `fixResolution` field.
- **Library identity:** use `library.name` + `library.version`. `artifactId` may carry a filename (e.g. `qs-6.10.5.tgz`) and `groupId` is only meaningful for Maven; non-Maven ecosystems set `groupId == name`.
- Useful extras: `status` (filter to `OPEN`), `directDependency` (direct vs transitive), `date`/`modifiedDate`, `alertUuid`.

## Severity filtering

The skill only acts on `HIGH` and `CRITICAL` by default (case-insensitive). `MEDIUM` / `LOW` are deferred — they appear in the Not-fixed table only if the user explicitly asked to include them.

## Test mode

When the `test` flag is set, **skip all API calls** and read pre-seeded JSON from `/tmp/mend-<component>-vulns.json` (same shape as the `getProjectAlertsByType` response). If the file is missing, abort with a clear error pointing at the expected path.

## Internal Blazemeter dependencies (NOT a Mend endpoint)

Blazemeter has **no single groupId/package convention**, and internal libraries are pulled differently per component:

- **a.blazemeter (PHP/Composer):** internal forks (`mongator`, `mondator`, `php-resque-ex`, `php-resque-ex-scheduler`, `PHP-Multivariate-Regression`, `Restler`, `mandrill-api-php`) are declared as git `repositories` in `composer.json` and resolve straight from `github.com/Blazemeter`. A CVE in one of these is fixed **upstream in that repo + a ref bump**, not via a Packagist version.
- **dagger (Gradle/Spring Boot):** versions are largely managed by the Spring Boot BOM (`io.spring.dependency-management`). Override a BOM-managed version via the Spring Boot version property; bump directly-pinned libraries inline in `build.gradle.kts`.

## Same-cycle re-query caveat

There is no Mend REST v1.3 endpoint for "rescan now". A `getProjectAlertsByType` call right after a fix shows what Mend **last** scanned (the previous nightly run or the previous Jenkins build's mend-stage upload). It does NOT reflect just-made local edits.

When using a same-cycle re-query as a verification step:

- Alerts that are absent → likely cleared at the resolved-tree layer (the upgraded library replaced a transitive). Reliable signal.
- Alerts that are still present → most likely "Mend hasn't rescanned yet." Label them `pending Mend rescan`, NOT `failed fix`.
- Final Mend-side confirmation comes after the PR's Jenkins build runs the **mend** stage upload.

## Gotchas

- **Project naming drift.** Mend project names sometimes diverge from the Blazemeter repo name. The substring fallback covers most cases, but be ready to ask the user for the right project token if matching fails.
- **API version 1.3** — there is a newer GraphQL API, but the v1.3 REST endpoints are what the cred set is wired into. Don't migrate without checking that the credentials still work.
- **Empty `alerts` array does NOT mean clean.** It can mean the project hasn't been scanned recently. Always check `lastUpdated` on the project vitals — if older than 7 days, surface it as a warning.
