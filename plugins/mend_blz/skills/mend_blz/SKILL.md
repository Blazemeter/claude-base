---
name: mend_blz
description: Use this skill for any work involving Mend (formerly WhiteSource) on Blazemeter components — fetching vulnerability alerts, looking up project tokens, interpreting CVE severity, and running the fix → PR → Jira → Jenkins loop for a.blazemeter and dagger. Load when the user mentions Mend, WhiteSource, CVEs in a Blazemeter service, or vulnerability remediation.
---

# When to use

Load this skill when the user:

- Asks about Mend vulnerabilities for a Blazemeter component (a.blazemeter, dagger)
- Wants to look up the Mend project token for a Blazemeter repo
- Asks about CVE severity classification (HIGH/CRITICAL vs MEDIUM/LOW)
- Mentions "WhiteSource" (legacy name for Mend)

End-to-end loop: **Mend alerts → dependency fix on a fresh date-stamped branch → Jenkins green → PR → Jira (MOB).**

# Invocation (arguments)

The skill is **argument-driven** — read what the user asks for; don't assume:

- **Component** (required): match the name the user gives against `services.json` (key or `repo`). E.g. "a.blazemeter.com" / "a.blazemeter" → the `a.blazemeter` entry; "dagger" → `dagger`. No match → list the registry keys and ask.
- **Severity scope** (optional): the level(s) the user names — `critical`, `high`, `medium`, `low`, or combinations ("high/critical", "all"). Act **only** on those (compare case-insensitively). **Default = HIGH + CRITICAL** when the user doesn't specify.

> Example: *"fix mend for a.blazemeter.com for critical level"* → component `a.blazemeter`, severity scope = **CRITICAL only**.

**Two ways to run:**
- **On-demand** — user names a component (+ optional severity), as above.
- **Scheduled (full sweep)** — an external scheduler invokes `mend scheduled`; the skill runs the fix loop for **every component in `services.json`**, at **all severities (CRITICAL + HIGH + MEDIUM + LOW)**, producing **one branch / PR / Jira per repository** (all severities batched). Cadence (daily / weekly / off) is just how often the scheduler fires — see "Scheduling".

# Credentials

All three required from environment or `~/.claude/team-config.md`:

- `MEND_URL` — `https://saas-eu.whitesourcesoftware.com`
- `MEND_USER_KEY` — per-user key (issued to `TCohen@perforce.com`; the value is a secret, the email only identifies the owner)
- `MEND_ORG_TOKEN` — the Blazemeter org token. It is exported under **both** names — `Blazemeter` and `Blazemeter_GHC` (the GitHub-Cloud-integration name) — with the **same value**, because different tools/code paths read different variable names. There is **no org selection or fallback logic** — authenticate and match the project.

**Never echo these values** to logs, Slack, PRs, Jira, or other channels. Validate presence at the start of any Mend operation and abort with an actionable error if any is missing.

# Component registry

Components are **data-driven** from [`references/services.json`](references/services.json) — a registry keyed by component alias, each entry carrying `repo` / `mend_project` / `owner` / `jenkins_folder` / `integration_branch` / `stack` / `description`. **To onboard a new repo, add an entry — no skill edits needed.**

```json
"a.blazemeter": {
  "repo": "Blazemeter/a.blazemeter.com",
  "mend_project": "BZA-Backend",
  "owner": "<assignee full name>",
  "jenkins_folder": "BACKEND-CI",
  "integration_branch": "develop",
  "stack": "php-composer",
  "description": "a.blazemeter primary backend (PHP)"
}
```

| Field | Meaning |
|-------|---------|
| `repo` | `org/name` under github.com (Blazemeter) — the PR target |
| `mend_project` | exact Mend project name (Mend names drift from repo names — e.g. `a.blazemeter.com` → `BZA-Backend`). Match this against `projectVitals[].name` to get the project token. |
| `owner` | **per-repo owner — a human display name** (text), set by the team. Resolved to a Jira accountId and set as the **Jira assignee**. Not used for GitHub. Empty → falls back to `tcohen`. |
| `jenkins_folder` | **multibranch** folder on `https://blazect-jenkins.blazemeter.com`. A branch build lives at `/job/<jenkins_folder>/job/<branch>/` |
| `integration_branch` | the branch the fix branches off and PRs back into (`develop`/`master`) |
| `stack` | drives the fix recipe — and implies the manifest file (`php-composer`→`composer.json`, `gradle-springboot`→`build.gradle.kts`, `maven-springboot`→`pom.xml`) |
| `description` | human label |

