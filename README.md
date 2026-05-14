# claude-base — reusable Claude Code plugin marketplace

[![Plugin marketplace validate](https://github.com/<owner>/claude-base/actions/workflows/plugin-validate.yml/badge.svg)](https://github.com/<owner>/claude-base/actions/workflows/plugin-validate.yml)

A project-agnostic [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin marketplace. Ships generic **skills**, **slash commands**, **sub-agents**, and **hooks** plus an example layout you can fork into your own org's marketplace.

> Replace `<owner>` in the badge URL above with the GitHub org once this repo's home is final.

## Quick install (for users)

Inside Claude Code:

```text
/plugin marketplace add <owner>/<repo>
/plugin install base-tools@claude-base
```

(Replace `<owner>/<repo>` with the GitHub path where this repo lives.)

That's it — Claude will auto-load all skills, register all slash commands, expose all sub-agents, and activate plugin hooks. Updates land automatically when you run `/plugin update`.

To verify:

```text
/plugin list                          # confirms base-tools is installed
/base-tools:example-command           # try the example slash command
```

## What's inside

```
claude-base/
├── .claude-plugin/
│   └── marketplace.json              # Catalog — lists every plugin in this repo
├── plugins/
│   └── base-tools/                   # The (currently single) bundled plugin
│       ├── .claude-plugin/
│       │   └── plugin.json           # Plugin manifest (name, version, license)
│       ├── skills/                   # Auto-loaded by Claude based on description
│       │   ├── example-skill/
│       │   │   └── SKILL.md          # Template — copy to start a new skill
│       │   └── summarize-pr/         # Real working skill — reference implementation
│       │       ├── SKILL.md
│       │       └── tests/
│       │           └── cases.yaml    # Behavioral test cases
│       ├── commands/                 # Slash commands (/base-tools:<name>)
│       │   └── example-command.md    # Template — copy to start a new command
│       ├── agents/                   # Sub-agents (Agent tool / /agents menu)
│       │   └── example-agent.md      # Template — copy to start a new agent
│       ├── hooks/                    # Hook scripts referenced from hooks.json
│       │   ├── README.md
│       │   ├── audit-file-changes.sh
│       │   ├── block-secrets-on-write.sh
│       │   └── log-skill-activation.py
│       └── hooks.json                # Plugin-level event hooks (Pre/Post ToolUse, Skill, etc.)
├── policy/
│   └── allowed-tools.yaml            # Tool allowlist + denylist enforced by validator
├── scripts/
│   ├── validate.py                   # Python validator (schema, standards, policy, secrets)
│   ├── behavioral_runner.py          # Schema-lint + opt-in Anthropic-API skill tests
│   ├── aggregate_telemetry.py        # Summarize skill-activation telemetry
│   ├── requirements.txt              # pip dep: pyyaml
│   ├── requirements-eval.txt         # Optional: anthropic SDK (for API runs)
│   ├── README.md
│   └── tests/
│       └── test_validate.py          # Regression tests (stdlib only)
├── .github/
│   ├── CODEOWNERS
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/plugin-validate.yml # CI: structural / SAST / secret-scan / claude-cli
├── CONTRIBUTING.md
├── LICENSE
└── README.md
```

## Adding new artifacts

### A new skill

```bash
cp -r plugins/base-tools/skills/example-skill plugins/base-tools/skills/<your-skill>
$EDITOR plugins/base-tools/skills/<your-skill>/SKILL.md
```

Edit the YAML frontmatter:

- `name` — kebab-case ID (must match directory name).
- `description` — Claude reads this to decide *when* to auto-load the skill. Be specific about triggers ("Use when the user asks to X").
- `allowed-tools` — optional space-separated list of tools the skill can use without prompting.

Once committed, users get it on the next `/plugin update`.

### A new slash command

```bash
cp plugins/base-tools/commands/example-command.md plugins/base-tools/commands/<your-command>.md
```

Slash commands are flat `.md` files (no subdirectory). After install they're invokable as `/base-tools:<your-command>`. They support `$ARGUMENTS`, `$1`, `$2`, and dynamic context injection with `` !`shell-cmd` ``.

### A new sub-agent

```bash
cp plugins/base-tools/agents/example-agent.md plugins/base-tools/agents/<your-agent>.md
```

Sub-agents are flat `.md` files with `name`, `description`, `model`, and `tools` frontmatter. They show up under `/agents` and can be called from the main agent via the `Agent` tool with `subagent_type: "<your-agent>"`.

### A new hook

Hook scripts live under `plugins/base-tools/hooks/` (one script per file). The wiring is in `plugins/base-tools/hooks.json`, which maps events + matchers to script paths.

**Workflow:**

```bash
# 1. Drop your script in the hooks folder. Use a shebang.
$EDITOR plugins/base-tools/hooks/<your-hook>.sh

# 2. Register it in hooks.json under the right event:
#    "<EventName>": [{ "matcher": "<regex>", "hooks": [{ "type": "command",
#      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/<your-hook>.sh" }] }]

# 3. (Linux/macOS) make it executable
chmod +x plugins/base-tools/hooks/<your-hook>.sh
```

**Supported events:**

- `PreToolUse`, `PostToolUse` (with `matcher` regex on tool name) — non-zero exit on `Pre*` blocks the tool call.
- `PreCommand`, `PostCommand`
- `PreFile`, `PostFile`
- `PreSkill`, `PostSkill`
- `PostSubagentSpawn`

**Environment provided to hook scripts:**

- `${CLAUDE_PLUGIN_ROOT}` — install path of this plugin (use for `command:` references in `hooks.json` and for sourcing helpers).
- `${CLAUDE_PLUGIN_DATA}` — per-user persistent data dir (use for logs, audit state — survives plugin upgrades).
- `${CLAUDE_SESSION_ID}` — current session.
- **stdin** — the tool/event payload as JSON. Parse with `jq` or `json.load(sys.stdin)`.

See `plugins/base-tools/hooks/README.md` for full conventions and the bundled example scripts:

- `audit-file-changes.sh` — `PostToolUse` logger for Write/Edit calls.
- `block-secrets-on-write.sh` — `PreToolUse` guard that blocks writes containing obvious secret patterns.
- `log-skill-activation.py` — `PreSkill` telemetry collector.

## Adding a second plugin

This marketplace supports many plugins. To add one:

1. `mkdir -p plugins/<new-plugin>/.claude-plugin/`
2. Create `plugins/<new-plugin>/.claude-plugin/plugin.json` (copy `base-tools/.claude-plugin/plugin.json` and rename).
3. Add an entry to the top-level `.claude-plugin/marketplace.json` `plugins` array.
4. Drop `skills/`, `commands/`, `agents/`, `hooks/`, `hooks.json` under the new plugin directory.

Users then install with `/plugin install <new-plugin>@claude-base`.

## Validating before pushing

Five independent CI jobs gate every merge. Each runs on its own runner — a failure in one diagnoses without blocking insight into the others.

### Layer 1 — structural / standards / tool policy / smoke secrets (Python)

```bash
pip install -r scripts/requirements.txt   # one-time, single dep (pyyaml)
python scripts/validate.py                # report
python scripts/validate.py --strict       # treat warnings as errors
```

`scripts/validate.py` covers:

- **Schema** for `marketplace.json`, every `plugin.json`, every `SKILL.md` / command / agent frontmatter, and `hooks.json`.
- **Standards**: kebab-case names, name ↔ directory parity, SKILL.md length budget, agent file-stem ↔ name parity, no human-centric files inside skill dirs.
- **Hook wiring**: every referenced script exists; each script has a shebang; every event name is known.
- **Tool policy**: every `allowed-tools` (skills/commands) and `tools` (agents) entry is checked against `policy/allowed-tools.yaml`. Unscoped `Bash` is forbidden by default. MCP tools (`mcp__*`) are exempt.
- **Smoke secret scan**: high-signal patterns (AWS keys, private key headers, GH / Slack / GitLab / Google tokens) so contributors catch obvious leaks before pushing.

See `scripts/README.md` for the full check list, the tool policy, and instructions for adding project-specific rules.

### Layer 2 — SAST on hook scripts (`shellcheck`, `ruff`)

Hook scripts run unsupervised on every developer's machine — they're the highest-leverage surface. CI lints them:

- `shellcheck plugins/**/hooks/**/*.sh` — catches unquoted vars, missing error handling, dangerous patterns.
- `ruff check plugins/**/hooks/**/*.py` — catches bare `except`, eval-of-user-input, broken imports, lint.

Replicate locally:

```bash
shellcheck plugins/*/hooks/*.sh
pip install ruff && ruff check plugins/*/hooks/*.py
```

### Layer 3 — comprehensive secret scan (gitleaks)

CI runs [`gitleaks/gitleaks-action`](https://github.com/gitleaks/gitleaks-action) with `fetch-depth: 0` so it scans the whole history, not just the PR diff. To replicate locally:

```bash
gitleaks detect --source . --redact
```

### Layer 4 — Claude Code's own validator

```bash
# Inside Claude Code:
/plugin validate .

# Or from the terminal (requires the Claude CLI):
claude plugin validate .
```

This is the canonical schema check that mirrors what Claude Code does at plugin-install time.

### Layer 5 — Behavioral tests (opt-in)

Each skill can ship `tests/cases.yaml` with prompts + assertions. `scripts/behavioral_runner.py` lints them every PR and — if the `ANTHROPIC_API_KEY` secret is configured — runs them against the Anthropic API:

```bash
python scripts/behavioral_runner.py --lint                  # always works
ANTHROPIC_API_KEY=... pip install -r scripts/requirements-eval.txt
python scripts/behavioral_runner.py                          # API mode
```

See `plugins/base-tools/skills/summarize-pr/tests/cases.yaml` for a worked example.

### Supply-chain hardening

Every action used in `.github/workflows/plugin-validate.yml` is pinned by full commit SHA (with `# vN` comment for readability) — a compromised tag can't escalate into CI. When bumping versions:

```bash
gh api repos/<owner>/<repo>/commits/v<N> --jq .sha
```

Replace the SHA in the workflow and update the trailing comment. Never use a floating tag (`@v4`, `@main`).

## Release process

- **Default**: leave `"version"` out of `plugin.json` — Claude Code uses the git commit SHA so every merge to `main` is automatically the latest release.
- **Explicit versioning**: set `"version": "x.y.z"` and bump it for every user-visible release. Users won't get updates until the string changes.
- **Channels**: maintain two marketplace entries (e.g. `stable` and `latest` refs) if you need staged rollouts.

## Why this format

Claude Code natively discovers plugins published as marketplaces, so users get auto-loading skills, namespaced slash commands, an `/agents` menu, plugin hooks, and one-command updates. See the [official Claude Code plugin docs](https://docs.claude.com/en/docs/claude-code/plugins) for the full spec.

## License

See `LICENSE` (if present) at repo root. The `base-tools` plugin manifest is set to `UNLICENSED` by default — change it to `MIT`, `Apache-2.0`, or whichever SPDX identifier applies before publishing externally.
