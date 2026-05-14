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

See `../hooks.json` for how these are wired up.
