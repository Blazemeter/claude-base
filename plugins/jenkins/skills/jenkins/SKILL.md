---
name: jenkins
description: Trigger and gate on a Blazemeter blazect Jenkins multibranch build — POST buildWithParameters with PUSH_TO_GCR=true, poll the branch's lastBuild until green (unit-test/prisms/mend stages), fix-forward on red, and never gate on the slow API_TESTS-CI suite. Load when a flow needs to run or wait on a Blazemeter CI build.
---

# Blazemeter CI gate

Server: `https://blazect-jenkins.blazemeter.com`. Auth with `JENKINS_USER` + `JENKINS_API_TOKEN`.
Each component has a **multibranch** folder (e.g. `BACKEND-CI`, `DAGGER-CI`, `SEARCH-CI`); a branch
build lives at `/job/<folder>/job/<branch>/`.

## Trigger with PUSH_TO_GCR

After pushing the branch, kick a parameterized build so the remediated image publishes to GCR
(`gcr.io/verdant-bulwark-278`; image libs `bm-backend`, `bm-dagger`, …):

```
POST https://blazect-jenkins.blazemeter.com/job/<folder>/job/<branch>/buildWithParameters?PUSH_TO_GCR=true
```

- **`PUSH_TO_GCR`** (boolean, default `False`) is the **"push to GCR" checkbox** — always check it, on **every** component's job (BACKEND-CI, DAGGER-CI, SEARCH-CI, and any repo added later).
- Leave the other boolean params (`RUN_UNIT_TESTS`, `PERFORM_*_SCAN`, `FAIL_JOB_ON_SCAN_FAILURES`, `NO_CACHE_FLAG`, `UPDATE_VERSION`) at their defaults.

## Gate on green

Poll `…/job/<folder>/job/<branch>/lastBuild/` until the build finishes. A build runs
**unit-test · prisms · mend** stages.

- **Never gate on `API_TESTS-CI`** — that shared suite is >1h, flaky/not-green, and run manually at developer discretion.
- **If RED:** **fix forward** on the same branch and re-push (re-triggers the build); reverting/deferring a breaking dependency counts as fixing forward. **Cap at 3 fix attempts per run** (local-test + Jenkins failures combined). Still red after the 3rd → **stop** (no PR, no Jira) and record the reason. A run that goes green after deferring some breaking deps still proceeds with the fixes that passed.
- **If GREEN:** continue downstream (PR, ticket).
