#!/usr/bin/env node
// Validates a skill directory against the claude-base standard.
// Usage: node validate-skill.js <path-to-skill-dir>
// Exit codes: 0 = OK, 1 = validation failures.

import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import matter from "gray-matter";
import Ajv from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const REQUIRED_SECTIONS = [
  "Triggers",
  "Inputs",
  "Steps",
  "Side effects",
  "Verification",
  "Failure modes",
  "Examples",
];

const skillPath = process.argv[2];
if (!skillPath) {
  console.error("Usage: validate-skill.js <skill-dir>");
  process.exit(2);
}

const skillFile = path.join(skillPath, "SKILL.md");
if (!fs.existsSync(skillFile)) {
  console.error(`FAIL: ${skillFile} not found`);
  process.exit(1);
}

const raw = fs.readFileSync(skillFile, "utf8");
const { data: frontmatter, content: body } = matter(raw);

// YAML auto-parses ISO dates to Date objects; coerce back to string so the
// JSON Schema (which uses `type: string, format: date`) validates correctly.
if (frontmatter["last-reviewed"] instanceof Date) {
  frontmatter["last-reviewed"] = frontmatter["last-reviewed"].toISOString().slice(0, 10);
}

const here = path.dirname(url.fileURLToPath(import.meta.url));
const schemaPath = path.join(here, "skill-schema.json");
const schema = JSON.parse(fs.readFileSync(schemaPath, "utf8"));

const ajv = addFormats(new Ajv({ allErrors: true, strict: false }));
const valid = ajv.validate(schema, frontmatter);

const errors = [];
if (!valid) {
  for (const e of ajv.errors || []) {
    errors.push(`frontmatter ${e.instancePath || "(root)"}: ${e.message}`);
  }
}

const dirName = path.basename(path.resolve(skillPath));
if (frontmatter.name && frontmatter.name !== dirName) {
  errors.push(`name '${frontmatter.name}' must match directory '${dirName}'`);
}

for (const heading of REQUIRED_SECTIONS) {
  if (!body.includes(`## ${heading}`)) {
    errors.push(`missing required section: ## ${heading}`);
  }
}

if (frontmatter.status === "stable") {
  const evalPath = path.join(skillPath, "tests/eval-cases.yaml");
  if (!fs.existsSync(evalPath)) {
    errors.push("stable skill requires tests/eval-cases.yaml");
  } else {
    const cases = fs.readFileSync(evalPath, "utf8");
    const count = (cases.match(/^- description:/gm) || []).length;
    if (count < 3) {
      errors.push(`stable skill requires >= 3 eval cases, found ${count}`);
    }
  }

  // Red-team eval is mandatory for every stable skill regardless of tier.
  // Covers prompt-injection, exfil, and denied-action attack classes.
  const redteamPath = path.join(skillPath, "tests/redteam-cases.yaml");
  if (!fs.existsSync(redteamPath)) {
    errors.push("stable skill requires tests/redteam-cases.yaml (>= 4 cases covering prompt-injection, indirect-injection, denied-action, exfiltration)");
  } else {
    const cases = fs.readFileSync(redteamPath, "utf8");
    const count = (cases.match(/^  - description:/gm) || []).length;
    if (count < 4) {
      errors.push(`stable skill requires >= 4 red-team cases, found ${count}`);
    }
  }

  if (frontmatter["permission-tier"] >= 2) {
    const inspectPath = path.join(skillPath, "tests/inspect_eval.py");
    if (!fs.existsSync(inspectPath)) {
      errors.push("tier 2+ stable skill requires tests/inspect_eval.py");
    } else {
      // Tier 2+ skills must include at least one negative-permission sample
      // in inspect_eval.py — i.e., a case where the agent is asked to do
      // something forbidden and is expected to refuse. We grep for the
      // `denied_action_` id prefix used in the template.
      const inspectSrc = fs.readFileSync(inspectPath, "utf8");
      if (!/denied_action_/.test(inspectSrc)) {
        errors.push(
          "tier 2+ stable skill requires at least one `denied_action_*` Sample in tests/inspect_eval.py"
        );
      }
    }
  }
}

if (frontmatter["last-reviewed"]) {
  const reviewed = new Date(frontmatter["last-reviewed"]);
  const ageDays = (Date.now() - reviewed.getTime()) / 86400000;
  if (ageDays > 365) {
    errors.push(`last-reviewed is ${Math.floor(ageDays)} days old (>365); requires re-review`);
  } else if (ageDays > 180) {
    console.warn(`WARN: last-reviewed is ${Math.floor(ageDays)} days old; review due soon`);
  }
}

if (errors.length) {
  console.error("FAIL:");
  for (const e of errors) console.error("  - " + e);
  process.exit(1);
}

console.log(
  `OK ${frontmatter.name} v${frontmatter.version} ` +
    `(category=${frontmatter.category}, tier=${frontmatter["permission-tier"]}, status=${frontmatter.status})`
);
