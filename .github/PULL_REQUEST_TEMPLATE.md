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

## Notes for the reviewer

<!-- Anything non-obvious: trade-offs considered, alternatives rejected, follow-ups. -->
