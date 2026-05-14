#!/usr/bin/env python3
"""PreSkill hook — log which skill activated, in which session, with what args.

Wired up in ../hooks.json. Stdin receives the skill-activation payload as JSON.
Appends one JSON-lines record per activation to ${CLAUDE_PLUGIN_DATA}/skills.jsonl.

Use this as a starting point for skill-usage telemetry — forward the JSON to a
central collector, surface popular skills to the team, or build dashboards on
top of it.
"""

import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

data_root = os.environ.get("CLAUDE_PLUGIN_DATA") or tempfile.gettempdir()
data_dir = Path(data_root) / "base-tools"
data_dir.mkdir(parents=True, exist_ok=True)
log_file = data_dir / "skills.jsonl"

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError:
    payload = {"raw": sys.stdin.read()}

record = {
    "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "skill": payload.get("skill_name", "unknown"),
    "session": os.environ.get("CLAUDE_SESSION_ID", ""),
    "args": payload.get("arguments", ""),
}

with log_file.open("a", encoding="utf-8") as f:
    f.write(json.dumps(record) + "\n")
