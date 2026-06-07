---
name: ui-run-checks
description: Run the reporting-ui "before pushing" gate (lint, prettier-check, license-check, Jest) before a push or PR, scoped to the packages the branch actually changed. Use when the user says "verify before push", "is this ready to push", "run the pre-push checks", "did I break anything", or right before opening a PR in the reporting-ui monorepo. Do NOT use for running a single arbitrary test the user named (just run it), for Cypress/E2E (that runs in CI, not locally here), or in repos that are not the Perfecto reporting-ui monorepo.
allowed-tools: Read Grep Glob Bash(git diff*) Bash(npm run lint) Bash(npm run prettier-check) Bash(npm run jest*) Bash(npm test*)
---

# ui-run-checks

Reproduce the reporting-ui repo's "before pushing" gate locally and report a clear pass/fail,
so the user knows a branch will survive CI before they push or open a PR. All commands run from
the `ui/` directory.

## When to use

- "Verify before I push", "is this ready", "run the pre-push checks", "will CI pass".
- Immediately before the `ui-open-pr` skill opens a pull request (that skill calls this one first).

## When NOT to use

- The user asked to run one specific test — just run `npm run jest -- <pattern>`, don't run the
  whole gate.
- Cypress / Selenium E2E — those run on Jenkins, not in this local gate. Don't attempt them.
- Any repo that isn't the reporting-ui monorepo (no `view-*` workspaces / `betterScripts`).

## Preconditions

- Current working directory is the repo's `ui/` folder (where `package.json` with the `lint`,
  `prettier-check`, `jest`, and `test` scripts lives). If `npm run` can't find those scripts,
  tell the user to `cd ui/` and stop.
- Dependencies installed (`npm i --legacy-peer-deps`). If a run fails because modules are
  missing, say so — do not auto-install unless the user asks.

## Workflow

1. **Find the changed surface.** Determine the merge base against `master` and list changed files:

   ```bash
   git diff --name-only master...HEAD   # what this branch changed vs master
   git status --porcelain               # also catch staged + unstaged + untracked work
   ```

   Map each path to its workspace by its top-level directory: `view-<x>/`, `reporting-<x>/`,
   `src/`, `tests/`. Note whether the change is localized to one or two workspaces or is broad
   (root config, `reporting-commons-ui`, lockfile → treat as broad).

2. **Lint and format (always full-repo — these are fast and repo-wide configured):**

   ```bash
   npm run lint
   npm run prettier-check
   ```

3. **Unit tests.**
   - Localized change → narrow Jest to the touched workspaces:
     `npm run jest -- <path-or-name-pattern>` (e.g. `npm run jest -- view-lab`).
   - Broad change, or you can't confidently scope it → run the full gate:
     `npm test` (this is Jest **plus** the license check — the canonical "before pushing" command).
   - If you ran a narrowed Jest, still run the license check via the full `npm test` once at the
     end, OR call out that the license check was skipped.

4. **Stop on first hard failure.** If a step exits non-zero, capture the relevant tail of its
   output, report it, and stop — don't run the remaining steps. The user fixes, then re-runs.

5. **Report** in the format below.

## Output format

```
## UI checks — <branch>

Changed: <N files across: view-lab, reporting-commons-ui> (scope: localized | broad)

| Check          | Command                          | Result |
|----------------|----------------------------------|--------|
| Lint           | npm run lint                     | ✅/❌  |
| Prettier       | npm run prettier-check           | ✅/❌  |
| Unit (Jest)    | npm run jest -- <pattern> / npm test | ✅/❌ |
| License check  | (part of npm test)               | ✅/❌/skipped |

<On failure: the failing command + the meaningful tail of its output.>

Verdict: READY TO PUSH | NOT READY — fix <check> first
```

## Notes

- `npm test` = Jest + license check (`betterScripts` `test`). `npm run jest` is Jest only.
- Prefer the narrowed Jest for fast feedback, but the full `npm test` is the authoritative gate.
- Don't run `npm run lint:fix` or `npm run prettier` (write mode) unless the user asks — this
  skill verifies, it doesn't mutate.

## Related

- [[ui-open-pr]] — runs this skill first, then fills the PR template and opens the PR.
- `docs/testing.md` and `package.json` `scripts` in the repo are the source of truth for these
  commands.
