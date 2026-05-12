#!/usr/bin/env node
// Validates a skill directory against the claude-base standard.
// Usage: node validate-skill.js <path-to-skill-dir>
// Exit codes: 0 = OK, 1 = validation failures.

import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import matter from "gray-matter";
import Ajv from "ajv";
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

  if (frontmatter["permission-tier"] >= 2) {
    const inspectPath = path.join(skillPath, "tests/inspect_eval.py");
    if (!fs.existsSync(inspectPath)) {
      errors.push("tier 2+ stable skill requires tests/inspect_eval.py");
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