## Fix recipe by `stack`

> **Golden rule — fix the DIRECT dependency, never the transitive.** If a vulnerable library **Y** is pulled in by a direct dependency **X**, bump **X** so it resolves a fixed **Y**. Do **not** pin/override the transitive **Y** directly. For BOM-managed transitives (Spring Framework, micrometer, logback, jackson under Spring Boot), that means **bump the Spring Boot BOM version** (`spring-boot.version`) — the one dep that brings them all — *not* individual `<spring-framework.version>`/`<micrometer.version>`/etc. overrides. If no direct-dep / BOM bump resolves the alert, **defer and note it** — never pin the transitive.

- **`php-composer`** (a.blazemeter) — bump the **direct `require`** in `composer.json` (incl. the direct dep that pulls a vulnerable transitive, e.g. bump `guzzle` to pull a fixed `psr7`) → `composer update <vendor/pkg> --with-dependencies` → commit `composer.lock`.
  - **Cross-check the fix version** with `composer audit` — Mend's suggested version may itself be under a Packagist advisory (e.g. aws/aws-sdk-php 3.368.0 was); escalate to the latest non-advisory version.
  - **Local compile + unit test (pre-push):** `make phpstan` (static check) + `make test-docker-cov` (the dockerized unit suite CI runs — needs Docker). Green here ⇒ very likely green on `BACKEND-CI`.
  - **Internal forks** resolve from `github.com/Blazemeter` git `repositories` (`mongator`, `mondator`, `php-resque-ex`, `php-resque-ex-scheduler`, `PHP-Multivariate-Regression`, `Restler`, `mandrill-api-php`), not Packagist. A CVE in one of these is fixed **upstream in that repo + a ref bump**, not via a registry version.
- **`gradle-springboot`** (dagger) — transitive brought by the Spring Boot BOM → **bump the Spring Boot version** (the BOM that brings it), not the individual transitive; a genuinely direct dep → bump its literal version in `build.gradle.kts`. Verify deps with `./gradlew dependencies`.
  - **Local compile + unit test (pre-push):** `./gradlew test` (compiles + runs the unit suite).
- **`maven-springboot`** (search) — transitive brought by the Spring Boot BOM → **bump `<spring-boot.version>`** in `pom.xml` (the BOM), *not* individual `<spring-framework.version>`/`<micrometer.version>`/etc.; a genuinely direct dep → bump its `<version>`. Verify deps with `mvn -q dependency:tree`.
  - **Local compile + unit test (pre-push):** `mvn -q -B verify` (compiles + runs the unit suite).
  - **Maven repo note:** Blazemeter builds don't use `aws-nexus` (that's an unrelated machine-global mirror); its image registry is **GCR `gcr.io/verdant-bulwark-278`**. Let the repo's own build config resolve dependencies — don't inject a Nexus.

## Notes

- Each component's Jenkins build runs **unit-test · prisms · mend** stages. The shared `API_TESTS-CI` suite is >1h, flaky/not-green, and run manually at developer discretion — **never gate the fix loop on it.**
- **`PUSH_TO_GCR`** (boolean job parameter, default `False`) is the **"push to GCR" checkbox** — the fix loop triggers **every component's** build with it **checked** so the remediated image publishes to **GCR `gcr.io/verdant-bulwark-278`** (image libs: `bm-backend`, `bm-dagger`, …). Other boolean params (`RUN_UNIT_TESTS`, `PERFORM_*_SCAN`, `FAIL_JOB_ON_SCAN_FAILURES`, `NO_CACHE_FLAG`, `UPDATE_VERSION`) stay at their defaults.
- Code Insight (`codeinsight-project.yml`, Revenera) is separate license scanning — not the Mend CVE flow.

# Scheduling

A **scheduled run is a full sweep**: iterate **every component in `services.json`** and run the full fix loop for each at **all severities — CRITICAL, HIGH, MEDIUM, and LOW**. **One branch / one PR / one Jira ticket per repository** — every in-scope fix for that repo (all severities) is **batched into that single branch/PR** (never split per severity or per alert). The sweep ends with one combined summary table covering all repositories.

Cadence is a **global** choice — **`daily`** · **`weekly`** · **`off`** — meaning simply *how often the sweep fires*. It is **not** per-component and lives in the external scheduler, not in `services.json`.

