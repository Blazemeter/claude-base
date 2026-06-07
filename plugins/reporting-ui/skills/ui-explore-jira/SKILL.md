---
name: ui-explore-jira
description: Explore a Jira issue or epic and produce a structured brief — summary, status, acceptance criteria, recent comments, linked issues, and linked PRs (plus child issues if it's an epic). Use when the user names a Jira key like "MOB-1234", "explore JIRA-42", "what's in ABC-99", "look up ticket X", "summarize this epic", or pastes an atlassian.net browse URL. Do NOT use to create, edit, transition, or comment on an issue (those are write actions — use a different skill), and do NOT use for non-Jira trackers (GitHub Issues, Linear, Asana).
allowed-tools: mcp__claude_ai_Atlassian_Rovo__getAccessibleAtlassianResources mcp__claude_ai_Atlassian_Rovo__getJiraIssue mcp__claude_ai_Atlassian_Rovo__searchJiraIssuesUsingJql mcp__claude_ai_Atlassian_Rovo__getJiraIssueRemoteIssueLinks
---

# ui-explore-jira

Pull together everything worth knowing about a Jira issue or epic in one read, so the user (or
a parent skill) can act on it without clicking into the browser. Read-only — this skill never
changes anything in Jira.

## When to use

- The user names a Jira key (`MOB-1234`, `ABC-99`) or pastes an `…atlassian.net/browse/<KEY>` URL.
- "Explore / look up / summarize / what's in" + a ticket or epic.
- As the first step of a parent workflow that needs the ticket's intent before implementing.

## When NOT to use

- Creating, editing, transitioning, or commenting on an issue — those are writes (a different skill).
- Non-Jira trackers (GitHub Issues, Linear, Asana, Trello).

## Preconditions

- The Atlassian MCP server is connected (the `mcp__claude_ai_Atlassian_Rovo__*` tools are available).
  If those tools aren't present, tell the user to connect the Atlassian integration and stop —
  do not guess at issue contents.

## Workflow

1. **Resolve the key.** From a bare key (`MOB-1234`) use it directly. From a browse URL
   (`https://<site>.atlassian.net/browse/MOB-1234`) extract the trailing key.

2. **Find the cloud id.** The Jira tools accept the **site hostname as `cloudId` directly** — try
   the hostname first (e.g. `perforce.atlassian.net`, from the browse URL or the team's known
   site). Only if that fails, call `getAccessibleAtlassianResources` to list sites and pick the
   matching one (ask the user if several match).

3. **Fetch the issue, comments included.** Call `getJiraIssue` with the `cloudId`, `issueIdOrKey`,
   `responseContentFormat: "markdown"`, and an **explicit `fields` list** — `getJiraIssue` omits the
   comment thread by default, so you must request it:
   `["summary","issuetype","status","priority","assignee","reporter","labels","fixVersions","description","comment"]`.
   Read summary, type, status, priority, assignee/reporter, labels, fix version, description, the
   acceptance-criteria section if present, and the comments.

4. **If it's an Epic, fetch its children.** When `issuetype` is `Epic`, call
   `searchJiraIssuesUsingJql` with `parent = <KEY> ORDER BY status` (fall back to
   `"Epic Link" = <KEY>` on older Jira) to list child stories with their key, summary, and status.

5. **Fetch linked PRs / remote links.** Call `getJiraIssueRemoteIssueLinks` for the issue to
   surface linked GitHub PRs, Confluence pages, or other remote links.

6. **Summarize comments.** From the issue's comments, take the most recent 3–5; quote the gist,
   not the whole thread.

7. **Produce the brief** in the format below. Keep it tight — this is a decision aid, not a dump.

## Output format

```
## <KEY> — <summary>

- **Type/Status:** <type> · <status> · **Priority:** <priority>
- **Assignee:** <name or Unassigned> · **Reporter:** <name> · **Fix version:** <version or —>
- **Labels:** <labels or —>

### What it asks for
<2–4 sentences distilled from the description.>

### Acceptance criteria
<Bulleted ACs if present, else "Not specified in the ticket.">

### Children   (epics only)
| Key | Summary | Status |
|-----|---------|--------|
| ... | ...     | ...    |

### Linked PRs / links
- <PR/link title → url, or "None linked.">

### Recent comments
- <author, date: one-line gist> (most recent 3–5, or "None.")

### Open questions / risks
<Anything ambiguous, blocked, or missing that a doer would need clarified. "None obvious" is fine.>
```

## Notes

- Read-only. Never transition, comment, or edit — if the user asks for that mid-flow, hand off
  (don't do it from here).
- Don't paste raw API JSON to the user — extract the fields into the brief above.
- Truncate any single field longer than ~400 chars with `…`.
- If the key doesn't exist or you lack permission, say so plainly with the key you tried.

## Related

- A future `update-jira` skill (the write counterpart: transition + comment).
- Parent workflows (CVE resolution, support-ticket resolution) call this first to understand the work.
