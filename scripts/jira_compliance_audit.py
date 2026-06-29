#!/usr/bin/env python3
"""
Server-side JIRA compliance audit for STANDARDS rules #2 and #5.

This is the install-INDEPENDENT backstop for the client-side base-tools hooks.
The hooks only fire if base-tools is installed and enabled; this audit runs in
CI and therefore catches violations regardless of what any developer had
installed when they did the work.

Two checks:

  lifecycle  (rule #5, PR-triggered)
    Given the JIRA key referenced by an AI-labeled PR, verify the issue
    reached "In Review" or beyond AND carries the AI_generated label (rule #2
    on the linked issue). Fails if the PR opened without the ticket being
    transitioned, which is exactly the metrics-blind case rule #5 exists to
    prevent.

  label  (rule #2, scheduled/nightly)
    Run the configured `label_audit_jql` to find issues created by a Claude
    tool path that are missing the AI_generated label, and report them.
    Skipped (not failed) while the JQL is the unset placeholder.

Connection comes from the environment (never from a file):
    JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN

Exit codes:
    0 — pass (no violations) or audit skipped (e.g. unset JQL)
    1 — one or more violations found
    2 — could not run (missing creds, missing/parse-broken config, JIRA error)

Usage:
    python scripts/jira_compliance_audit.py lifecycle \
        --branch "$BRANCH" --pr-title "$TITLE" --pr-body "$BODY"
    python scripts/jira_compliance_audit.py label [--root .]
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml is required. Install with:  pip install -r scripts/requirements.txt", file=sys.stderr)
    sys.exit(2)


# A real, non-zero JIRA key — same shape the client hooks enforce.
JIRA_KEY_RE = re.compile(r"[A-Z][A-Z0-9_]+-[0-9]+")
ALL_ZERO_RE = re.compile(r"^[A-Z][A-Z0-9_]+-0+$")

UNSET = "__UNSET__"

DEFAULTS = {
    "ai_label": "AI_generated",
    "label_audit_jql": UNSET,
    "label_audit_max_results": 100,
    "review_or_beyond_statuses": ["In Review", "Testing", "Accepted", "Closed"],
    "review_or_beyond_status_categories": ["done"],
}


# --- Config -------------------------------------------------------------------

class ConfigError(Exception):
    """policy/compliance-audit.yaml is present but unparsable."""


def load_config(root: Path) -> dict:
    """Load policy/compliance-audit.yaml, layered over DEFAULTS.

    A missing file is fine (defaults apply). A present-but-malformed file is a
    hard error — silently auditing with defaults would hide a typo.
    """
    cfg = dict(DEFAULTS)
    p = root / "policy" / "compliance-audit.yaml"
    if not p.exists():
        return cfg
    try:
        loaded = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        raise ConfigError(f"policy/compliance-audit.yaml is unparsable: {e}") from e
    if not isinstance(loaded, dict):
        raise ConfigError("policy/compliance-audit.yaml must be a mapping")
    cfg.update(loaded)
    # Coerce/validate here so a bad override fails with a clean ConfigError
    # (exit 2) rather than crashing later inside the JIRA client.
    try:
        cfg["label_audit_max_results"] = int(cfg["label_audit_max_results"])
    except (TypeError, ValueError) as e:
        raise ConfigError(
            f"label_audit_max_results must be an integer, got "
            f"{cfg['label_audit_max_results']!r}") from e
    return cfg


# --- JIRA key extraction ------------------------------------------------------

def extract_jira_key(*texts: str) -> str | None:
    """Return the first real (non-zero) JIRA key across the given strings.

    Mirrors the client hook precedence: branch name, then PR title, then body —
    the caller passes them in that order. All-zero placeholders are ignored.
    """
    for text in texts:
        if not text:
            continue
        for m in JIRA_KEY_RE.finditer(text):
            key = m.group(0)
            if not ALL_ZERO_RE.match(key):
                return key
    return None


# --- JIRA client --------------------------------------------------------------

class JiraError(Exception):
    pass


class JiraClient:
    """Minimal JIRA Cloud REST v3 client.

    HTTP is funneled through `self._opener(url, headers)` so tests can inject a
    fake transport instead of hitting the network. The default opener uses
    urllib with basic auth (email:token, the JIRA Cloud convention).
    """

    def __init__(self, base_url: str, email: str, token: str, opener=None):
        if not base_url or not email or not token:
            raise JiraError("JIRA_BASE_URL, JIRA_EMAIL and JIRA_API_TOKEN must all be set")
        self.base_url = base_url.rstrip("/")
        cred = base64.b64encode(f"{email}:{token}".encode()).decode()
        self._auth_header = f"Basic {cred}"
        self._opener = opener or self._urllib_opener

    @staticmethod
    def _urllib_opener(url: str, headers: dict) -> tuple[int, bytes]:
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            # An HTTP response with a non-2xx status — surface it as (status, body)
            # so _get_json can include the snippet. (HTTPError is a URLError
            # subclass, so this clause must come first.)
            return e.code, e.read()
        except urllib.error.URLError as e:
            # DNS / connection / TLS / timeout — no HTTP status. Convert to a
            # JiraError so main() exits 2 cleanly instead of dumping a traceback.
            raise JiraError(f"network error contacting JIRA: {e.reason}") from e

    def _get_json(self, path: str) -> dict:
        url = f"{self.base_url}{path}"
        headers = {"Authorization": self._auth_header, "Accept": "application/json"}
        status, body = self._opener(url, headers)
        if status != 200:
            snippet = body[:200].decode("utf-8", "replace") if body else ""
            raise JiraError(f"JIRA GET {path} -> HTTP {status}: {snippet}")
        try:
            return json.loads(body)
        except (ValueError, TypeError) as e:
            raise JiraError(f"JIRA GET {path}: invalid JSON: {e}") from e

    def get_issue(self, key: str) -> dict:
        return self._get_json(f"/rest/api/3/issue/{key}?fields=status,labels,summary")

    def search(self, jql: str, max_results: int) -> list[dict]:
        # Use the enhanced JQL search endpoint `/rest/api/3/search/jql`. The
        # legacy `/rest/api/3/search` (GET & POST) was DEPRECATED by Atlassian
        # and removed for JIRA Cloud on 2025-05-01, so the new endpoint is the
        # correct one going forward. It still returns an `issues` array.
        from urllib.parse import quote
        path = (f"/rest/api/3/search/jql?jql={quote(jql)}"
                f"&maxResults={int(max_results)}&fields=labels,summary")
        data = self._get_json(path)
        return data.get("issues", []) or []


# --- Checks -------------------------------------------------------------------

def issue_has_label(issue: dict, label: str) -> bool:
    return label in (issue.get("fields", {}).get("labels") or [])


def issue_reached_review(issue: dict, cfg: dict) -> bool:
    status = issue.get("fields", {}).get("status", {}) or {}
    name = status.get("name", "")
    cat = (status.get("statusCategory", {}) or {}).get("key", "")
    if name in set(cfg["review_or_beyond_statuses"]):
        return True
    if cat in set(cfg["review_or_beyond_status_categories"]):
        return True
    return False


def audit_lifecycle(client: JiraClient, key: str, cfg: dict) -> list[str]:
    """Rule #5 (+ rule #2 on the linked issue) for a single referenced key."""
    violations: list[str] = []
    issue = client.get_issue(key)
    if not issue_has_label(issue, cfg["ai_label"]):
        violations.append(
            f"{key}: missing the '{cfg['ai_label']}' label (STANDARDS rule #2)")
    if not issue_reached_review(issue, cfg):
        status_name = (issue.get("fields", {}).get("status", {}) or {}).get("name", "unknown")
        violations.append(
            f"{key}: status is '{status_name}', never reached In Review "
            f"although an AI-labeled PR was opened (STANDARDS rule #5)")
    return violations


