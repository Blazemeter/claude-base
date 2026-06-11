# Documentation-planning JIRA task — canonical template

This is the documentation team's standard for a doc-planning ticket. The
`file-doc-task` skill produces a ticket that matches it **exactly**. Do not
reorder, rename, or drop sections.

## Ticket metadata

| Field | Value |
|-------|-------|
| **Summary (title)** | `DOC-ready: [Feature name]` — use the customer-facing feature name |
| **Label** | `ready-for-docs` |
| **Project / issue type / link type** | See `policy/doc-task.yaml` (deployment-specific config) |

## Authoring rules (non-negotiable)

1. Use the **customer-facing feature name** in the title.
2. Write all content in **plain English** and use **active voice**.
3. Keep the description **concise, factual, and useful for documentation planning**.
4. **Do not invent missing information.**
5. Do **not** invent UI text, behavior, steps, defaults, limits, permissions,
   supported environments, or unsupported scenarios.
6. If required information is missing, put it under **Internal notes** as an
   open question — never guess.
7. Focus **only** on customer-facing impact and documentation-relevant
   information.

## Description structure (use exactly this)

```markdown
## Context summary
- Feature name: [customer-facing feature name]
- Related engineering ticket: [Jira key and link]
- Engineering SME: [full name]
- High-level overview: [2-4 sentence plain-English summary of what the feature does]

## Customer impact
- Customer value: [why this matters to customers]
- Why/how this feature is customer-facing: [how customers encounter, use, or benefit from it]
- Primary audience: [admin, end user, API user, persona, etc]
- User-visible changes:
  - [change 1]
  - [change 2]
  - [change 3]

## Release note entry
- Draft release note summary: [1-3 sentence customer-facing release note text]
- Type of change: [for example, new feature, enhancement, bug fix, deprecation]
- Breaking change or migration note: [include only if applicable; otherwise write "None identified"]

## Documentation breakdown
### Task content
- What users or admins need to do because of this feature:
- Likely procedures or workflows to document, including all steps:

### Explanation content
- What users need to understand about this feature:
- Important concepts, behavior, or workflow context:

### Reference content
- Settings, fields, parameters, permissions, API details, limits, defaults, supported environments:

### Prerequisites
- What users need to configure or set up in advance

## Known issues and limitations
- Known issues:
- Limitations:
- Unsupported scenarios:
- Rollout constraints:

## Supporting links
- Pull request / repo link:
- Design or spec:
- Confluence:
- QA / test artifacts:
- Related docs or release notes:

## Internal notes
- Open questions for documentation:
- Missing information:
- Internal-only considerations:
```

## How to fill it

- Pull `Related engineering ticket`, `Pull request / repo link`, and
  `Design or spec` from the dev workflow context (the MOB ticket and the PR the
  workflow just opened).
- Pull `Engineering SME` from the assignee of the engineering ticket.
- For any field you cannot source from the dev ticket, PR, design doc, or the
  developer — leave the bracketed placeholder text and add a matching line under
  **Internal notes → Open questions for documentation** / **Missing information**.
  Do not fabricate a plausible value.
- `User-visible changes` may have fewer or more than three bullets — list the
  real ones; if none are known yet, say so under Internal notes.
