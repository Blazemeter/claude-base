#!/usr/bin/env python3
"""PreSkill hook — nudge to file the EARLY doc-task draft during design/spec work.

STANDARDS rule #4 has two invocation points for `file-doc-task`: an EARLY draft
(right after a design / spec / plan is reviewed and locked, to guide development)
and a FINALIZE reconcile (at PR time). The PR gate
(`require-doc-task-decision.sh`) guarantees the finalize side. This hook covers
the early side: when a design / spec / plan / architecture skill activates, it
surfaces a reminder to draft the DOC-ready ticket now rather than waiting for the
PR.

It is ADVISORY and best-effort:
  * It never blocks (always exits 0) — a nudge, not a gate.
  * PreSkill stdout is not a guaranteed context channel across harness versions,
    so this emits the documented `hookSpecificOutput.additionalContext` JSON
    shape (honoured where supported) and logs the nudge for telemetry. The
    always-on SessionStart primer carries the same instruction as the reliable
    fallback, so the reminder is never lost even if this channel is ignored.

Wired up in ../hooks.json under PreSkill with matcher ".*"; the design/spec
filtering happens here so we don't depend on matcher semantics for skill names.
"""

import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# Skill names (or slugs) that indicate a design / spec / planning phase — the
# moment the early draft is most useful. Matched case-insensitively as a
# substring of the skill name, so "sdd", "generate-design", "spec-review",
# "architect", "plan" all trigger.
PHASE_MARKERS = (
    "design",
    "spec",
    "plan",
    "architect",
    "blueprint",
    "sdd",
    "feature-dev",
)

NUDGE = (
    "STANDARDS rule #4 (early invocation): you're in a design/spec/planning "
    "phase. If the design or spec is reviewed and locked, file the EARLY "
    "DOC-ready draft now with the file-doc-task skill — drafting from the "
    "intended behavior guides development and anchors it to a stated customer "
    "outcome. It's idempotent: the finalize pass at PR time reconciles this "
    "draft to as-built rather than filing a second ticket. If docs clearly "
    "don't apply yet, you can defer — the PR gate will still require a decision "
    "before merge."
)


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        payload = {}

    skill = str(payload.get("skill_name", "")).lower()
    # Don't nudge the doc skill about itself, or unknown skills.
    if not skill or "file-doc-task" in skill:
        return
    if not any(marker in skill for marker in PHASE_MARKERS):
        return

    # Telemetry — record that we nudged, so teams can see coverage. Best-effort.
    try:
        data_root = os.environ.get("CLAUDE_PLUGIN_DATA") or tempfile.gettempdir()
        data_dir = Path(data_root) / "base-tools"
        data_dir.mkdir(parents=True, exist_ok=True)
        with (data_dir / "doc-task-nudges.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps({
                "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "skill": payload.get("skill_name", ""),
                "session": os.environ.get("CLAUDE_SESSION_ID", ""),
            }) + "\n")
    except OSError:
        pass

    # Surface the nudge via the documented additionalContext JSON shape
    # (honoured where supported); the SessionStart primer is the reliable
    # fallback if this channel is ignored.
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreSkill",
            "additionalContext": NUDGE,
        }
    }))


if __name__ == "__main__":
    main()
