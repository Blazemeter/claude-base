# Skill template

Copy this directory when starting a new skill:

```bash
cp -r ../../claude-base/skill-template plugin-marketplace/plugins/<your-skill-name>
```

Then fill in:

1. `SKILL.md` — frontmatter (all required fields) + 7 body sections
2. `tests/eval-cases.yaml` — at least one case for `experimental`, three for `stable`
3. `tests/permission-test.yaml` — match the `permission-tier` declared in `SKILL.md`
4. `tests/inspect_eval.py` — only required for tier 2+ or agentic flows

Run locally before opening a PR:

```bash
node ../../../claude-base/validators/validate-skill.js .
promptfoo eval -c tests/promptfooconfig.yaml
inspect eval tests/inspect_eval.py --model anthropic/claude-opus-4-7   # if applicable
```

See `claude-base/docs/creating-a-skill.md` for the full lifecycle.
