---
name: mend_blz
description: End-to-end Mend vulnerability remediation for Blazemeter components (a.blazemeter, dagger, search). Composes the mend, dep-remediation, jenkins, github, and jira skills into one loop — Mend alerts → dependency fix on a fresh date-stamped branch → Jenkins green → PR → Jira (MOB). Load when the user wants to fix/remediate Mend/WhiteSource vulnerabilities for a Blazemeter service.
---

# When to use

Load this recipe to run the **full Mend remediation loop** for a Blazemeter component. It is the
composer — the reusable knowledge lives in five skills it drives:

| Step | Skill |
|------|-------|
| Fetch/triage Mend alerts, resolve project token, severity | **mend** |
| Apply the fix (golden rule, advisory cross-check, defer majors, per-stack recipe, local build+test) | **dep-remediation** |
| Trigger the branch build with `PUSH_TO_GCR=true` and gate on green | **jenkins** |
| Dated branch, commit/push, open PR, tag PR with the ticket id | **github** |
| Create the MOB ticket (In Review, assignee = owner) | **jira** |

These auto-load alongside this recipe; defer to them for the "how," and follow the order/gates below.

# Invocation (arguments)

Argument-driven — read what the user asks; don't assume:

- **Component** (required): match the name against `services.json` (key or `repo`). "a.blazemeter.com"/"a.blazemeter" → `a.blazemeter`; "dagger" → `dagger`. No match → list the registry keys and ask.
- **Severity scope** (optional): the level(s) named — `critical`/`high`/`medium`/`low` or combos ("high/critical", "all"). Act **only** on those (case-insensitive). **Default = HIGH + CRITICAL.**

> Example: *"fix mend for a.blazemeter.com for critical level"* → component `a.blazemeter`, scope = CRITICAL only.

# Component registry

Data-driven from [`references/services.json`](references/services.json) — keyed by component alias,
each entry carrying `repo` / `mend_project` / `owner` / `jenkins_folder` / `integration_branch` /
`stack` / `description`. **To onboard a repo, add an entry — no skill edits.**

| Field | Meaning |
|-------|---------|
| `repo` | `org/name` under github.com (Blazemeter) — the PR target |
| `mend_project` | exact Mend project name (drifts from repo name; match against `projectVitals[].name`) — see the **mend** skill |
| `owner` | per-repo owner display name → resolved to the **Jira assignee** (empty → `tcohen`) — see the **jira** skill |
| `jenkins_folder` | multibranch folder on blazect Jenkins — see the **jenkins** skill |
| `integration_branch` | branch the fix branches off / PRs into (`develop`/`master`) |
| `stack` | drives the fix recipe + manifest (`php-composer`→`composer.json`, `gradle-springboot`→`build.gradle.kts`, `maven-springboot`→`pom.xml`) — see **dep-remediation** |
| `description` | human label |

# Fix loop

Order: **alerts → branch → fix → local compile+unit-test → push → Jenkins green (GATE) → PR → Jira → tag PR with MOB id.** Local tests run before push (fail fast); Jenkins-green is the hard gate — nothing downstream runs until the branch build is green.

1. **Fetch alerts → triage to the requested scope** (default HIGH+CRITICAL, case-insensitive) — via **mend**. Resolve the project token first. Triage by the alert set, not by what's in flight (fix an in-scope alert even if it's in another open PR). Only fix alerts in the component's `stack` ecosystem; defer the rest to the summary.
2. **Create the dated branch** `mend-fix-<YYYYMMDD-HHMMSS>` off `integration_branch` — via **github**.
3. **Apply the fix** for every in-scope alert, batched into the branch, per the `stack` — via **dep-remediation** (golden rule, advisory cross-check, defer breaking majors to Notes).
4. **Compile + run unit tests locally** per stack — via **dep-remediation**. Only push if green.
5. **Commit + push** the branch — via **github**.
6. **Trigger the build with `PUSH_TO_GCR=true` and poll until green** — via **jenkins**. Red → fix-forward, cap **3 attempts**; still red → stop (no PR/Jira) + Notes.
7. **Open the PR** into `integration_branch` — via **github**.
8. **Create the MOB ticket** (In Review, assignee = owner) unless `nojira` — via **jira**.
9. **Tag the PR** title with the `MOB-####` id — via **github**.
10. **Write the summary table** — one row per alert acted on:

    | Repository | Alert (CVE / library) | Fix (from → to) | Succeeded | Notes |
    |------------|-----------------------|-----------------|-----------|-------|
    | `<repo>` | CVE-… / `lib` | `x → y` | ✅ / ❌ | *(only if needed)* |

    "Succeeded" = fix landed **and** Jenkins went green. **Leave Notes empty on success** — fill only on ❌/deferred (failing stage + root cause, hit the 3-attempt cap, breaking major required, or the Mend fix version was itself under advisory). Below the table, also list: alerts deferred as out-of-recipe ecosystem, alerts outside the requested scope, and any `pending Mend rescan` items.

# Command flags

| Flag | Effect |
|------|--------|
| *(none)* | Full loop as above (Jenkins gate → PR → Jira → tag). Red build → fix-forward up to 3; still red → stop + Notes. |
| `test` | Skip the Mend API; read pre-seeded JSON from `/tmp/mend-<component>-vulns.json` (see **mend**). |
| `nojenkins` | Skip the Jenkins-green gate — open the PR/Jira without waiting for the build. |
| `nojira` | Skip Jira create/update. |

# References

- [services.json](references/services.json) — the component registry (add an entry to onboard a repo).
- Composed skills: **mend**, **dep-remediation**, **jenkins**, **github**, **jira**.
