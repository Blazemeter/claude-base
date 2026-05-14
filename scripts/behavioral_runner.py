#!/usr/bin/env python3
"""Behavioral test runner for skills.

Walks plugins/<plugin>/skills/<name>/tests/cases.yaml, lints the schema, and
(if ANTHROPIC_API_KEY is set) sends each prompt to the Anthropic API with the
skill's SKILL.md as system context. Assertions check the response text.

This tests *whether the skill body steers Claude correctly*, not Claude Code's
plugin auto-invocation (which would require running CC end-to-end). It catches
~80% of skill regressions for ~0% of the engineering cost.

Test case schema:

    skill: <plugin>/<skill-name>          # e.g. base-tools/summarize-pr
    cases:
      - name: unique-test-name            # required
        prompt: "user-facing prompt"      # required
        expected:                         # required
          response_must_contain: [..]     # all substrings must appear
          response_must_not_contain: [..] # none of these may appear
        setup: {..}                       # optional; reserved for future use

Usage:
    python scripts/behavioral_runner.py --lint                # schema only, no API
    python scripts/behavioral_runner.py                       # run all (needs key)
    python scripts/behavioral_runner.py --skill base-tools/summarize-pr  # one skill
    python scripts/behavioral_runner.py --model claude-sonnet-4-6        # override

Exit codes:
    0 — all cases passed (or --lint clean)
    1 — at least one case failed / lint error
    2 — environment problem (no pyyaml, no API key when running, etc.)

Requirements:
    pip install -r scripts/requirements.txt          # for --lint
    pip install -r scripts/requirements-eval.txt     # for API runs (anthropic SDK)
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml required. pip install -r scripts/requirements.txt",
          file=sys.stderr)
    sys.exit(2)


DEFAULT_MODEL = "claude-sonnet-4-6"
REPO_ROOT = Path(__file__).resolve().parent.parent


@dataclass
class Case:
    name: str
    prompt: str
    must_contain: list[str] = field(default_factory=list)
    must_not_contain: list[str] = field(default_factory=list)


@dataclass
class Suite:
    skill_path: Path           # plugins/<plugin>/skills/<name>
    skill_id: str              # <plugin>/<name>
    cases_file: Path
    cases: list[Case]


# --- Discovery & lint ---------------------------------------------------------

def discover_suites(root: Path, only_skill: str | None) -> tuple[list[Suite], list[str]]:
    """Walk plugins/*/skills/*/tests/cases.yaml. Returns (suites, errors).

    Errors are accumulated across all suites rather than raising on the first —
    a CI run should report every broken cases.yaml at once, not one per push.
    """
    suites: list[Suite] = []
    errors: list[str] = []
    for skill_dir in sorted((root / "plugins").glob("*/skills/*")):
        if not skill_dir.is_dir():
            continue
        cases_file = skill_dir / "tests" / "cases.yaml"
        if not cases_file.exists():
            continue
        plugin = skill_dir.parent.parent.name
        skill = skill_dir.name
        skill_id = f"{plugin}/{skill}"
        if only_skill and only_skill != skill_id:
            continue
        try:
            suites.append(parse_suite(skill_dir, cases_file, skill_id))
        except ValueError as e:
            errors.append(str(e))
    return suites, errors


def parse_suite(skill_dir: Path, cases_file: Path, skill_id: str) -> Suite:
    try:
        data = yaml.safe_load(cases_file.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        raise ValueError(f"{cases_file}: invalid YAML: {e}") from e
    if not isinstance(data, dict):
        raise ValueError(f"{cases_file}: top level must be a mapping")
    # Optional `skill:` field — if present, it must match the discovered path,
    # so a renamed/moved skill doesn't silently desync from its tests.
    declared = data.get("skill")
    if declared is not None and str(declared) != skill_id:
        raise ValueError(
            f"{cases_file}: 'skill' field {declared!r} does not match the "
            f"discovered skill path {skill_id!r} — fix the field or move the file"
        )
    raw_cases = data.get("cases")
    if not isinstance(raw_cases, list) or not raw_cases:
        raise ValueError(f"{cases_file}: 'cases' must be a non-empty list")
    cases: list[Case] = []
    seen: set[str] = set()
    for i, raw in enumerate(raw_cases):
        if not isinstance(raw, dict):
            raise ValueError(f"{cases_file}: cases[{i}] must be a mapping")
        name = str(raw.get("name", "")).strip()
        if not name:
            raise ValueError(f"{cases_file}: cases[{i}] missing 'name'")
        if name in seen:
            raise ValueError(f"{cases_file}: duplicate case name {name!r}")
        seen.add(name)
        prompt = str(raw.get("prompt", "")).strip()
        if not prompt:
            raise ValueError(f"{cases_file}: case {name!r} missing 'prompt'")
        exp = raw.get("expected") or {}
        if not isinstance(exp, dict):
            raise ValueError(f"{cases_file}: case {name!r} 'expected' must be a mapping")
        must_contain = [str(s) for s in (exp.get("response_must_contain") or [])]
        must_not_contain = [str(s) for s in (exp.get("response_must_not_contain") or [])]
        if not must_contain and not must_not_contain:
            raise ValueError(
                f"{cases_file}: case {name!r} has no assertions "
                f"(need response_must_contain and/or response_must_not_contain)"
            )
        cases.append(Case(name=name, prompt=prompt,
                          must_contain=must_contain,
                          must_not_contain=must_not_contain))
    return Suite(skill_path=skill_dir, skill_id=skill_id,
                 cases_file=cases_file, cases=cases)


# --- Execution ----------------------------------------------------------------

def run_case(client, model: str, system_prompt: str, case: Case) -> tuple[bool, str]:
    """Returns (passed, response_text_or_error)."""
    try:
        resp = client.messages.create(
            model=model,
            max_tokens=2048,
            system=system_prompt,
            messages=[{"role": "user", "content": case.prompt}],
        )
    except Exception as e:  # noqa: BLE001 — surface any SDK / network error
        return False, f"API error: {e}"
    # Extract text from the response
    text_parts = []
    for block in resp.content:
        if getattr(block, "type", None) == "text":
            text_parts.append(block.text)
    text = "\n".join(text_parts)

    for needle in case.must_contain:
        if needle not in text:
            return False, f"missing required substring: {needle!r}\n--- response ---\n{text}"
    for needle in case.must_not_contain:
        if needle in text:
            return False, f"contained forbidden substring: {needle!r}\n--- response ---\n{text}"
    return True, text


# --- Main ---------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Behavioral test runner for skills.")
    ap.add_argument("--root", type=Path, default=REPO_ROOT, help="Repo root")
    ap.add_argument("--lint", action="store_true",
                    help="Validate cases.yaml structure only; do not call the API")
    ap.add_argument("--skill", type=str, default=None,
                    help="Run only this skill (form: <plugin>/<skill-name>)")
    ap.add_argument("--model", type=str, default=DEFAULT_MODEL,
                    help=f"Model id (default: {DEFAULT_MODEL})")
    args = ap.parse_args()

    suites, errors = discover_suites(args.root, args.skill)
    if errors:
        for err in errors:
            print(f"LINT ERROR: {err}", file=sys.stderr)
        print(f"\n{len(errors)} broken cases.yaml file(s).", file=sys.stderr)
        return 1

    if not suites:
        if args.skill:
            print(f"No test suite found for skill {args.skill!r}.")
        else:
            print("No test suites found under plugins/*/skills/*/tests/cases.yaml.")
        return 0

    if args.lint:
        for s in suites:
            print(f"  [LINT] {s.skill_id} — {len(s.cases)} case(s) OK ({s.cases_file.relative_to(args.root)})")
        print(f"\nLint clean: {sum(len(s.cases) for s in suites)} cases across {len(suites)} suite(s).")
        return 0

    # API mode — need key + SDK
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ERROR: ANTHROPIC_API_KEY not set. Use --lint for schema-only mode.",
              file=sys.stderr)
        return 2
    try:
        from anthropic import Anthropic  # type: ignore
    except ImportError:
        print("ERROR: anthropic SDK required. pip install -r scripts/requirements-eval.txt",
              file=sys.stderr)
        return 2

    client = Anthropic(api_key=api_key)

    total = 0
    failed = 0
    for s in suites:
        skill_md = (s.skill_path / "SKILL.md").read_text(encoding="utf-8")
        print(f"\n=== {s.skill_id} ({len(s.cases)} cases) ===")
        for case in s.cases:
            total += 1
            ok, detail = run_case(client, args.model, skill_md, case)
            if ok:
                print(f"  [PASS] {case.name}")
            else:
                failed += 1
                print(f"  [FAIL] {case.name}\n    {detail}")

    print(f"\n{total - failed}/{total} passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
