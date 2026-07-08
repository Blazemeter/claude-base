---
name: mend-blz
description: End-to-end Mend vulnerability remediation for Blazemeter components (a.blazemeter, dagger, search). Composes the mend, dep-remediation, jenkins, github, and jira skills into one loop — Mend alerts → dependency fix on a fresh date-stamped branch → Jenkins green → PR → Jira (MOB) → Confluence report of unfixed alerts. Load when the user wants to fix/remediate Mend/WhiteSource vulnerabilities for a Blazemeter service.
---

# When to use

Load this recipe to run the **full Mend remediation loop** for a Blazemeter component. It is the
composer — the reusable knowledge lives in five skills it drives:

| Step | Skill |
|------|-------|
| Fetch/triage Mend alerts, resolve project token, severity | **mend** |
| Apply the fix (golden rule, advisory cross-check, defer majors, per-stack recipe, local build+test) | **dep-remediation** |
| Trigger the branch build with `PUSH_TO_GCR=true` + `PERFORM_WHITESOURCE_SCAN=true` and gate on green | **jenkins** |
| Dated branch, commit/push, open PR, tag PR with the ticket id | **github** |
| Upsert currently-unfixable libraries to the Confluence tracking page | this skill (see [references/mend-confluence-report.md](references/mend-confluence-report.md)) |
| Create the MOB ticket (In Review, assignee = owner) — this skill supplies the ticket summary and, if there were deferred alerts, links back to the Confluence page above | **jira** |

These auto-load alongside this recipe; defer to them for the "how," and follow the order/gates below.

# Invocation (arguments)

Argument-driven — read what the user asks; don't assume:

- **Component** (required): match the name against the component registry (see [Component registry](#component-registry)) by key or `repo`. "a.blazemeter.com"/"a.blazemeter" → `a.blazemeter`; "dagger" → `dagger`. No match → list the registry keys and ask.
- **Severity scope** (optional): the level(s) named — `critical`/`high`/`medium`/`low` or combos ("high/critical", "all"). Act **only** on those (case-insensitive). **Default = HIGH + CRITICAL.**

> Example: *"fix mend for a.blazemeter.com for critical level"* → component `a.blazemeter`, scope = CRITICAL only.

# Component registry

The registry is **not bundled with this skill** — its single source of truth is
`config/services.json` in the **blz-claude-orchestrator** repo (onboard a repo by adding an entry
there). On an orchestrated run the orchestrator passes the resolved target entry into the prompt —
**use that, verbatim.** For a standalone/interactive run (this skill alone, without the
orchestrator), there is no local registry file to read — **ask the user for** (or copy from the
orchestrator's `config/services.json`) a per-component entry with these fields:

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

Order: **alerts → branch → fix → local compile+unit-test → push → Jenkins green (GATE) → Confluence report → PR → Jira → tag PR with MOB id.** Local tests run before push (fail fast); Jenkins-green is the hard gate — nothing downstream runs until the branch build is green. The Confluence report runs right after the gate and **before** PR/Jira, and regardless of how the run ends (including a red-build stop) — it only needs step 1's triage + the fix/build outcome, not a PR or ticket, and its page needs to already reflect this run by the time the Jira ticket (which may link to it) is created.

1. **Fetch alerts → triage to the requested scope** (default HIGH+CRITICAL, case-insensitive) — via **mend**. Resolve the project token first. Triage by the alert set, not by what's in flight (fix an in-scope alert even if it's in another open PR). Only fix alerts in the component's `stack` ecosystem; defer the rest to the summary.
2. **Create the dated branch** `mend-fix-<YYYYMMDD-HHMMSS>` off `integration_branch` — via **github**.
3. **Apply the fix** for every in-scope alert, batched into the branch, per the `stack` — via **dep-remediation** (golden rule, advisory cross-check, defer breaking majors to Notes).
4. **Compile + run unit tests locally** per stack — via **dep-remediation**. Only push if green.
5. **Commit + push** the branch — via **github**.
6. **Trigger the build with `PUSH_TO_GCR=true` + `PERFORM_WHITESOURCE_SCAN=true` and poll until
   green** — via **jenkins**. Red → fix-forward, cap **3 attempts**; still red → stop (no PR/Jira,
   but still do step 7) + Notes. Expect **two builds** after the push: the branch's own
   auto-trigger (webhook/branch-indexing, default params) plus this explicit parameterized one —
   gate on the **explicit** one, not the auto-triggered one.
7. **Upsert currently-unfixable libraries to Confluence** — a manager-facing quick view, not a
   run log: only libraries genuinely un-fixable right now (breaking major required, no fix version
   upstream, or out-of-recipe ecosystem) get a row on the
   [Mend vulns](https://perforce.atlassian.net/wiki/spaces/BLZRD/pages/3332964371/Mend+vuls)
   Confluence page — **excluding** `pending Mend rescan` (already fixed, just waiting on Mend) and
   out-of-scope-severity (not attempted, not "can't fix") alerts. One row per (repo, library) —
   never write the same library+CVE twice: a repeat sighting of an already-listed CVE updates that
   row's Date in place, and a new CVE against an already-listed library is added into that same
   row rather than getting its own. Report the **primary/direct** library per the golden rule,
   never a transitive one. See
   [references/mend-confluence-report.md](references/mend-confluence-report.md) for the exact API
   calls, upsert matching, and column schema. Runs even when step 6 stopped early on a red build.
   Skip silently if nothing from this run qualifies.
8. **Open the PR** into `integration_branch` — via **github**.
9. **Create the MOB ticket** (In Review, assignee = owner) unless `nojira` — via **jira**, passing
   the summary `Fix Mend vulnerabilities <repository name>` (jira owns project/board/fields/
   status; this recipe only supplies the ticket's name and description content). If step 7
   reported any deferred/unfixed alerts, the description also links to the Confluence page (see
   the **jira** skill's description ordering) — omit that line if step 7 had nothing to report or
   was skipped via `noconfluence`.
10. **Tag the PR** title with the `MOB-####` id — via **github**.
11. **Write the summary table** — one row per alert acted on:

    | Repository | Alert (CVE / library) | Fix (from → to) | Succeeded | Notes |
    |------------|-----------------------|-----------------|-----------|-------|
    | `<repo>` | CVE-… / `lib` | `x → y` | ✅ / ❌ | *(only if needed)* |

    "Succeeded" = fix landed **and** Jenkins went green. **Leave Notes empty on success** — fill only on ❌/deferred (failing stage + root cause, hit the 3-attempt cap, breaking major required, or the Mend fix version was itself under advisory). Below the table, also list: alerts deferred as out-of-recipe ecosystem, alerts outside the requested scope, and any `pending Mend rescan` items.

# Command flags

| Flag | Effect |
|------|--------|
| *(none)* | Full loop as above (Jenkins gate → Confluence → PR → Jira → tag). Red build → fix-forward up to 3; still red → stop + Notes. |
| `test` | Skip the Mend API; read pre-seeded JSON from `/tmp/mend-<component>-vulns.json` (see **mend**). |
| `nojenkins` | Skip the Jenkins-green gate — open the PR/Jira without waiting for the build. |
| `nojira` | Skip Jira create/update. |
| `noconfluence` | Skip the step-7 Confluence report (and the Jira description's link to it). |

# References

- Component registry (authoritative): `config/services.json` in **blz-claude-orchestrator**.
- Composed skills: **mend**, **dep-remediation**, **jenkins**, **github**, **jira** (this recipe
  supplies the ticket summary/name; jira owns project MOB/board/fields/status).
- Confluence report mechanics: [references/mend-confluence-report.md](references/mend-confluence-report.md).
