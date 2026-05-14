# `scripts/` — validation tooling

Standalone Python scripts for validating the marketplace. No `node_modules`, single pip dependency (`pyyaml`).

## Setup (once per machine)

```bash
pip install -r scripts/requirements.txt
```

## Run the validator locally

```bash
python scripts/validate.py
# or, with warnings promoted to errors:
python scripts/validate.py --strict
```

The validator scans `.claude-plugin/marketplace.json`, every `plugins/*/.claude-plugin/plugin.json`, every `SKILL.md`, every slash command, every sub-agent, every `hooks.json`, and the bodies of every text file in the repo. See the docstring at the top of `validate.py` for the full check list.

Exit codes:

- `0` — clean
- `1` — at least one error (or warning, in `--strict` mode)
- `2` — could not run (missing pyyaml, no marketplace at root)

## What's covered vs. what's not

| Layer | Covered by | Where it runs |
|---|---|---|
| JSON / YAML well-formedness | `validate.py` | local + CI |
| Frontmatter required fields, kebab-case names, name/dir parity | `validate.py` | local + CI |
| Hook event names, referenced scripts exist, shebangs | `validate.py` | local + CI |
| SKILL.md length budget, no human-centric files inside skill dirs | `validate.py` | local + CI |
| **Tool policy** — every `allowed-tools` / `tools` entry on the allowlist | `validate.py` + `policy/allowed-tools.yaml` | local + CI |
| **Smoke** secret patterns (AWS keys, private keys, GH/Slack/GitLab tokens) | `validate.py` | local + CI |
| **SAST** on hook scripts (`shellcheck`, `ruff`) | `.github/workflows/plugin-validate.yml` `sast` job | CI |
| **Comprehensive** secret scanning (full gitleaks ruleset, history-aware) | `gitleaks-action` | CI |
| Claude Code's own schema validation | `claude plugin validate .` | CI (if Claude CLI available) |
| **Behavioral tests** of skills (assertions against Anthropic API responses) | `scripts/behavioral_runner.py` | CI opt-in (`ANTHROPIC_API_KEY` secret) |
| **Telemetry aggregation** of skill activations | `scripts/aggregate_telemetry.py` | local, on demand |

The five jobs in `.github/workflows/plugin-validate.yml` (`structural`, `sast`, `secret-scan`, `claude-cli`, `behavioral`) are independent — any one of them failing blocks the merge. `behavioral` always lints test cases but only invokes the Anthropic API if the `ANTHROPIC_API_KEY` secret is configured.

## Editing the tool policy

`policy/allowed-tools.yaml` declares which tools may appear in any skill / command / agent frontmatter. To add a new permitted Bash scope, e.g. `Bash(terraform *)`:

1. Add the entry under `allowed:` in `policy/allowed-tools.yaml`. Keep the scope as narrow as possible.
2. Run `python scripts/validate.py` locally.
3. Open a PR; reviewers can see exactly what new shell surface is being granted.

To explicitly deny a tool (overrides allowlist), add it under `forbidden:`. Unscoped `Bash` and `Bash(*)` are already forbidden by default.

**Per-artifact exceptions.** If a single skill legitimately needs a tool not in the global allowlist, add an entry under `exceptions:` rather than widening the allowlist:

```yaml
exceptions:
  - artifact: base-tools/skills/terraform-plan
    tools: [Bash(terraform plan), Bash(terraform show*)]
    justification: "plan-only summary skill; cannot run apply or destroy"
```

The `artifact` path is `<plugin>/<kind>/<name>` where `<kind>` is one of `skills`, `commands`, `agents`. Exceptions are narrow — they grant ONE tool to ONE artifact. `forbidden:` still wins over exceptions. CODEOWNERS reviews every change to `policy/` so each exception gets explicit human sign-off.

MCP tools (anything starting with `mcp__`) are exempt from this policy — they are governed by `.mcp.json` instead.

## Telemetry aggregation

The `log-skill-activation.py` `PreSkill` hook records one JSON line per skill activation to `${CLAUDE_PLUGIN_DATA}/base-tools/skills.jsonl`. Aggregate it into a markdown summary:

```bash
python scripts/aggregate_telemetry.py                       # default path, top 10
python scripts/aggregate_telemetry.py --since 2026-04-01    # filter window
python scripts/aggregate_telemetry.py --top 25 --format json | jq .
```

Outputs activation counts, last-seen timestamps, unique sessions. Useful for a team lead seeing which skills are actually getting traction.

## Behavioral test runner

`scripts/behavioral_runner.py` walks `plugins/<plugin>/skills/<name>/tests/cases.yaml`, validates each test case's schema, and (with an API key) sends each prompt to the Anthropic API using the skill's `SKILL.md` as system context. Assertions check the response text.

```bash
# Lint cases.yaml structure only — no API key needed:
python scripts/behavioral_runner.py --lint

# Run all behavioral tests (requires ANTHROPIC_API_KEY + the anthropic SDK):
pip install -r scripts/requirements-eval.txt
ANTHROPIC_API_KEY=... python scripts/behavioral_runner.py

# Restrict to one skill:
python scripts/behavioral_runner.py --skill base-tools/summarize-pr
```

Case schema:

```yaml
skill: <plugin>/<name>
cases:
  - name: unique-test-name
    prompt: "user-style prompt"
    expected:
      response_must_contain: ["substring"]    # all must appear
      response_must_not_contain: ["forbidden"] # none may appear
```

Caveat: this tests *instruction-following* (skill body as system prompt), not Claude Code's plugin auto-invocation. It catches most regressions for ~0% of the engineering cost; for full end-to-end coverage you'd need to spawn Claude Code itself.

## Extending the validator

To add a project-specific rule (e.g. require every skill description to include the literal word "Use"):

1. Add a new check in `validate.py`. Keep it pure: read files, return `list[Issue]` where `Issue = (severity, file, line, message)`. `severity` is `"ERROR"` or `"WARN"`.
2. Wire it into `main()` alongside the existing `validate_*` calls.
3. Add a test case in `scripts/tests/test_validate.py` (negative fixture asserts the new error fires).
4. Run `python scripts/validate.py` and `python -m unittest discover -s scripts/tests -t scripts` locally.
