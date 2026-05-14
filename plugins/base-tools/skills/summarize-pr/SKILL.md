---
name: summarize-pr
description: Summarize a GitHub pull request — purpose, key changes, review state, CI status, and outstanding blockers. Use when the user pastes a PR URL (github.com/<org>/<repo>/pull/<n>), references a PR by number (e.g. "PR #123", "summarize PR 42"), or asks "what's in PR X" / "is PR X ready to merge". Do NOT use for reviewing a local git diff (use a code-review skill instead), for investigating CI failures in detail (use a CI-investigation skill), or for any non-GitHub VCS (GitLab, Bitbucket).
allowed-tools: Bash(gh *), Read
---

# summarize-pr

Produce a concise, structured summary of a GitHub pull request. The goal is to let the user decide *what to do about the PR* without opening the browser — purpose, scope, review state, blockers, recommendation.

## When to use

- User pastes a PR URL like `https://github.com/<org>/<repo>/pull/123`.
- User refers to a PR by number — "summarize PR 123", "what's in 123", "is 123 ready".
- User asks for the *state* of a PR they own or are reviewing.

## When NOT to use

- Reviewing a local diff or working tree — use a code-review skill.
- Deep CI failure investigation — use a CI-investigation skill.
- Non-GitHub PRs (GitLab merge requests, Bitbucket PRs).

## Preconditions

- `gh` CLI installed and authenticated. If `gh auth status` fails, tell the user to run `gh auth login` and stop.
- For private repos, the user's `gh` token must have repo access.

## Workflow

1. **Resolve the PR identifier.**
   - Full URL → parse `<org>/<repo>` and number from `/<org>/<repo>/pull/<n>`.
   - Bare `#<n>` or `PR <n>` → run `gh repo view --json nameWithOwner -q .nameWithOwner` to get current repo. If the user is not in a git repo, ask which repo they mean.

2. **Fetch metadata in one call.**

   ```bash
   gh pr view <n> --repo <org>/<repo> --json \
     number,title,author,state,isDraft,mergeable,reviewDecision,additions,deletions,changedFiles,body,reviews,statusCheckRollup,comments,headRefName,baseRefName
   ```

3. **Fetch the diff, bounded.**

   ```bash
   gh pr diff <n> --repo <org>/<repo> | head -500
   ```

   If `changedFiles` > 30 or `additions + deletions` > 1500, skip the full diff — list filenames instead and call out the size.

4. **Identify blockers.**
   - `reviewDecision == "CHANGES_REQUESTED"` → list each "REQUEST_CHANGES" review with its body.
   - Any `statusCheckRollup` entry with `conclusion != "SUCCESS"` and not in `["SKIPPED", "NEUTRAL"]` → name the check.
   - Unresolved review threads → count them.
   - `mergeable == "CONFLICTING"` → flag the merge conflict.

5. **Produce the summary** in the exact format below.

## Output format

```
## PR #<num> — <title>

- **Author:** @<author> · **State:** <state><draft-tag> · **Branch:** `<head>` → `<base>`
- **Size:** +<additions>/-<deletions> across <N> files
- **Review:** <reviewDecision> · <N approvals> · <N changes requested> · <N unresolved threads>
- **CI:** <N passing> · <N failing> · <N pending>

## Purpose
<One paragraph from PR body, or "(empty)" if no description>

## Key changes
- <Bullet per meaningful change. Group small file edits. Reference exact file paths.>

## Outstanding concerns
<Numbered list of blockers. If none, write "None — this PR has no blocking issues.">

## Recommendation
<One of: "Ready to merge", "Needs <comma-separated blockers>", "Discussion needed", "Draft — not yet ready for review">
```

## Notes

- Don't paste the full `gh pr view` JSON output to the user — extract the fields and present the summary above.
- Stick to verifiable facts from the API. Do not speculate about whether changes are "good" or "bad" — that's a code review, not a summary.
- If the PR has > 30 files, mention the top 5 files by lines changed; don't enumerate all.
- Truncate any single field longer than ~300 chars in the output, with `…`.

## Related

- A code-review skill (different scope) — focuses on correctness of the diff, not the PR state.
- A CI-investigation skill — drills into a specific failing check.
