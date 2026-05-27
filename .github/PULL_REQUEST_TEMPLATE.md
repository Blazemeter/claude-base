## What changed

<!-- One paragraph: what this PR adds / changes / fixes. Link any issue. -->

## Type

- [ ] New skill / command / sub-agent / hook
- [ ] Update to existing skill / command / sub-agent / hook
- [ ] Validator / policy / CI change
- [ ] Docs only
- [ ] Other (describe)

## Pre-merge checklist

- [ ] `python scripts/validate.py --strict` passes locally
- [ ] `python -m unittest discover -s scripts/tests -t scripts` passes locally
- [ ] If hook scripts changed: `shellcheck` / `ruff check` pass locally
- [ ] If `policy/allowed-tools.yaml` changed: the PR description explains *why* the new entry is needed and the narrowest scope used
- [ ] If a new skill: `description` clearly states *when* Claude should trigger it (positive AND negative cases)
- [ ] No secrets in the diff (CI gitleaks will block anyway, but check first)
- [ ] **Linked-repo awareness**: I understand this repo is mirrored to its sibling (`PerfectoMobileDev/claude-base` ↔ `Blazemeter/claude-base`) and that merging here will propagate to the other via `sync-to-sibling.yml`. The `Verify sibling sync` check is green on this PR. See [`LINKED_REPOS.md`](../LINKED_REPOS.md).
- [ ] **If this PR edits `LINKED_REPOS.md` or any workflow under `.github/workflows/sync-to-sibling.yml` / `verify-sibling-sync.yml`**: a matching PR has been opened on the sibling repo and linked in the description above.

## Notes for the reviewer

<!-- Anything non-obvious: trade-offs considered, alternatives rejected, follow-ups. -->
