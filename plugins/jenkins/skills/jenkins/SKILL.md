---
name: jenkins
description: Trigger and gate on a Blazemeter blazect Jenkins multibranch build — POST buildWithParameters with PUSH_TO_GCR=true and PERFORM_WHITESOURCE_SCAN=true, track the queue item to the specific triggered build number and poll that (not lastBuild, which races with the branch's own auto-triggered build) until green (unit-test/prisms/mend stages), fix-forward on red, and never gate on the slow API_TESTS-CI suite. Load when a flow needs to run or wait on a Blazemeter CI build.
---

# Blazemeter CI gate

Server: `https://blazect-jenkins.blazemeter.com`. Auth with `JENKINS_USER` + `JENKINS_API_TOKEN`.
Each component has a **multibranch** folder (e.g. `BACKEND-CI`, `DAGGER-CI`, `SEARCH-CI`); a branch
build lives at `/job/<folder>/job/<branch>/`.

## Trigger with PUSH_TO_GCR + PERFORM_WHITESOURCE_SCAN

After pushing the branch, kick a parameterized build so the remediated image publishes to GCR
(`gcr.io/verdant-bulwark-278`; image libs `bm-backend`, `bm-dagger`, …) and the build re-scans the
branch with Mend/WhiteSource (so fixed alerts show as resolved on the next **mend** triage instead
of lingering as stale/open):

```
POST https://blazect-jenkins.blazemeter.com/job/<folder>/job/<branch>/buildWithParameters?PUSH_TO_GCR=true&PERFORM_WHITESOURCE_SCAN=true
```

- **`PUSH_TO_GCR`** (boolean, default `False`) is the **"push to GCR" checkbox** — always check it, on **every** component's job (BACKEND-CI, DAGGER-CI, SEARCH-CI, and any repo added later).
- **`PERFORM_WHITESOURCE_SCAN`** (boolean, default `False`) triggers the Mend/WhiteSource scan stage — always check it too, same components, so the branch's Mend project reflects the fix.
- Leave the other boolean params (`RUN_UNIT_TESTS`, other `PERFORM_*_SCAN` flags, `FAIL_JOB_ON_SCAN_FAILURES`, `NO_CACHE_FLAG`, `UPDATE_VERSION`) at their defaults.
- **Expect a second build to already be running or queued.** Pushing the branch itself
  auto-triggers a build via Jenkins' own branch-indexing/webhook (default params, no
  `PUSH_TO_GCR`/`PERFORM_WHITESOURCE_SCAN`) — that's normal multibranch-pipeline behavior, not a
  bug in this flow. This `buildWithParameters` call is a **second, explicit** build; gate on that
  one (see below), not the auto-triggered one.

## Gate on green

The `buildWithParameters` POST's response `Location` header points at a **queue item**, not a
build directly — poll that queue item until it resolves to an `executable` with a build number,
then poll `…/job/<folder>/job/<branch>/<that number>/` until it finishes. **Don't poll `lastBuild`
blindly** — with the auto-triggered build from above also in flight, `lastBuild` can point at the
wrong one depending on which finishes first. A build runs **unit-test · prisms · mend** stages.

- **Never gate on `API_TESTS-CI`** — that shared suite is >1h, flaky/not-green, and run manually at developer discretion.
- **If RED:** **fix forward** on the same branch and re-push (re-triggers the build); reverting/deferring a breaking dependency counts as fixing forward. **Cap at 3 fix attempts per run** (local-test + Jenkins failures combined). Still red after the 3rd → **stop** (no PR, no Jira) and record the reason. A run that goes green after deferring some breaking deps still proceeds with the fixes that passed.
- **If GREEN:** continue downstream (PR, ticket).