def audit_labels(client: JiraClient, cfg: dict) -> tuple[str, list[str]]:
    """Rule #2 sweep. Returns (status, violations) where status is one of
    'skipped' | 'ok' | 'violations'."""
    jql = cfg["label_audit_jql"]
    if not jql or jql == UNSET:
        return "skipped", []
    issues = client.search(jql, cfg["label_audit_max_results"])
    missing = [iss.get("key", "?") for iss in issues
               if not issue_has_label(iss, cfg["ai_label"])]
    return ("violations" if missing else "ok"), missing


# --- CLI ----------------------------------------------------------------------

def _client_from_env() -> JiraClient:
    return JiraClient(
        os.environ.get("JIRA_BASE_URL", ""),
        os.environ.get("JIRA_EMAIL", ""),
        os.environ.get("JIRA_API_TOKEN", ""),
    )


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Server-side JIRA compliance audit (rules #2 & #5).")
    ap.add_argument("check", choices=["lifecycle", "label"])
    ap.add_argument("--root", default=".", help="Repo root (default: cwd)")
    ap.add_argument("--branch", default="", help="(lifecycle) branch name")
    ap.add_argument("--pr-title", default="", help="(lifecycle) PR title")
    ap.add_argument("--pr-body", default="", help="(lifecycle) PR body")
    args = ap.parse_args(argv)

    root = Path(args.root).resolve()
    try:
        cfg = load_config(root)
    except ConfigError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    try:
        client = _client_from_env()
    except JiraError as e:
        print(f"ERROR: cannot run audit: {e}", file=sys.stderr)
        return 2

    try:
        if args.check == "lifecycle":
            key = extract_jira_key(args.branch, args.pr_title, args.pr_body)
            if not key:
                # No real key anywhere — rule #1 territory, not this audit's job.
                print("No real JIRA key found in branch/title/body; nothing to audit "
                      "(rule #1 covers missing keys).")
                return 0
            violations = audit_lifecycle(client, key, cfg)
            if violations:
                print(f"FAIL: {key} — AI-work traceability violations:")
                for v in violations:
                    print(f"  - {v}")
                return 1
            print(f"OK: {key} carries '{cfg['ai_label']}' and reached In Review or beyond.")
            return 0

        # label
        status, missing = audit_labels(client, cfg)
        if status == "skipped":
            print("SKIPPED: label_audit_jql is unset (__UNSET__) — configure it in "
                  "policy/compliance-audit.yaml to enable the rule #2 sweep.")
            return 0
        if status == "violations":
            print(f"FAIL: {len(missing)} issue(s) missing the '{cfg['ai_label']}' label (rule #2):")
            for k in missing:
                print(f"  - {k}")
            return 1
        print(f"OK: all audited issues carry the '{cfg['ai_label']}' label.")
        return 0
    except JiraError as e:
        print(f"ERROR: JIRA request failed: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
