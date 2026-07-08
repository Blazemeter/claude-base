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
| Trigger the branch build with `PUSH_TO_GCR=true` and gate on green | **jenkins** |
| Dated branch, commit/push, open PR, tag PR with the ticket id | **github** |
| Create the MOB ticket (In Review, assignee = owner) — this skill supplies the [MOB config](#mob-jira-config) | **jira** |
| Report unfixed alerts to the Confluence tracking page | this skill (see [references/mend-confluence-report.md](references/mend-confluence-report.md)) |

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

# MOB Jira config

The **jira** skill is generic — it knows Jira Cloud REST mechanics only, not this project's
specifics. This recipe is what supplies the concrete config for step 8, per its
[caller config contract](../../../jira/skills/jira/SKILL.md#caller-config-contract):

| Field | Value |
|-------|-------|
| `base_url` | `https://perforce.atlassian.net` |
| `project_key` | `MOB` |
| `board_id` | `5348` |
| `issue_type_id` | `10013` (Task) |
| `custom_fields` | Product=Blazemeter — `customfield_10350` (id `21409`); Scrum Team=Terra — `customfield_10067` (id `21406`) |
| `sprint_field` | `customfield_10020` — active sprint of board `5348` |
| `assignee` | the target's `owner` (component registry); fallback `tcohen` when empty — ownership is tracked via assignee since there's no GitHub reviewer |
| `target_status` / `transition_id` | `In Review` / `61` |
| `summary` | `Fix Mend vulnerabilities <repository name>` (the repo's short name, e.g. `Fix Mend vulnerabilities a.blazemeter.com` — not the component alias) |
| `description_lines` | one line per dependency fixed (`library: <from> → <to>` + severity/CVE), then the PR link, then the Jenkins build link directly under it |
| `skip` | the `nojira` flag |

Treat the ids above as config this recipe owns — not as defaults baked into **jira** itself.

# Fix loop

Order: **alerts → branch → fix → local compile+unit-test → push → Jenkins green (GATE) → PR → Jira → tag PR with MOB id → Confluence report.** Local tests run before push (fail fast); Jenkins-green is the hard gate — nothing downstream runs until the branch build is green. The Confluence report step runs regardless of how the run ends (including a red-build stop) — it is the record of what's still outstanding.

1. **Fetch alerts → triage to the requested scope** (default HIGH+CRITICAL, case-insensitive) — via **mend**. Resolve the project token first. Triage by the alert set, not by what's in flight (fix an in-scope alert even if it's in another open PR). Only fix alerts in the component's `stack` ecosystem; defer the rest to the summary.
2. **Create the dated branch** `mend-fix-<YYYYMMDD-HHMMSS>` off `integration_branch` — via **github**.
3. **Apply the fix** for every in-scope alert, batched into the branch, per the `stack` — via **dep-remediation** (golden rule, advisory cross-check, defer breaking majors to Notes).
4. **Compile + run unit tests locally** per stack — via **dep-remediation**. Only push if green.
5. **Commit + push** the branch — via **github**.
6. **Trigger the build with `PUSH_TO_GCR=true` and poll until green** — via **jenkins**. Red → fix-forward, cap **3 attempts**; still red → stop (no PR/Jira) + Notes.
7. **Open the PR** into `integration_branch` — via **github**.
8. **Create the MOB ticket** (In Review, assignee = owner) unless `nojira` — via **jira**, using
   the [MOB Jira config](#mob-jira-config) above.
9. **Tag the PR** title with the `MOB-####` id — via **github**.
10. **Write the summary table** — one row per alert acted on:

    | Repository | Alert (CVE / library) | Fix (from → to) | Succeeded | Notes |
    |------------|-----------------------|-----------------|-----------|-------|
    | `<repo>` | CVE-… / `lib` | `x → y` | ✅ / ❌ | *(only if needed)* |

    "Succeeded" = fix landed **and** Jenkins went green. **Leave Notes empty on success** — fill only on ❌/deferred (failing stage + root cause, hit the 3-attempt cap, breaking major required, or the Mend fix version was itself under advisory). Below the table, also list: alerts deferred as out-of-recipe ecosystem, alerts outside the requested scope, and any `pending Mend rescan` items.
11. **Report unfixed alerts to Confluence** — every alert from step 1's triage that did **not**
    end up ✅ in the step-10 table (deferred, failed the build/Jenkins gate, out-of-recipe
    ecosystem, out-of-scope, or `pending Mend rescan`) gets one row appended to the tracking table
    on the [Mend vulns](https://perforce.atlassian.net/wiki/spaces/BLZRD/pages/3332964371/Mend+vuls)
    Confluence page. **Never remove or overwrite existing rows** — this table accumulates across
    runs. See [references/mend-confluence-report.md](references/mend-confluence-report.md) for the
    exact API calls and row format. Do this even when the run stopped early (e.g. Jenkins never
    went green) — it's the audit trail of what's still outstanding, so it runs whether or not step
    10 does.

# Command flags

| Flag | Effect |
|------|--------|
| *(none)* | Full loop as above (Jenkins gate → PR → Jira → tag). Red build → fix-forward up to 3; still red → stop + Notes. |
| `test` | Skip the Mend API; read pre-seeded JSON from `/tmp/mend-<component>-vulns.json` (see **mend**). |
| `nojenkins` | Skip the Jenkins-green gate — open the PR/Jira without waiting for the build. |
| `nojira` | Skip Jira create/update. |
| `noconfluence` | Skip the step-11 Confluence report. |

# References

- Component registry (authoritative): `config/services.json` in **blz-claude-orchestrator**.
- Composed skills: **mend**, **dep-remediation**, **jenkins**, **github**, **jira** (generic —
  see [MOB Jira config](#mob-jira-config) above for the concrete values this recipe supplies).
- Confluence report mechanics: [references/mend-confluence-report.md](references/mend-confluence-report.md).
