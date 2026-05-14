#!/usr/bin/env python3
"""
Validate a Claude Code plugin marketplace.

Layered checks, fail-fast:

  Schema
    - marketplace.json: required fields (name, owner, plugins[]); kebab-case names;
      plugin source paths resolve.
    - plugin.json: required fields; name matches its directory.
    - SKILL.md frontmatter: required `description`; optional `name` must match dir.
    - command/agent .md frontmatter: required `description`; agent must declare `name`.
    - hooks.json: known event names, referenced scripts exist, scripts have a shebang.

  Standards
    - Skill dir name == frontmatter name (when set).
    - Agent file stem == frontmatter name.
    - SKILL.md soft cap: 500 lines (progressive disclosure rule of thumb).
    - No human-centric files inside skill dirs (README.md, INSTALLATION.md, etc.).
    - Hook scripts have a shebang line.
    - Description length >= 50 chars (warn if shorter — triggering depends on it).

  Tool policy
    - Every tool in a skill/command `allowed-tools` or agent `tools` frontmatter
      must appear in policy/allowed-tools.yaml `allowed:`, OR be granted by an
      `exceptions:` entry for that artifact, OR be an MCP tool (mcp__*).
    - Anything in `forbidden:` fails regardless of allowlist / exceptions.
    - Missing policy file => warning. Malformed policy => ERROR.

  Security (smoke)
    - Scans every tracked text file for high-signal secret patterns
      (AWS keys, private key headers, Slack/GitHub/GitLab tokens, Google API keys).
    - This is NOT a substitute for gitleaks — it's a fast in-repo gate so contributors
      catch obvious leaks before CI does.

Exit code:
    0 — all checks passed
    1 — one or more errors (warnings included only with --strict)
    2 — could not run (missing pyyaml, no repo root, etc.)

Usage:
    python scripts/validate.py [--root .] [--strict] [--quiet]

Install requirements once:
    pip install -r scripts/requirements.txt
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Iterable

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml is required. Install with:  pip install -r scripts/requirements.txt", file=sys.stderr)
    sys.exit(2)


# --- Constants ----------------------------------------------------------------

KEBAB = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")

KNOWN_MODELS = {
    "claude-opus-4-7", "claude-opus-4-6", "claude-opus-4-5",
    "claude-sonnet-4-6", "claude-sonnet-4-5",
    "claude-haiku-4-5", "claude-haiku-4-5-20251001",
    # Inherit-from-parent sentinel:
    "inherit",
}

KNOWN_HOOK_EVENTS = {
    "PreToolUse", "PostToolUse",
    "PreCommand", "PostCommand",
    "PreFile", "PostFile",
    "PreSkill", "PostSkill",
    "PostSubagentSpawn",
}

# High-signal secret patterns. Keep this short — gitleaks (CI) does the heavy lifting.
SECRET_PATTERNS = [
    (r"AKIA[0-9A-Z]{16}", "AWS access key id"),
    (r"-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----", "private key header"),
    (r"xox[baprs]-[0-9a-zA-Z-]{10,}", "Slack token"),
    (r"glpat-[0-9A-Za-z_-]{20,}", "GitLab PAT"),
    (r"ghp_[0-9A-Za-z]{36,}", "GitHub PAT"),
    (r"AIza[0-9A-Za-z_-]{35}", "Google API key"),
]

MAX_SKILL_LINES = 500
MIN_DESCRIPTION_CHARS = 50
SKILL_FORBIDDEN_FILES = {"README.md", "INSTALLATION.md", "INSTALL.md", "CHANGELOG.md"}

SCAN_SKIP_DIRS = {".git", ".idea", ".vscode", "node_modules", ".venv", "__pycache__", ".mypy_cache"}
SCAN_BINARY_EXT = {
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf",
    ".woff", ".woff2", ".ttf", ".otf",
    ".zip", ".tar", ".gz", ".bz2", ".7z",
    ".pyc", ".class", ".jar",
}

# Files that legitimately contain literal secret patterns (validator source,
# policy file, secret-block hook). Excluded from the smoke secret scan to
# avoid self-reporting. Paths are relative to the repo root.
SCAN_EXCLUDE_FILES = {
    "scripts/validate.py",
    "scripts/tests/test_validate.py",
    "plugins/base-tools/hooks/block-secrets-on-write.sh",
}

ERROR = "ERROR"
WARN = "WARN"

# An issue: (severity, file, line, message)
Issue = tuple[str, str, int, str]


# --- Helpers ------------------------------------------------------------------

_FM_CLOSE_RE = re.compile(r"\n---(?:\r?\n|\Z)")


def load_frontmatter(path: Path) -> dict:
    """Parse YAML frontmatter from a markdown file. Returns {} if missing.

    Accepts LF and CRLF line endings, and a closing `---` either followed by
    a newline or at end-of-file (some editors save without a trailing newline).
    """
    text = path.read_text(encoding="utf-8")
    if text.startswith("﻿"):
        text = text[1:]  # strip a single BOM if present
    if not (text.startswith("---\n") or text.startswith("---\r\n")):
        return {}
    opener_len = 4 if text.startswith("---\n") else 5
    m = _FM_CLOSE_RE.search(text, opener_len - 1)
    if m is None:
        raise ValueError("frontmatter opened with '---' but no closing '---'")
    fm_text = text[opener_len:m.start()]
    try:
        data = yaml.safe_load(fm_text)
    except yaml.YAMLError as e:
        raise ValueError(f"YAML parse error in frontmatter: {e}") from e
    return data or {}


def rel(root: Path, p: Path | str) -> str:
    try:
        return str(Path(p).resolve().relative_to(root)).replace("\\", "/")
    except Exception:
        return str(p)


# --- Validators ---------------------------------------------------------------

def validate_marketplace(root: Path) -> list[Issue]:
    issues: list[Issue] = []
    mp = root / ".claude-plugin" / "marketplace.json"
    if not mp.exists():
        return [(ERROR, str(mp), 0, "missing .claude-plugin/marketplace.json")]
    try:
        data = json.loads(mp.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [(ERROR, str(mp), e.lineno or 0, f"invalid JSON: {e.msg}")]

    for field in ("name", "owner", "plugins"):
        if field not in data:
            issues.append((ERROR, str(mp), 0, f"missing required field: {field}"))

    name = data.get("name", "")
    if name and not KEBAB.match(name):
        issues.append((ERROR, str(mp), 0, f"'name' must be kebab-case, got: {name!r}"))

    owner = data.get("owner")
    if isinstance(owner, dict) and "name" not in owner:
        issues.append((ERROR, str(mp), 0, "'owner.name' is required"))

    plugin_root = data.get("metadata", {}).get("pluginRoot", "")
    for plugin in data.get("plugins", []) or []:
        if not isinstance(plugin, dict):
            issues.append((ERROR, str(mp), 0, "each entry of 'plugins' must be an object"))
            continue
        pname = plugin.get("name", "")
        psrc = plugin.get("source")
        if not pname:
            issues.append((ERROR, str(mp), 0, "plugin entry missing 'name'"))
        elif not KEBAB.match(pname):
            issues.append((ERROR, str(mp), 0, f"plugin '{pname}': name not kebab-case"))
        if isinstance(psrc, str):
            full = (root / plugin_root / psrc).resolve() if plugin_root else (root / psrc).resolve()
            if not full.exists():
                issues.append((ERROR, str(mp), 0, f"plugin '{pname}': source path missing: {rel(root, full)}"))
    return issues


def validate_plugin(root: Path, plugin_dir: Path) -> list[Issue]:
    issues: list[Issue] = []
    manifest = plugin_dir / ".claude-plugin" / "plugin.json"
    if not manifest.exists():
        return [(ERROR, str(manifest), 0, "missing .claude-plugin/plugin.json")]
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [(ERROR, str(manifest), e.lineno or 0, f"invalid JSON: {e.msg}")]

    if "name" not in data:
        issues.append((ERROR, str(manifest), 0, "missing required field: name"))
    if "description" not in data:
        issues.append((WARN, str(manifest), 0, "missing recommended field: description"))

    name = data.get("name", "")
    if name and not KEBAB.match(name):
        issues.append((ERROR, str(manifest), 0, f"name not kebab-case: {name!r}"))
    if name and name != plugin_dir.name:
        issues.append((ERROR, str(manifest), 0, f"name {name!r} must match directory {plugin_dir.name!r}"))
    return issues


def validate_skill(root: Path, skill_dir: Path) -> list[Issue]:
    issues: list[Issue] = []
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        return [(ERROR, str(skill_md), 0, "missing SKILL.md")]
    try:
        fm = load_frontmatter(skill_md)
    except ValueError as e:
        return [(ERROR, str(skill_md), 0, str(e))]
    if not fm:
        return [(ERROR, str(skill_md), 0, "missing YAML frontmatter")]

    if "description" not in fm:
        issues.append((ERROR, str(skill_md), 0, "frontmatter missing required field: description"))
    elif len(str(fm["description"])) < MIN_DESCRIPTION_CHARS:
        issues.append((WARN, str(skill_md), 0, f"description is short ({len(str(fm['description']))} chars); be specific about triggers"))

    name = fm.get("name")
    if name and not KEBAB.match(str(name)):
        issues.append((ERROR, str(skill_md), 0, f"name not kebab-case: {name!r}"))
    if name and str(name) != skill_dir.name:
        issues.append((ERROR, str(skill_md), 0, f"name {name!r} must match directory {skill_dir.name!r}"))

    line_count = skill_md.read_text(encoding="utf-8").count("\n")
    if line_count > MAX_SKILL_LINES:
        issues.append((WARN, str(skill_md), 0, f"SKILL.md is {line_count} lines (recommended <{MAX_SKILL_LINES}); split into references/"))

    for forbidden in SKILL_FORBIDDEN_FILES:
        bad = skill_dir / forbidden
        if bad.exists():
            issues.append((WARN, str(bad), 0, f"human-centric file {forbidden!r} should not live inside a skill dir"))
    return issues


def validate_command_or_agent(file_path: Path, kind: str) -> list[Issue]:
    issues: list[Issue] = []
    try:
        fm = load_frontmatter(file_path)
    except ValueError as e:
        return [(ERROR, str(file_path), 0, str(e))]
    if not fm:
        return [(ERROR, str(file_path), 0, "missing YAML frontmatter")]
    if "description" not in fm:
        issues.append((ERROR, str(file_path), 0, "frontmatter missing required field: description"))

    if kind == "agent":
        if "name" not in fm:
            issues.append((ERROR, str(file_path), 0, "agent frontmatter missing required field: name"))
        else:
            name = str(fm["name"])
            if not KEBAB.match(name):
                issues.append((ERROR, str(file_path), 0, f"name not kebab-case: {name!r}"))
            if name != file_path.stem:
                issues.append((ERROR, str(file_path), 0, f"name {name!r} must match file stem {file_path.stem!r}"))
        if "model" in fm and str(fm["model"]) not in KNOWN_MODELS:
            issues.append((WARN, str(file_path), 0, f"unknown model {fm['model']!r}; consider one of {sorted(KNOWN_MODELS)}"))
    return issues


def validate_hooks(plugin_dir: Path) -> list[Issue]:
    issues: list[Issue] = []
    hooks_json = plugin_dir / "hooks.json"
    if not hooks_json.exists():
        return []  # hooks are optional
    try:
        data = json.loads(hooks_json.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [(ERROR, str(hooks_json), e.lineno or 0, f"invalid JSON: {e.msg}")]
    hooks = data.get("hooks", {}) if isinstance(data, dict) else {}
    for event, entries in hooks.items():
        if event.startswith("_"):
            continue
        if event not in KNOWN_HOOK_EVENTS:
            issues.append((WARN, str(hooks_json), 0, f"unknown hook event: {event}"))
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            for h in entry.get("hooks", []) or []:
                cmd = h.get("command", "") if isinstance(h, dict) else ""
                if not cmd:
                    continue
                # Resolve ${CLAUDE_PLUGIN_ROOT}/... refs and verify the script exists
                m = re.search(r"\$\{CLAUDE_PLUGIN_ROOT\}([^\s\"']+)", cmd)
                if m:
                    script_rel = m.group(1).lstrip("/").lstrip("\\")
                    script_path = plugin_dir / script_rel
                    if not script_path.exists():
                        issues.append((ERROR, str(hooks_json), 0, f"hook references missing script: {script_rel}"))
                    elif script_path.is_file():
                        try:
                            first = script_path.read_text(encoding="utf-8", errors="replace").splitlines()[:1]
                            if first and not first[0].startswith("#!"):
                                issues.append((WARN, str(script_path), 1, "script missing shebang"))
                        except Exception:
                            pass
    return issues


def validate_secrets(root: Path) -> list[Issue]:
    issues: list[Issue] = []
    for path in iter_text_files(root):
        if rel(root, path) in SCAN_EXCLUDE_FILES:
            continue
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for pattern, label in SECRET_PATTERNS:
            for m in re.finditer(pattern, content):
                line = content[:m.start()].count("\n") + 1
                issues.append((ERROR, str(path), line, f"possible {label} matching /{pattern}/"))
    return issues


def iter_text_files(root: Path) -> Iterable[Path]:
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SCAN_SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() in SCAN_BINARY_EXT:
            continue
        yield path


# --- Tool policy --------------------------------------------------------------

def parse_tool_list(value) -> list[str]:
    """Parse `allowed-tools` / `tools` frontmatter into individual entries.

    Accepts a list, or a string separated by whitespace/commas. Paren-scoped
    entries like 'Bash(git *)' are kept as a single entry (the space inside
    the parens is not a separator).
    """
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    s = str(value).strip()
    if not s:
        return []
    out: list[str] = []
    cur: list[str] = []
    depth = 0
    for ch in s:
        if ch == "(":
            depth += 1
            cur.append(ch)
        elif ch == ")":
            depth = max(0, depth - 1)
            cur.append(ch)
        elif depth == 0 and (ch.isspace() or ch == ","):
            if cur:
                out.append("".join(cur).strip())
                cur = []
        else:
            cur.append(ch)
    if cur:
        out.append("".join(cur).strip())
    return [t for t in out if t]


class PolicyParseError(Exception):
    """Raised when policy/allowed-tools.yaml is present but unparsable."""


def load_tool_policy(root: Path) -> dict | None:
    """Return parsed policy, or None if the file is absent.

    A *present but malformed* policy file raises PolicyParseError — the caller
    must turn that into an ERROR-level issue. Silently skipping enforcement on
    a typo would let policy violations through.
    """
    p = root / "policy" / "allowed-tools.yaml"
    if not p.exists():
        return None
    try:
        return yaml.safe_load(p.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        raise PolicyParseError(str(e)) from e


def _build_exceptions_map(policy: dict) -> dict[str, set[str]]:
    """Return {artifact_path: {tool, ...}} from policy['exceptions']."""
    out: dict[str, set[str]] = {}
    for exc in policy.get("exceptions", []) or []:
        if not isinstance(exc, dict):
            continue
        artifact = exc.get("artifact")
        if not artifact:
            continue
        tools = exc.get("tools", []) or []
        out.setdefault(str(artifact), set()).update(str(t) for t in tools)
    return out


def validate_tool_policy(root: Path) -> list[Issue]:
    """Check that every tool declared in a skill / command / agent frontmatter
    is permitted by policy/allowed-tools.yaml. MCP tools (mcp__*) are exempt —
    they are governed by .mcp.json.

    Resolution order for each tool:
      1. forbidden  → ERROR (overrides everything below)
      2. allowed    → pass
      3. exceptions → pass if (artifact_path, tool) is granted
      4. otherwise  → ERROR (not in allowlist)
    """
    issues: list[Issue] = []
    policy_path = root / "policy" / "allowed-tools.yaml"
    try:
        policy = load_tool_policy(root)
    except PolicyParseError as e:
        return [(ERROR, str(policy_path), 0,
                 f"policy/allowed-tools.yaml is unparsable: {e}")]
    if policy is None:
        return [(WARN, str(policy_path), 0,
                 "tool-policy file missing — tool allowlist enforcement skipped")]
    allowed = set(policy.get("allowed", []) or [])
    forbidden = set(policy.get("forbidden", []) or [])
    exceptions = _build_exceptions_map(policy)

    # Sanity-check exceptions structure
    for exc in policy.get("exceptions", []) or []:
        if not isinstance(exc, dict):
            issues.append((ERROR, str(policy_path), 0,
                           "exceptions entry must be a mapping"))
            continue
        if not exc.get("artifact"):
            issues.append((ERROR, str(policy_path), 0,
                           "exceptions entry missing 'artifact'"))
        if not exc.get("tools"):
            issues.append((ERROR, str(policy_path), 0,
                           f"exceptions entry for {exc.get('artifact')!r} missing 'tools'"))
        if not exc.get("justification"):
            issues.append((WARN, str(policy_path), 0,
                           f"exceptions entry for {exc.get('artifact')!r} missing 'justification' — please add one for CODEOWNERS review"))

    def check(file_path: Path, key: str, value, artifact_path: str) -> None:
        for tool in parse_tool_list(value):
            if tool.startswith("mcp__"):
                continue
            if tool in forbidden:
                issues.append((ERROR, str(file_path), 0,
                               f"frontmatter '{key}' contains forbidden tool {tool!r} (see policy/allowed-tools.yaml)"))
                continue
            if tool in allowed:
                continue
            if tool in exceptions.get(artifact_path, set()):
                continue
            issues.append((ERROR, str(file_path), 0,
                           f"frontmatter '{key}' contains tool {tool!r} not in policy/allowed-tools.yaml allowlist "
                           f"(add to 'allowed:' or to an 'exceptions:' entry for {artifact_path!r})"))

    plugins_dir = root / "plugins"
    if not plugins_dir.exists():
        return issues
    for plugin_dir in sorted(plugins_dir.iterdir()):
        if not plugin_dir.is_dir():
            continue
        plugin_name = plugin_dir.name
        skills_dir = plugin_dir / "skills"
        if skills_dir.exists():
            for skill_dir in sorted(skills_dir.glob("*")):
                skill_md = skill_dir / "SKILL.md"
                if skill_md.is_file():
                    try:
                        fm = load_frontmatter(skill_md)
                        check(skill_md, "allowed-tools", fm.get("allowed-tools"),
                              f"{plugin_name}/skills/{skill_dir.name}")
                    except ValueError:
                        pass
        commands_dir = plugin_dir / "commands"
        if commands_dir.exists():
            for cmd in sorted(commands_dir.glob("*.md")):
                try:
                    fm = load_frontmatter(cmd)
                    check(cmd, "allowed-tools", fm.get("allowed-tools"),
                          f"{plugin_name}/commands/{cmd.stem}")
                except ValueError:
                    pass
        agents_dir = plugin_dir / "agents"
        if agents_dir.exists():
            for agent in sorted(agents_dir.glob("*.md")):
                try:
                    fm = load_frontmatter(agent)
                    check(agent, "tools", fm.get("tools"),
                          f"{plugin_name}/agents/{agent.stem}")
                except ValueError:
                    pass
    return issues


# --- Main ---------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Validate Claude Code plugin marketplace.")
    ap.add_argument("--root", default=".", help="Repo root (default: cwd)")
    ap.add_argument("--strict", action="store_true", help="Treat warnings as errors")
    ap.add_argument("--quiet", action="store_true", help="Only print issues + final tally")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    if not (root / ".claude-plugin" / "marketplace.json").exists():
        print(f"ERROR: no .claude-plugin/marketplace.json under {root}", file=sys.stderr)
        return 2

    all_issues: list[Issue] = []

    if not args.quiet:
        print(f"Validating marketplace at: {root}")

    all_issues += validate_marketplace(root)

    plugins_dir = root / "plugins"
    if plugins_dir.exists():
        for plugin_dir in sorted(plugins_dir.iterdir()):
            if not plugin_dir.is_dir():
                continue
            if not args.quiet:
                print(f"  plugin: {plugin_dir.name}")
            all_issues += validate_plugin(root, plugin_dir)

            skills_dir = plugin_dir / "skills"
            if skills_dir.exists():
                for s in sorted(skills_dir.iterdir()):
                    if s.is_dir():
                        all_issues += validate_skill(root, s)

            commands_dir = plugin_dir / "commands"
            if commands_dir.exists():
                for c in sorted(commands_dir.glob("*.md")):
                    all_issues += validate_command_or_agent(c, "command")

            agents_dir = plugin_dir / "agents"
            if agents_dir.exists():
                for a in sorted(agents_dir.glob("*.md")):
                    all_issues += validate_command_or_agent(a, "agent")

            all_issues += validate_hooks(plugin_dir)

    all_issues += validate_tool_policy(root)
    all_issues += validate_secrets(root)

    # Report
    errors = [i for i in all_issues if i[0] == ERROR]
    warnings = [i for i in all_issues if i[0] == WARN]

    if all_issues:
        print()
        for sev, file_, line, msg in sorted(all_issues, key=lambda x: (x[1], x[2])):
            loc = f"{rel(root, file_)}:{line}" if line else rel(root, file_)
            print(f"  [{sev}] {loc} — {msg}")
        print()
    print(f"Summary: {len(errors)} error(s), {len(warnings)} warning(s)")

    if errors or (args.strict and warnings):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
