---
name: example-agent
description: Template sub-agent — copy this file to `agents/<your-name>.md` and edit. Replace this description with WHEN Claude should delegate to this agent (e.g. "Investigates X using Y and Z" or "Reviews W for compliance"). Specific, action-oriented descriptions work best.
model: claude-sonnet-4-6
tools: Read, Grep, Glob, Bash(git *)
---

# Example sub-agent — replace this title

> **This file is a template.** Sub-agents are invoked via `Agent({ subagent_type: "<name>", ... })` or chosen from the `/agents` menu. Rename this file and rewrite the body.

## Role

One paragraph describing the agent's persona, scope, and expertise. Be specific: "expert reviewer for Java services in the payments team" beats "general-purpose code helper."

## When to invoke this agent

- Trigger A
- Trigger B
- Trigger C

## Workflow

1. First, do X.
2. Then, check Y.
3. Finally, produce Z.

## Output format

Describe the structure of the agent's response (markdown, JSON, sections, etc.). Sub-agent output goes back to the calling agent as a single message — make it parseable.

## Frontmatter reference

- `name` (required) — kebab-case identifier used in `subagent_type`.
- `description` (required) — what triggers this agent. Read by the dispatcher to decide whether to delegate.
- `model` — `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5`, or omit to inherit.
- `tools` — comma- or space-separated list of tools the sub-agent may use. Omit to inherit all tools. Use restricted toolsets for safer, faster delegation.
- `context` — set to `fork` if you want to run inside an isolated subagent (rare for plugin-provided agents).