**The skill does not fire itself** — wire the timed trigger externally to invoke `mend scheduled` on the chosen cadence:
- **Claude Code routine** — `/schedule` a daily or weekly cron agent that runs `mend scheduled`.
- **GitHub Actions** — a workflow with `on: schedule:` cron (`0 6 * * *` daily / `0 6 * * 1` weekly) invoking the bot/CLI.
- **Jenkins** — a periodic timer-triggered job.

`off` = no scheduler configured (on-demand only).

# Quick reference (Mend REST v1.3)

| Task | Endpoint | Key params |
|------|----------|------------|
| Find a project's token | `requestType: getOrganizationProjectVitals` | match `projectVitals[].name` against the registry's `mend_project` |
| Fetch alerts | `requestType: getProjectAlertsByType` | `userKey` + `projectToken` + `alertType: SECURITY_VULNERABILITY` |
| Severity scope | — | Driven by the invocation args (e.g. "critical level" → CRITICAL only); **default HIGH+CRITICAL**. **Compare case-insensitively** — Mend returns severities lowercase (`"high"`, `"critical"`, `"medium"`, `"low"`). Levels outside the requested scope are deferred. |

> `getOrganizationProjectVitals` needs an **org-admin** user key. The fetch itself (`getProjectAlertsByType`) only needs `userKey` + `projectToken`, so once a project token is known it works for any member.

## Project name matching (in order)

1. Exact match of the registry `mend_project` against `projectVitals[].name`.
2. Case-insensitive / substring fallback either direction.
3. No match → abort, list the first 10 available project names so the user can spot a naming mismatch.

## Test mode

The `test` flag skips the API entirely and reads pre-seeded JSON from `/tmp/mend-<component>-vulns.json` (same shape as the `getProjectAlertsByType` response). Missing file in test mode → abort with a clear error pointing at the expected path.

# Fix loop

Order: **alerts → branch → fix → local compile+unit-test → push → Jenkins green (GATE) → PR → Jira → tag PR with MOB id.** Tests run locally before push (fail fast); Jenkins-green is the hard gate — nothing downstream runs until the branch build is green.

1. **Fetch Mend alerts → triage to the requested severity scope** (from the invocation args; default HIGH+CRITICAL; case-insensitive). Resolve the project token first.
   - **Triage by the alert set, not by what's already in flight** — if an in-scope alert already appears in another open PR, **still fix it in this run** (don't skip it).
   - **Only alerts in the component's `stack` ecosystem are fixed.** Alerts in a different ecosystem/manifest (e.g. Python `requirements.txt` or npm `package.json` under `tools/` in a PHP repo) are **deferred and listed in the summary**, not fixed here.
