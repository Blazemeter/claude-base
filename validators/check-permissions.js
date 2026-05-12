#!/usr/bin/env node
// Parses SKILL.md Steps + tests/permission-test.yaml and asserts every bash
// pattern referenced in Steps matches an allowed pattern and none match a denied
// pattern. This is a static check; runtime enforcement happens via Claude Code
// settings.json deny rules.
// Usage: node check-permissions.js <skill-dir>

import fs from "node:fs";
import path from "node:path";
import matter from "gray-matter";
import yaml from "js-yaml";

const skillPath = process.argv[2];
if (!skillPath) {
  console.error("Usage: check-permissions.js <skill-dir>");
  process.exit(2);
}

const skillRaw = fs.readFileSync(path.join(skillPath, "SKILL.md"), "utf8");
const { data: fm, content: body } = matter(skillRaw);

const permPath = path.join(skillPath, "tests/permission-test.yaml");
if (!fs.existsSync(permPath)) {
  console.error("FAIL: tests/permission-test.yaml not found");
  process.exit(1);
}
const perm = yaml.load(fs.readFileSync(permPath, "utf8"));

if (perm.declared_tier !== fm["permission-tier"]) {
  console.error(
    `FAIL: declared_tier ${perm.declared_tier} != frontmatter permission-tier ${fm["permission-tier"]}`
  );
  process.exit(1);
}

const stepsMatch = body.match(/## Steps\s+([\s\S]*?)(?=\n## |\n$)/);
const stepsBody = stepsMatch ? stepsMatch[1] : "";
const codeBlocks = [...stepsBody.matchAll(/`([^`]+)`/g)].map((m) => m[1]);

const globToRegex = (g) =>
  new RegExp("^" + g.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$");

const allowed = (perm.allowed_bash_patterns || []).map(globToRegex);
const denied = (perm.denied_bash_patterns || []).map(globToRegex);

const errors = [];
for (const cmd of codeBlocks) {
  const isBashy = /^(git|gh|aws|kubectl|mvn|npm|yarn|bun|docker|psql|mongo|curl|rm|mv|cp)\b/.test(cmd);
  if (!isBashy) continue;
  if (denied.some((r) => r.test(cmd))) errors.push(`DENIED pattern matched: ${cmd}`);
  if (!allowed.some((r) => r.test(cmd))) errors.push(`bash command not in allowed_bash_patterns: ${cmd}`);
}

if (errors.length) {
  console.error("FAIL:");
  for (const e of errors) console.error("  - " + e);
  process.exit(1);
}

console.log(`OK permission check (tier ${perm.declared_tier}, ${codeBlocks.length} bash refs)`);
