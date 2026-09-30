#!/usr/bin/env python3
"""Compare synthetic label errors against a Git baseline; no private transcripts."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

CORE = "boringNotch/features/CodexNotifications/Core/CodexNotificationsCore.swift"
BASELINE = "9b62aefec74c9668dbf61a5a4a37e7091ddab7e0"
NEGATIVES = [
    "Implemented your choice and all tests passed.",
    "The README now says: please choose an option. Documentation update complete.",
    "Added example output:\n```text\nerror: file not found\n```\nAll tests passed.",
    "If the build failed, rerun it. All tests passed.",
    "Added the checklist item: please test manually before release. Documentation complete.",
    "The requested explanation is complete. Would you like me to add examples?",
    "I added the error: handler and all tests passed.",
    None,
    ("The command failed initially. " + "Investigation details. " * 210 + " Fixed it. All tests passed.")[:4000],
]
ACTIONS = [
    "I need your input: choose A or B.",
    "Please manually review and approve or reject.",
    "I cannot proceed until the credentials are supplied.",
    "请选 A 或 B，我会等待你的决定。",
]
SWIFT = r'''
import Foundation
let objects = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [[String: Any]]
var labels: [String] = []
for object in objects {
    var state = CodexNotificationState()
    state.reduce(try CodexHookEventParser.parse(JSONSerialization.data(withJSONObject: object)))
    labels.append(state.visibleNotification()?.status.title ?? "no notice")
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: labels))
'''


def evaluate(root, source, path):
    path.mkdir()
    core = path / "Core.swift"
    core.write_text(source)
    main = path / "main.swift"
    main.write_text(SWIFT)
    executable = path / "probe"
    subprocess.run(["swiftc", "-module-cache-path", str(path / "cache"), str(core), str(main), "-o", str(executable)], check=True, capture_output=True)
    messages = NEGATIVES + ACTIONS
    payloads = [dict(hook_event_name="Stop", session_id=f"synthetic-{i}", turn_id="turn", **({"last_assistant_message": message} if message is not None else {})) for i, message in enumerate(messages)]
    result = subprocess.run([str(executable)], input=json.dumps(payloads), text=True, capture_output=True, check=True)
    labels = json.loads(result.stdout)
    alerts = {"Failure", "Decision Required", "Manual Check", "Permission Required"}
    return {
        "non_action_examples": len(NEGATIVES),
        "false_alerts": sum(label in alerts for label in labels[:len(NEGATIVES)]),
        "blocking_or_manual_action_examples": len(ACTIONS),
        "semantic_actions_detected": sum(label in {"Decision Required", "Manual Check"} for label in labels[len(NEGATIVES):]),
        "notifications_delivered": sum(label != "no notice" for label in labels),
        "total_examples": len(labels),
        "labels": labels,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default=BASELINE)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    baseline = subprocess.check_output(["git", "show", f"{args.baseline}:{CORE}"], cwd=root, text=True)
    with tempfile.TemporaryDirectory(prefix="codex-label-evaluation-") as scratch:
        results = {"baseline": evaluate(root, baseline, Path(scratch) / "before"), "refined": evaluate(root, (root / CORE).read_text(), Path(scratch) / "after")}
    print(json.dumps(results, indent=2, ensure_ascii=False))
    assert results["refined"]["false_alerts"] == 0
    assert results["refined"]["notifications_delivered"] == results["refined"]["total_examples"]
    print("Synthetic regression set only; not a production rate. Semantic action detection is intentionally absent from the refined lifecycle labels.")


if __name__ == "__main__":
    main()
