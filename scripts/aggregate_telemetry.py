#!/usr/bin/env python3
"""Aggregate skill-activation telemetry written by the log-skill-activation hook.

The PreSkill hook in plugins/base-tools/hooks/log-skill-activation.py appends
one JSON-lines record per skill activation to:

    ${CLAUDE_PLUGIN_DATA}/base-tools/skills.jsonl

(or to ${TMPDIR}/base-tools/skills.jsonl if CLAUDE_PLUGIN_DATA is unset).

This script reads that log and prints a markdown summary grouped by skill —
usage counts, date range, last-seen-at — so a team lead can see which skills
the team is actually getting value from.

Usage:
    python scripts/aggregate_telemetry.py
    python scripts/aggregate_telemetry.py --path ~/.claude/plugins/data/base-tools/skills.jsonl
    python scripts/aggregate_telemetry.py --since 2026-04-01
    python scripts/aggregate_telemetry.py --top 10
    python scripts/aggregate_telemetry.py --format json    # for piping into other tools

Stdlib only — no extra dependencies.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass
class Record:
    ts: str
    skill: str
    session: str


def default_path() -> Path:
    root = os.environ.get("CLAUDE_PLUGIN_DATA") or tempfile.gettempdir()
    return Path(root) / "base-tools" / "skills.jsonl"


def parse_since(s: str | None) -> str | None:
    if not s:
        return None
    # Accept YYYY-MM-DD or full ISO 8601
    try:
        datetime.fromisoformat(s)
    except ValueError:
        print(f"ERROR: --since {s!r} is not ISO 8601 (e.g. 2026-04-01)", file=sys.stderr)
        sys.exit(2)
    return s


def load(path: Path, since: str | None) -> list[Record]:
    if not path.exists():
        print(f"No telemetry log at {path}. Skill hook hasn't fired yet, "
              f"or CLAUDE_PLUGIN_DATA points elsewhere.", file=sys.stderr)
        return []
    out: list[Record] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            print(f"WARNING: {path}:{line_no} skipped — invalid JSON: {e}", file=sys.stderr)
            continue
        ts = str(obj.get("ts", ""))
        if since and ts < since:
            continue
        out.append(Record(
            ts=ts,
            skill=str(obj.get("skill", "unknown")),
            session=str(obj.get("session", "")),
        ))
    return out


def render_markdown(records: list[Record], top: int) -> str:
    if not records:
        return "_No telemetry records._\n"
    by_skill = Counter(r.skill for r in records)
    sessions = {r.session for r in records if r.session}
    # `default=""` guards against all-records-with-empty-ts (shouldn't happen with
    # the bundled hook, but custom collectors might emit malformed records).
    earliest = min((r.ts for r in records if r.ts), default="")
    latest = max((r.ts for r in records if r.ts), default="")
    last_seen: dict[str, str] = {}
    for r in records:
        if r.skill not in last_seen or r.ts > last_seen[r.skill]:
            last_seen[r.skill] = r.ts

    lines = []
    lines.append(f"# Skill activations — {len(records)} total")
    lines.append("")
    lines.append(f"- **Window:** {earliest} → {latest}")
    lines.append(f"- **Unique skills:** {len(by_skill)}")
    lines.append(f"- **Unique sessions:** {len(sessions)}")
    lines.append("")
    lines.append(f"## Top {min(top, len(by_skill))} skills")
    lines.append("")
    lines.append("| Skill | Activations | Last seen |")
    lines.append("|---|---:|---|")
    for skill, count in by_skill.most_common(top):
        lines.append(f"| `{skill}` | {count} | {last_seen.get(skill, '')} |")
    lines.append("")
    return "\n".join(lines)


def render_json(records: list[Record], top: int) -> str:
    by_skill = Counter(r.skill for r in records)
    return json.dumps({
        "total": len(records),
        "top": [{"skill": s, "count": c} for s, c in by_skill.most_common(top)],
        "skills": dict(by_skill),
    }, indent=2)


def main() -> int:
    ap = argparse.ArgumentParser(description="Aggregate base-tools skill-activation telemetry.")
    ap.add_argument("--path", type=Path, default=default_path(),
                    help="Path to skills.jsonl (default: $CLAUDE_PLUGIN_DATA/base-tools/skills.jsonl)")
    ap.add_argument("--since", type=str, default=None,
                    help="ISO date — only include records on or after this timestamp")
    ap.add_argument("--top", type=int, default=10, help="Show top N skills (default 10)")
    ap.add_argument("--format", choices=["markdown", "json"], default="markdown")
    args = ap.parse_args()

    since = parse_since(args.since)
    records = load(args.path, since)

    if args.format == "json":
        print(render_json(records, args.top))
    else:
        print(render_markdown(records, args.top))
    return 0


if __name__ == "__main__":
    sys.exit(main())