2. **Create a unique, date-stamped branch — one per run** — named `mend-fix-<YYYYMMDD-HHMMSS>` (e.g. `mend-fix-$(date +%Y%m%d-%H%M%S)`) off `integration_branch`. **No component in the name** — component names like `a.blazemeter.com` contain dots (not Docker-tag-safe); each component is its own repo, so the timestamp alone is unique. A fresh branch every run (referred to as `<branch>` below); never reuse a prior run's branch. Optionally close any prior **open** `mend-fix-*` PR in the repo with a "superseded by newer mend run" comment.
3. **Apply the fix** for **every in-scope alert**, batched into the one branch, per the component's `stack` (see "Fix recipe by `stack`"). **If a dependency's fix needs a breaking/major upgrade that fails the build** (within the attempt cap below), **revert just that dependency**, keep the other fixes, and record the deferred one in the summary **Notes** (e.g. "symfony/yaml 3.4 → major upgrade required, deferred") — one breaking dep must not fail the whole batch.
4. **Compile + run unit tests locally** (per `stack`: `./gradlew test` for dagger; `mvn -q -B verify` for search; `make phpstan` + `make test-docker-cov` for a.blazemeter). **Only push if green.** If local tests fail, fix forward locally first — don't burn a Jenkins cycle. If the local env can't run them (e.g. Docker unavailable), say so in the summary and rely on the Jenkins gate.
5. **Commit** (keep the `Co-Authored-By` trailer) → **push** `<branch>` to `github.com/<repo>`.
6. **Trigger the branch build with `PUSH_TO_GCR=true`, then poll until green.** After the push, kick a parameterized build so the remediated image publishes to GCR (`gcr.io/verdant-bulwark-278`):
   `POST https://blazect-jenkins.blazemeter.com/job/<jenkins_folder>/job/<branch>/buildWithParameters?PUSH_TO_GCR=true`
   (the job's **"push to GCR" checkbox** — `PUSH_TO_GCR`, default `False`; check it. Leave the other params at their defaults.) Then poll `…/job/<jenkins_folder>/job/<branch>/lastBuild/` for the build (unit-test · prisms · mend stages). Never gate on `API_TESTS-CI`. **Do this for every component's job** (BACKEND-CI, DAGGER-CI, SEARCH-CI, and any repo added later).
   - **If RED:** try to **fix forward** on the same branch and re-push (re-triggers the build) — reverting/deferring a breaking dependency (step 3) counts as fixing forward. **Cap at 3 fix attempts per run** (local-test + Jenkins failures combined). If the build still can't go green after the 3rd attempt, **stop** — do **not** open a PR or Jira — and record the reason in the summary **Notes**. (A run that goes green after deferring some breaking deps still proceeds to PR with the fixes that passed.)
   - **If GREEN:** continue.
7. **Open the PR** from `<branch>` into `integration_branch`. (No GitHub reviewer is set — ownership is tracked via the Jira assignee.)
8. **Create the MOB Jira ticket** (project **MOB**, board 5348), unless `nojira`:
   - Fields: type **Task**, **Product = Blazemeter** (`customfield_10350`), **Scrum Team = Terra** (`customfield_10067`), **assignee = the repo `owner`** (resolve the display name → accountId via `/rest/api/3/user/search?query=<owner>`; if `owner` is empty, fall back to `tcohen`), **active sprint** of board 5348 (`customfield_10020`), and **transition status to `In Review`**.
   - **Summary:** `<component> Fix Mend vulnerabilities`.
   - **Description**, in this order: (1) dependencies fixed — one line each `library: <from> → <to>` + severity/CVE; (2) **PR link** (the real, open PR); (3) **Jenkins build link** — directly **under the PR link**.
9. **Tag the PR**: prepend the **`MOB-####` id** to the PR title (HEAD), e.g. `MOB-51396: mend: …`.
10. **Write a summary table** when the run finishes — one row per alert acted on:

    | Repository | Alert (CVE / library) | Fix (from → to) | Succeeded | Notes |
    |------------|-----------------------|-----------------|-----------|-------|
    | `<repo>` | CVE-… / `lib` | `x → y` | ✅ / ❌ | *(only if needed)* |

    "Succeeded" = the fix landed and the Jenkins build went green. **Leave Notes empty when it succeeded** — fill Notes only on ❌ or when deferred (failing stage/test + root cause, hit the 3-attempt cap, breaking/major upgrade required, or the Mend fix version was itself under advisory). Below the table, also list: alerts **deferred as out-of-recipe ecosystem** (e.g. Python/JS tooling deps), alerts **outside the requested severity scope**, and any `pending Mend rescan` items.

# Command flags

| Flag | Effect |
|------|--------|
| *(none)* | Full loop: alerts → fresh date-stamped branch `mend-fix-<YYYYMMDD-HHMMSS>` → fix/push → **Jenkins green (gate)** → PR → Jira (In Review) → tag PR with MOB id. Red build → fix-forward up to **3 attempts**; if still red, stop + Notes (no PR, no Jira). |
| `test` | Skip Mend API; read pre-seeded JSON from `/tmp/mend-<component>-vulns.json` |
| `nojenkins` | Skip the Jenkins-green gate — open the PR/Jira without waiting for the branch build |
| `nojira` | Skip Jira create/update |

# Gotchas

- **Project naming drift.** Mend project names sometimes diverge from the Blazemeter repo name. The substring fallback covers most cases; be ready to ask the user for the right project token if matching fails.
- **API version `v1.3`.** A newer GraphQL API exists, but `v1.3` REST is what the credentials are wired for. Do not migrate without re-validating creds.
- **Empty `alerts[]` does NOT mean clean.** Can also mean the project hasn't been scanned recently. Check `projectVitals[].lastUpdated`; warn if older than 7 days.
- **No on-demand rescan in v1.3.** A re-query right after a fix shows the *last* scan, not local edits. Absent alerts → likely cleared at the resolved-tree layer; still-present → label `pending Mend rescan`, not `failed fix`. Final confirmation comes from the component's Jenkins **mend** stage.
- **Dual-name org token.** `Blazemeter` and `Blazemeter_GHC` are the same value under two names — never branch logic on which org.

# References

- [services.json](references/services.json) — the component registry (add an entry to onboard a repo).
- [API reference](references/api.md) — endpoint specs, request/response shapes, examples.
