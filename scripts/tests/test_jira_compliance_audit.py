"""Regression tests for scripts/jira_compliance_audit.py.

No network: a fake opener feeds canned JIRA REST responses into JiraClient.
Stdlib unittest only.

Run from repo root:

    python -m unittest discover -s scripts/tests -t scripts -v
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
SCRIPTS_DIR = THIS_DIR.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import jira_compliance_audit as audit  # noqa: E402


# --- Helpers ------------------------------------------------------------------

def make_opener(routes: dict):
    """Build a fake opener. `routes` maps a substring of the URL path to a
    (status, json-able-body) tuple. First matching substring wins."""
    def opener(url: str, headers: dict):
        for needle, (status, body) in routes.items():
            if needle in url:
                return status, json.dumps(body).encode("utf-8")
        return 404, b'{"errorMessages":["not found"]}'
    return opener


def issue(key: str, status_name: str, status_cat: str, labels: list[str]) -> dict:
    return {
        "key": key,
        "fields": {
            "summary": "x",
            "labels": labels,
            "status": {"name": status_name, "statusCategory": {"key": status_cat}},
        },
    }


def client_with(routes: dict) -> audit.JiraClient:
    return audit.JiraClient("https://jira.example.com", "a@b.com", "tok",
                            opener=make_opener(routes))


# --- Key extraction -----------------------------------------------------------

class ExtractKeyTests(unittest.TestCase):
    def test_branch_precedence(self):
        self.assertEqual(
            audit.extract_jira_key("MOB-123-foo", "title MOB-999", "body"),
            "MOB-123")

    def test_falls_through_to_title_then_body(self):
        self.assertEqual(audit.extract_jira_key("feature/foo", "MOB-77: x", ""), "MOB-77")
        self.assertEqual(audit.extract_jira_key("foo", "no key", "see MOB-5"), "MOB-5")

    def test_all_zero_rejected(self):
        self.assertIsNone(audit.extract_jira_key("MOB-00000", "MOB-0", ""))

    def test_none_when_absent(self):
        self.assertIsNone(audit.extract_jira_key("just-a-branch", "", ""))


# --- Predicates ---------------------------------------------------------------

class PredicateTests(unittest.TestCase):
    def setUp(self):
        self.cfg = dict(audit.DEFAULTS)

    def test_label_presence(self):
        self.assertTrue(audit.issue_has_label(issue("M-1", "Open", "new", ["AI_generated"]), "AI_generated"))
        self.assertFalse(audit.issue_has_label(issue("M-1", "Open", "new", []), "AI_generated"))

    def test_reached_review_by_name(self):
        self.assertTrue(audit.issue_reached_review(issue("M-1", "In Review", "indeterminate", []), self.cfg))

    def test_reached_review_by_done_category(self):
        # A custom "Cancelled" done-status not in the name list still counts via category.
        self.assertTrue(audit.issue_reached_review(issue("M-1", "Cancelled", "done", []), self.cfg))

    def test_not_reached_review_when_todo(self):
        self.assertFalse(audit.issue_reached_review(issue("M-1", "Open", "new", []), self.cfg))

    def test_in_progress_is_not_review(self):
        self.assertFalse(audit.issue_reached_review(issue("M-1", "In Progress", "indeterminate", []), self.cfg))


# --- Lifecycle audit ----------------------------------------------------------

class LifecycleAuditTests(unittest.TestCase):
    def setUp(self):
        self.cfg = dict(audit.DEFAULTS)

    def test_compliant_issue_no_violations(self):
        c = client_with({"/issue/MOB-1": (200, issue("MOB-1", "In Review", "indeterminate", ["AI_generated"]))})
        self.assertEqual(audit.audit_lifecycle(c, "MOB-1", self.cfg), [])

    def test_missing_label_flagged(self):
        c = client_with({"/issue/MOB-2": (200, issue("MOB-2", "In Review", "indeterminate", []))})
        v = audit.audit_lifecycle(c, "MOB-2", self.cfg)
        self.assertTrue(any("rule #2" in x for x in v), v)

    def test_not_reached_review_flagged(self):
        c = client_with({"/issue/MOB-3": (200, issue("MOB-3", "Open", "new", ["AI_generated"]))})
        v = audit.audit_lifecycle(c, "MOB-3", self.cfg)
        self.assertTrue(any("rule #5" in x for x in v), v)

    def test_both_violations(self):
        c = client_with({"/issue/MOB-4": (200, issue("MOB-4", "Open", "new", []))})
        v = audit.audit_lifecycle(c, "MOB-4", self.cfg)
        self.assertEqual(len(v), 2, v)

    def test_http_error_raises(self):
        c = client_with({"/issue/MOB-9": (404, {"errorMessages": ["x"]})})
        with self.assertRaises(audit.JiraError):
            audit.audit_lifecycle(c, "MOB-9", self.cfg)


# --- Label audit --------------------------------------------------------------

class LabelAuditTests(unittest.TestCase):
    def test_skipped_when_jql_unset(self):
        cfg = dict(audit.DEFAULTS)  # label_audit_jql == __UNSET__
        c = client_with({})
        status, missing = audit.audit_labels(c, cfg)
        self.assertEqual(status, "skipped")
        self.assertEqual(missing, [])

    def test_violations_listed(self):
        cfg = dict(audit.DEFAULTS, label_audit_jql="reporter = claude")
        c = client_with({"/search/jql": (200, {"issues": [
            issue("MOB-10", "Open", "new", []),
            issue("MOB-11", "Open", "new", ["AI_generated"]),
            issue("MOB-12", "Open", "new", []),
        ]})})
        status, missing = audit.audit_labels(c, cfg)
        self.assertEqual(status, "violations")
        self.assertEqual(missing, ["MOB-10", "MOB-12"])

    def test_ok_when_all_labeled(self):
        cfg = dict(audit.DEFAULTS, label_audit_jql="reporter = claude")
        c = client_with({"/search/jql": (200, {"issues": [
            issue("MOB-10", "Open", "new", ["AI_generated"]),
        ]})})
        status, missing = audit.audit_labels(c, cfg)
        self.assertEqual(status, "ok")
        self.assertEqual(missing, [])


# --- Config -------------------------------------------------------------------

class ConfigTests(unittest.TestCase):
    def test_missing_file_uses_defaults(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = audit.load_config(Path(td))
            self.assertEqual(cfg["ai_label"], "AI_generated")
            self.assertEqual(cfg["label_audit_jql"], audit.UNSET)

    def test_override_merges_over_defaults(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "policy").mkdir()
            (root / "policy" / "compliance-audit.yaml").write_text(
                'ai_label: AI_made\nlabel_audit_jql: "reporter = bot"\n', encoding="utf-8")
            cfg = audit.load_config(root)
            self.assertEqual(cfg["ai_label"], "AI_made")
            self.assertEqual(cfg["label_audit_jql"], "reporter = bot")
            # untouched key keeps its default
            self.assertEqual(cfg["pr_ai_label"], "ai-generated")

    def test_malformed_config_raises(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "policy").mkdir()
            (root / "policy" / "compliance-audit.yaml").write_text("ai_label: [unbalanced\n", encoding="utf-8")
            with self.assertRaises(audit.ConfigError):
                audit.load_config(root)


# --- Client construction ------------------------------------------------------

class ClientTests(unittest.TestCase):
    def test_missing_creds_raises(self):
        with self.assertRaises(audit.JiraError):
            audit.JiraClient("", "", "")

    def test_search_url_encodes_jql(self):
        captured = {}
        def opener(url, headers):
            captured["url"] = url
            return 200, json.dumps({"issues": []}).encode()
        c = audit.JiraClient("https://j.example.com", "a@b.com", "t", opener=opener)
        c.search("project = MOB AND labels != AI_generated", 50)
        self.assertIn("/rest/api/3/search/jql?jql=", captured["url"])
        self.assertNotIn(" ", captured["url"])  # spaces must be percent-encoded


class CLITests(unittest.TestCase):
    """main() routing + exit codes, with the JIRA client patched out."""

    def _run(self, argv, fake_client=None, raise_creds=False):
        orig = audit._client_from_env
        def fake():
            if raise_creds:
                raise audit.JiraError("creds missing")
            return fake_client
        audit._client_from_env = fake
        try:
            return audit.main(argv)
        finally:
            audit._client_from_env = orig

    def test_lifecycle_compliant_returns_0(self):
        c = client_with({"/issue/MOB-1": (200, issue("MOB-1", "In Review", "indeterminate", ["AI_generated"]))})
        self.assertEqual(self._run(["lifecycle", "--branch", "MOB-1-foo"], c), 0)

    def test_lifecycle_violation_returns_1(self):
        c = client_with({"/issue/MOB-2": (200, issue("MOB-2", "Open", "new", []))})
        self.assertEqual(self._run(["lifecycle", "--branch", "MOB-2-foo"], c), 1)

    def test_lifecycle_no_key_returns_0(self):
        c = client_with({})
        self.assertEqual(self._run(["lifecycle", "--branch", "just-a-branch"], c), 0)

    def test_missing_creds_returns_2(self):
        self.assertEqual(self._run(["lifecycle", "--branch", "MOB-1"], raise_creds=True), 2)

    def test_label_skipped_returns_0(self):
        # default config has __UNSET__ jql; runs from a temp root with no policy file
        with tempfile.TemporaryDirectory() as td:
            c = client_with({})
            self.assertEqual(self._run(["label", "--root", td], c), 0)


if __name__ == "__main__":
    unittest.main()
