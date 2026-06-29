# `hooks/` — plugin hook scripts

This directory holds executable scripts referenced from `../hooks.json`. Keep one script per file, name them after the event + matcher they implement.

## Conventions

- **Shebang**: every script starts with a portable shebang (`#!/usr/bin/env bash` or `#!/usr/bin/env python3`).
- **Executable bit**: scripts must be `chmod +x` on Linux/macOS; on Windows, Claude Code runs them via the configured shell — no chmod needed but keep them POSIX-style if Linux teammates will run them.
- **stdin = tool input**: Claude Code pipes the tool/event payload to stdin as JSON. Read with `jq` (bash) or `json.load(sys.stdin)` (python).
- **Exit code = decision**: exit `0` to allow; exit non-zero to **block** the action (for `Pre*` events). Stdout/stderr is shown to the user.
- **Reference from hooks.json**: use `${CLAUDE_PLUGIN_ROOT}/hooks/<script>` — that variable expands to this plugin's install path.
- **Data dir**: persist audit logs / state under `${CLAUDE_PLUGIN_DATA}` so they survive plugin upgrades and don't write to read-only plugin install paths.

## Supported events

| Event | When it fires | Common use |
|---|---|---|
| `SessionStart` | When a session begins. Stdout is appended to context. | Inject an always-on primer (standards, repo memory) |
| `Stop` | When Claude finishes a turn. Stdout is appended to context. | Close-out reminders (lifecycle, cleanup) |
| `PreToolUse` | Before any tool call. Non-zero exit blocks the call. | Guardrails (block writes to forbidden paths, deny dangerous bash) |
| `PostToolUse` | After a tool call completes. | Audit logging, secret scans on diffs, lint on writes |
| `PreCommand` | Before a slash command runs. | Permission checks |
| `PostCommand` | After a slash command runs. | Telemetry |
| `PreFile` / `PostFile` | File read/write boundaries. | Encryption, redaction |
| `PreSkill` / `PostSkill` | Skill activation boundaries. | Logging which skills triggered |
| `PostSubagentSpawn` | After a sub-agent is launched. | Tracking sub-agent usage |

## Matchers

In `hooks.json`, the `matcher` field is a regex matched against the tool/command name. Examples:

- `"Write|Edit"` — both Write and Edit tool calls.
- `"Bash"` — any shell command (use the `tool_input.command` JSON field to further filter inside the script).
- `".*"` — every tool call (use sparingly — hot path).

## Examples in this directory

- `audit-file-changes.sh` — minimal `PostToolUse` audit logger.
- `block-secrets-on-write.sh` — `PreToolUse` guard that blocks writes containing obvious secret patterns.
- `log-skill-activation.py` — `PreSkill` telemetry, Python.

## STANDARDS enforcement hooks

These implement the baseline rules in `../../../STANDARDS.md`:

- `inject-standards-index.sh` — `SessionStart`. Injects a 1-page primer of the five baseline rules + safety guardrails so they are in context from turn one, without re-reading the full `STANDARDS.md` each session. Pure priming — always exits 0, never blocks.
- `remind-jira-lifecycle.sh` — `Stop`. When the current branch references a real (non-zero) JIRA key, reminds Claude to keep that issue's lifecycle current via the `jira-lifecycle` skill (rule #5) — the most-missed step being *In Review* + PR link on PR open. Deduped to at most once per session+branch (marker under `${CLAUDE_PLUGIN_DATA}`); advisory, always exits 0.
- `enforce-jira-id.sh` — `PreToolUse`/`Bash`. Blocks `git checkout -b`, `git switch -c`, `git branch <name>`, and `gh pr create` when no JIRA key (`[A-Z][A-Z0-9_]+-[0-9]+`) is present.
- `enforce-claude-attribution.sh` — `PreToolUse`/`Bash`. Blocks `git commit -m …` when the message lacks a `Co-Authored-By: Claude` trailer. Lets `--amend --no-edit` and `--fixup` through.
- `inject-ai-generated-label.sh` — `PreToolUse`/`mcp__claude_ai_Atlassian_Rovo__createJiraIssue`. Blocks the create call when the `AI_generated` label is missing from `tool_input.additional_fields.labels` (where the MCP tool actually reads labels; legacy `tool_input.labels` / `tool_input.fields.labels` shapes are also tolerated) and tells Claude to retry with the label added under `additional_fields.labels`.

All three honour `CLAUDE_STANDARDS_SKIP=1` as an escape hatch; every skip is logged to `${CLAUDE_PLUGIN_DATA}/base-tools/standards-skip.log`.

The server-side counterparts live in `../../../.github/workflows/jira-id-lint.yml` and `claude-attribution-lint.yml` — make those required status checks in branch protection if you want true compulsion.

## Safety guardrail hooks

These block destructive actions Claude should never take autonomously. See `../../../STANDARDS.md` → "Safety guardrails" for the rationale and the override contract.

- `block-ec2-cloud-mutations.sh` — `PreToolUse`/`Bash`. Blocks mutating `aws ec2` verbs (run/start/stop/terminate/create/delete/modify/…) and `gcloud compute` mutations. Read verbs (`describe-*`/`get-*`/`list`) pass.
- `block-datastore-mutations.sh` — `PreToolUse`/`Bash`. Blocks destructive/creative DynamoDB, S3 (`rb`/`rm`/`mv`/`sync --delete`/uploads/`s3api` writes), Redis (`redis-cli` writes), and Mongo (`mongoimport`/`mongorestore`, destructive `mongo`/`mongosh` ops). Reads/downloads/dumps pass.
- `block-shared-branch-git.sh` — `PreToolUse`/`Bash`. Blocks `git push` to `master`/`main`, force push to a shared branch, and `git rebase`/`git reset --hard` while on a shared branch (`master`, `main`, `develop`, `staging`, `prod`, `release/*`, `hotfix/*`).
- `block-credentials-in-commit.sh` — `PreToolUse`/`Bash`. Blocks `git add`/`git commit` of key/credential files (`id_rsa`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*.jks`, `*.keystore`, `*.ppk`, `.env`, AWS `credentials`) and any staged diff matching a secret pattern. *(Allowlisted in `validate.py` + `.gitleaks.toml` because it contains literal secret regexes.)*
- `block-test-skips.sh` — `PreToolUse`/`Write|Edit`. Blocks adding test-skip annotations (`@Disabled`/`@Ignore`, `pytest.mark.skip`, `.skip(`/`xit`/`xdescribe`/`pending`) in test files, and `-DskipTests`/`maven.test.skip` in build files.
- `block-hook-bypass.sh` — `PreToolUse`/`Bash`. Blocks `--no-verify`/`git commit -n`, `core.hooksPath` overrides, `HUSKY=0`, `chmod`/`rm` on hook files, and inlined `CLAUDE_*_SKIP=`/`CLAUDE_SAFETY_OVERRIDE=` prefixes.

All six honour a **human-exported** `CLAUDE_SAFETY_OVERRIDE=1` (read from the hook's own environment — Claude cannot self-bypass by inlining it); every override is logged to `${CLAUDE_PLUGIN_DATA}/base-tools/safety-override.log`.

See `../hooks.json` for how these are wired up.
