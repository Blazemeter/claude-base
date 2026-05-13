#!/usr/bin/env node
// Validates community-allowlist.yaml:
//   1. Every approved entry has a non-placeholder pinned-ref.
//   2. The pinned-ref looks like a 40-char commit SHA (not a tag or branch).
//   3. If GH_TOKEN is available and the repo is on GitHub, the SHA exists
//      in the upstream repo's git history.
//   4. `reviewed` is within the last 365 days.
//
// A skill is not allowed to depend on a community framework that is not in
// the `approved:` list. This validator only checks the allowlist itself;
// the skill-side check (which community deps the skill imports) is performed
// in check-permissions.js once a `community-deps:` field is declared.
//
// Usage: node check-community-pins.js <path-to-community-allowlist.yaml>

import fs from "node:fs";
import path from "node:path";
import https from "node:https";
import yaml from "js-yaml";

const allowlistPath = process.argv[2];
if (!allowlistPath) {
  console.error("Usage: check-community-pins.js <path-to-community-allowlist.yaml>");
  process.exit(2);
}

if (!fs.existsSync(allowlistPath)) {
  console.error(`FAIL: ${allowlistPath} not found`);
  process.exit(1);
}

const doc = yaml.load(fs.readFileSync(allowlistPath, "utf8")) || {};
const approved = doc.approved || [];

const errors = [];
const warnings = [];

const SHA_RE = /^[0-9a-f]{40}$/i;
const PLACEHOLDER_RE = /^<.*>$/;

const ghToken = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;

const ghHead = (owner, repo, sha) =>
  new Promise((resolve) => {
    const req = https.request(
      {
        host: "api.github.com",
        path: `/repos/${owner}/${repo}/commits/${sha}`,
        method: "HEAD",
        headers: {
          "User-Agent": "claude-base-pins-check",
          Accept: "application/vnd.github+json",
          ...(ghToken ? { Authorization: `Bearer ${ghToken}` } : {}),
        },
      },
      (res) => {
        res.resume();
        resolve(res.statusCode === 200);
      }
    );
    req.on("error", () => resolve(false));
    req.end();
  });

const parseRepo = (url) => {
  const m = /github\.com[/:]([^/]+)\/([^/.]+)/.exec(url || "");
  return m ? { owner: m[1], repo: m[2] } : null;
};

const checks = [];

for (const entry of approved) {
  const label = entry.name || "(unnamed)";
  const ref = entry["pinned-ref"];

  if (!ref || PLACEHOLDER_RE.test(String(ref))) {
    errors.push(`${label}: pinned-ref is a placeholder ('${ref}'). Pin a reviewed SHA.`);
    continue;
  }

  if (!SHA_RE.test(String(ref))) {
    errors.push(`${label}: pinned-ref '${ref}' is not a 40-char commit SHA (tags/branches are not allowed).`);
    continue;
  }

  if (entry.reviewed) {
    const reviewed = new Date(entry.reviewed);
    const ageDays = (Date.now() - reviewed.getTime()) / 86400000;
    if (Number.isFinite(ageDays) && ageDays > 365) {
      errors.push(`${label}: reviewed ${Math.floor(ageDays)} days ago (>365). Re-review required.`);
    } else if (Number.isFinite(ageDays) && ageDays > 180) {
      warnings.push(`${label}: reviewed ${Math.floor(ageDays)} days ago; review due soon.`);
    }
  } else {
    warnings.push(`${label}: no 'reviewed' date.`);
  }

  const repo = parseRepo(entry.repo);
  if (repo) {
    checks.push(
      ghHead(repo.owner, repo.repo, ref).then((ok) => {
        if (!ok) {
          errors.push(
            `${label}: pinned SHA ${ref} not found in ${repo.owner}/${repo.repo} (or API unauthenticated). ` +
              `Set GH_TOKEN to enable upstream verification.`
          );
        }
      })
    );
  } else {
    warnings.push(`${label}: repo '${entry.repo}' is not on GitHub; cannot verify SHA upstream.`);
  }
}

await Promise.all(checks);

for (const w of warnings) console.warn(`WARN: ${w}`);

if (errors.length) {
  console.error("FAIL:");
  for (const e of errors) console.error("  - " + e);
  process.exit(1);
}

console.log(`OK community-allowlist: ${approved.length} approved entries pinned by SHA`);
