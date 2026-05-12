# Creating a skill

End-to-end lifecycle for adding a skill to a team marketplace.

## 1. Identify

Build a skill only when a manual task is:
- Done >= 3 times per week
- Done by >= 2 different engineers
- Has a clear, repeatable shape

If any of those is false, write a note in your team wiki instead.

## 2. Scaffold

```bash
cp -r /path/to/claude-base/skill-template plugin-marketplace/plugins/<name>
```

Fill in the frontmatter:

| Field | Notes |
|---|---|
| `name` | kebab-case, must match the directory name |
| `category` | one of the 9 categories |
| `owner` | `team-<your-team>` |
| `permission-tier` | 1 read-only / 2 scoped writes / 3 privileged |
| `mcps-used` | array of MCP server names |
| `version` | `0.1.0` for new skills |
| `status` | `experimental` until eval cases pass |
| `last-reviewed` | today's date |

Fill in the 7 body sections. Be specific in Triggers — they decide auto-load.

## 3. Trial

Use the skill on >= 5 real tasks. Keep notes on:
- Where it produced the wrong answer
- Where the trigger phrases failed to fire
- What the user had to manually correct

## 4. Eval cases

After trial, write >= 3 cases in `tests/eval-cases.yaml` derived from the misses above. Eval cases that come from real failures are worth 10x the ones invented up front.

## 5. Permission test

Edit `tests/permission-test.yaml`:
- `declared_tier` must match `permission-tier` in SKILL.md
- `allowed_bash_patterns` lists every bash invocation the Steps section uses
- `denied_bash_patterns` defaults to BU-wide denies; add team-specific ones

## 6. Inspect AI (tier 2+ only)

For tier 2 or tier 3 skills, add agentic test cases in `tests/inspect_eval.py`. These exercise multi-turn tool use and assert the agent stays inside its declared tool set.

## 7. Local validation

```bash
node /path/to/claude-base/validators/validate-skill.js .
node /path/to/claude-base/validators/check-permissions.js .
promptfoo eval -c tests/promptfooconfig.yaml
inspect eval tests/inspect_eval.py --model anthropic/claude-opus-4-7   # tier 2+ only
```

All four must pass before opening a PR.

## 8. PR

CI runs all four validators automatically. Two reviewers from CODEOWNERS approve.

## 9. Promotion

Flip `status: experimental` -> `stable` when:
- >= 3 eval cases passing at >= 85%
- Used productively for >= 2 weeks
- Tier 2+ has inspect_eval.py passing

## 10. Re-review

Update `last-reviewed` every 6 months. CI warns at 6 months, fails at 12.

## 11. Promotion to BU marketplace

If >= 2 other teams want to consume the skill, promote it from your team marketplace to `claude-base`-aligned BU marketplace. Owner stays the originating team.
