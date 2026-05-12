# claude-base

BU-level base for Claude Code skill development across all Perfecto + Blazemeter R&D teams.

## What's here

| Path | Purpose |
|---|---|
| `skill-template/` | The canonical skill scaffold. Every new skill starts as a copy of this. |
| `validators/` | Static validators for `SKILL.md` (schema, sections, permission tier consistency). |
| `settings-base.json` | Baseline Claude Code permissions every product extends. CI rejects products that weaken deny rules. |
| `community-allowlist.yaml` | Approved community skills (Superpowers, BMAD, etc.), pinned to reviewed commits. |
| `.github/workflows/skill-ci.yml` | Reusable workflow team marketplaces call from their CI. |

## Creating a new skill

```bash
# In your team's marketplace repo
cp -r /path/to/claude-base/skill-template plugin-marketplace/plugins/<name>
cd plugin-marketplace/plugins/<name>
# 1. Fill in SKILL.md frontmatter and body
# 2. Add eval cases to tests/eval-cases.yaml
# 3. Match permission-test.yaml to the declared tier
# 4. For tier 2+, fill in tests/inspect_eval.py

# Validate locally
node /path/to/claude-base/validators/validate-skill.js .
promptfoo eval -c tests/promptfooconfig.yaml
```

## CI integration (team marketplace)

In `<your-marketplace>/.github/workflows/ci.yml`:

```yaml
on:
  pull_request:
    paths: ['plugin-marketplace/plugins/**']
jobs:
  validate:
    uses: PerfectoMobileDev/claude-base/.github/workflows/skill-ci.yml@main
    with:
      skill_path: plugin-marketplace/plugins/<changed-plugin>
    secrets: inherit
```

## Standards summary

- **9 categories**: onboarding, build-test, vcs-pr, issue-mgmt, ci-cd, observability, data-store, security, hooks
- **3 permission tiers**: 1=read-only, 2=scoped writes, 3=privileged
- **Promotion gate**: experimental → stable requires >= 3 eval cases passing at >= 85%
- **Re-review**: every 6 months; CI fails after 12 months without `last-reviewed` update

See `docs/creating-a-skill.md` for the full lifecycle.

## Worked example

`PerfectoMobileDev/reporting-claude/plugin-marketplace/plugins/pr-health-check-example/` is a template-conforming reference skill. Use it as the model when authoring a new one.
