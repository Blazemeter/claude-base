---
description: Template slash command — copy this file to `commands/<your-name>.md` and edit. Replace this description with a one-line summary; it shows up in the `/` menu.
argument-hint: "[optional args hint]"
---

> **This file is a template.** Once your marketplace + plugin are installed, the user can invoke this with `/base-tools:example-command`. Rename the file and rewrite this body.

You can reference user input with `$ARGUMENTS` (full string) or `$1`, `$2`, etc. for positional args.

## Behavior

Describe what the command does. Be precise — these instructions are read by Claude and followed in the next assistant turn.

1. Read the relevant file: ...
2. Run the relevant tool: ...
3. Report the result in the format: ...

## Notes

- Slash commands are flat `.md` files under `commands/` — no subdirectory needed.
- They support the same frontmatter as `SKILL.md` (`description`, `allowed-tools`, `model`, `argument-hint`, etc.).
- Dynamic command substitution works: `` !`git status -s` `` inserts the live output before Claude sees the command body.
