#!/usr/bin/env python3
# Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
# Attribution applies to the extension platform contributions.

"""Summarize controller lifetime telemetry from the standalone tab stress fixture."""
import argparse
from collections import Counter
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("log", type=Path, nargs="?", default=Path("/tmp/boring-tab-scale/controllers.jsonl"))
parser.add_argument("--pid", type=int, help="Restrict to one host process after multiple test launches.")
args = parser.parse_args()
records = [json.loads(line) for line in args.log.read_text().splitlines() if line.strip()]
if args.pid is not None:
    records = [item for item in records if item["pid"] == args.pid]
created = {item["controllerID"]: item for item in records if item["event"] == "controller.create"}
released = {item["controllerID"] for item in records if item["event"] == "controller.deinit"}
print(json.dumps({
    "events": dict(Counter(item["event"] for item in records)),
    "processIDs": sorted({item["pid"] for item in records}),
    "providers": len({item["providerID"] for item in records if item["event"] == "instance.create"}),
    "createdControllers": len(created), "releasedControllers": len(released),
    "liveControllers": [item for key, item in created.items() if key not in released],
    "unknownReleases": sorted(released - created.keys())
}, indent=2))
