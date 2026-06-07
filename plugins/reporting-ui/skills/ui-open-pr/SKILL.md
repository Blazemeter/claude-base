---
name: ui-open-pr
description: Open a GitHub pull request for the reporting-ui monorepo the repo's way — enforce the `<first-name>/<short-description>/MOB-<ticket>` branch convention, run the pre-push gate first, and fill out every section of the repo's pull_request_template.md. Use when the user says "open a PR", "create the pull request", "raise a PR for this", or "submit this for review" in the reporting-ui repo. Do NOT use to summarize or review an existing PR (use a summarize/review skill), to merge a PR, or in repos without `.github/pull_request_template.md`.
allowed-tools: Read Grep Glob Bash(git *) Bash(gh *) Bash(npm run lint) Bash(npm run prettier-check) Bash(npm run jest*) Bash(npm test*)
---

# ui-open-pr

Open a pull request against `master` for the Perfecto reporting-ui monorepo, following the
repo's branch-naming and PR-template conventions, and only after the pre-push gate is green.

## When to use

- "Open a PR", "create the pull request", "raise a PR", "submit this for review".

## When NOT to use

- Summarizing or reviewing an existing PR — that's a different skill.
- Merging / closing a PR.
- A repo with no `.github/pull_request_template.md` (this skill is reporting-ui specific).

## Preconditions

- `gh auth status` succeeds. If not, tell the user to run `gh auth login` and stop.
- There are commits on the current branch ahead of `master` (`git log master..HEAD`). If the
  working tree has uncommitted changes, tell the user to commit them first — this skill does
  **not** commit on the user's behalf.

## Workflow

1. **Check the branch name.** `git rev-parse --abbrev-ref HEAD`.
   - Must match the repo convention `<first-name>/<short-description>/MOB-<number>` (or a bot
     branch like `claude/<source>/<slug>/MOB-<number>`) and not be `master`.
   - If it doesn't match (or is `master`), ask the user for the MOB ticket and a short slug,
     show the branch name you'd use (`<first-name>/<slug>/MOB-<n>`), and only create/rename it
     after they confirm. Never rename or branch silently.

2. **Run the gate.** Invoke the [[ui-run-checks]] workflow (lint, prettier-check, Jest,
   license check). If it fails, report the failure and **stop** — do not open the PR.

3. **Push the branch** (only if it has an upstream or the user is ready to push):
   `git push -u origin <branch>`.

4. **Read the template.** Read `.github/pull_request_template.md` from the repo root and parse
   its sections (the repo's template has fields like description, Jira link, type of change,
   testing, screenshots — fill each one).

5. **Compose the body.** Fill every template section from the actual diff and commits:
   - Derive the MOB ticket from the branch; the template's H1 links to
     `https://perforce.atlassian.net/browse/MOB-<n>` — fill in the real number.
   - Summarize the change from `git log master..HEAD` and `git diff master...HEAD --stat` into
     the `# Summary` section. Tick `# PR Type` (Bugfix/Feature/Refactoring/Build-CI) from the diff.
   - Title format the repo uses: `MOB-<n>: <Area>, <Description>` (e.g.
     `MOB-49239: UI Redesign - Dropdown/Select Field Component`).
   - Leave checkboxes the user must self-assert (e.g. "I tested manually") unchecked, and note
     them in your summary so the user ticks them.

6. **Create the PR.**

   ```bash
   gh pr create --base master --head <branch> --title "<title>" --body-file <tmp-body>
   ```

   Then print the PR URL.

## Safety gates

- Never commit, force-push, or rename branches without explicit user confirmation.
- Never open the PR if the pre-push gate failed.
- Base branch is always `master`.

## Output format

```
## PR opened — MOB-<n>

- **Branch:** <head> → master
- **Title:** <title>
- **Gate:** ui-run-checks ✅
- **URL:** <pr-url>

Sections you still need to confirm: <list of self-assert checkboxes left unchecked>
```

## Related

- [[ui-run-checks]] — the gate this skill runs before opening the PR.
- The repo's `.github/pull_request_template.md` and the branch convention in `CLAUDE.md`.
