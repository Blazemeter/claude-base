# claude-base

BU-level base for Claude Code skill development across all Perfecto + Blazemeter R&D teams.

## What's here

| Path | Purpose |
|---|---|
| `skill-template/` | The canonical skill scaffold. Every new skill starts as a copy of this. |
| `validators/` | Static validators for `SKILL.md` (schema, sections, permission tier consistency, community-pin integrity). |
| `settings-base.json` | Baseline Claude Code permissions every product extends. CI rejects products that weaken deny rules. |
| `community-allowlist.yaml` | Approved community skills (Superpowers, BMAD, etc.), pinned to reviewed commit SHAs. |
| `.github/workflows/skill-ci.yml` | Reusable workflow team marketplaces call from their CI (secret scan → SAST → static → red-team → behavioural → agentic). |

## Creating a new skill

```bash
# In your team's marketplace repo
cp -r /path/to/claude-base/skill-template plugin-marketplace/plugins/<name>
cd plugin-marketplace/plugins/<name>
# 1. Fill in SKILL.md frontmatter and body
# 2. Add behavioural cases to tests/eval-cases.yaml (>= 3 for stable)
# 3. Add red-team cases to tests/redteam-cases.yaml (>= 4 for stable)
# 4. Match permission-test.yaml to the declared tier
# 5. For tier 2+, fill in tests/inspect_eval.py (must include a denied_action_* Sample)

# Validate locally
node /path/to/claude-base/validators/validate-skill.js .
node /path/to/claude-base/validators/check-permissions.js .
promptfoo eval -c tests/promptfooconfig.yaml
promptfoo eval -c tests/redteam-cases.yaml   # red-team gate, >= 95% pass
```

## CI integration (team marketplace)

In `<your-marketplace>/.github/workflows/ci.yml`:

```yaml
on:
  pull_request:
    paths: ['plugin-marketplace/plugins/**']
jobs:
  validate:
    # Pin claude-base by commit SHA, not @main. Bumps require a security review.
    uses: PerfectoMobileDev/claude-base/.github/workflows/skill-ci.yml@<sha>
    with:
      skill_path: plugin-marketplace/plugins/<changed-plugin>
    # Pass only the secrets the workflow declares — never `secrets: inherit`.
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      LANGFUSE_PUBLIC_KEY: ${{ secrets.LANGFUSE_PUBLIC_KEY }}
      LANGFUSE_SECRET_KEY: ${{ secrets.LANGFUSE_SECRET_KEY }}
```

## Standards summary

- **9 categories**: onboarding, build-test, vcs-pr, issue-mgmt, ci-cd, observability, data-store, security, hooks
- **3 permission tiers**: 1=read-only, 2=scoped writes, 3=privileged
- **Promotion gate**: experimental → stable requires
  - >= 3 behavioural eval cases passing at >= 85%
  - >= 4 red-team cases (prompt-injection, indirect-injection, denied-action, exfil) passing at >= 95%
  - tier 2+ skills: at least one `denied_action_*` Sample in `tests/inspect_eval.py`
- **Re-review**: every 6 months; CI fails after 12 months without `last-reviewed` update

## Security gates in the reusable CI

The workflow at `.github/workflows/skill-ci.yml` runs, in order:

1. **`security-validate`** — `gitleaks` secret scan + `semgrep` SAST (`p/ci`, `p/secrets`, `p/owasp-top-ten`) on the skill's tests and scripts.
2. **`static-validate`** — schema / sections / permission-tier parity + `check-community-pins` (rejects placeholder or non-SHA pins in `community-allowlist.yaml`) + `npm audit --audit-level=high` on validator deps.
3. **`promptfoo-eval`** — behavioural eval (≥ 85%) and red-team eval (≥ 95%) traced to Langfuse. `promptfoo` version is pinned.
4. **`inspect-agentic`** — runs in a sandboxed container (`--cap-drop=ALL`, `--read-only`, `--security-opt=no-new-privileges`) with no egress except the Anthropic API.

All third-party actions are pinned by commit SHA. Secrets are passed by name; `secrets: inherit` is disallowed in caller workflows.

See `docs/creating-a-skill.md` for the full lifecycle.

## Worked example

`PerfectoMobileDev/reporting-claude/plugin-marketplace/plugins/pr-health-check-example/` is a template-conforming reference skill. Use it as the model when authoring a new one.
