---
name: example-skill
description: Template skill — copy this directory and edit. Replace this description with WHEN Claude should invoke the skill (e.g. "Use when the user asks to inspect X" or "Triggers on mentions of Y"). The description is the only signal Claude uses to auto-load the skill, so be specific about the trigger surface.
allowed-tools: Read Grep Glob
effort: low
---

# Example skill — replace this title

> **This file is a template.** Duplicate the `example-skill/` directory under `skills/`, rename it, and replace every section below.

## What this skill is

One paragraph: what problem this skill solves, what domain knowledge it encodes, and what it expects from the user (inputs, preconditions, VPN, credentials, etc.).

## When NOT to use it

Optional but valuable: list situations where Claude should NOT auto-invoke this. Helps Claude avoid mis-firing.

## Workflow / instructions

Write the body in the imperative voice — these are instructions Claude will follow when the skill is active.

1. Step one
2. Step two
3. Step three

## Reference data

Tables, endpoint lists, code snippets, command templates — anything Claude would need to look up while the skill is active.

| Column | Column |
|---|---|
| value | value |

## Safety gates (optional)

If the skill enables destructive operations (writes, deletes, cluster ops), document the confirmation gates here — name the exact preconditions Claude must check, the dry-run requirement, and the user-confirmation echo before any irreversible action.

## Related

- Links to internal docs, Confluence pages, related skills, code paths.
