#!/usr/bin/env python3
"""Compile the actual drag validator with typed, in-memory pasteboard stand-ins.

Also compile f4372f5's validator as a negative control. No system pasteboard is
created or accessed, and no event monitors or app processes are started.
"""

import argparse
from pathlib import Path
import subprocess


def validator(source):
    start = source.index("    private func hasValidDragContent() -> Bool {")
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def wrapper(name, method):
    return f"""
struct {name} {{
    let dragPasteboard: FakePasteboard
{method}
    func evaluate() -> Bool {{ hasValidDragContent() }}
}}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    work = args.work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[2]
    path = "boringNotch/observers/DragDetector.swift"
    current = validator((repo / path).read_text())
    original = validator(subprocess.check_output(
        ["git", "show", f"f4372f5:{path}"], cwd=repo, text=True
    ))
    assert original.count(".allSatisfy") == 2, "Expected original nested allSatisfy"
    standins = """
import AppKit
import UniformTypeIdentifiers

struct FakePasteboardItem {
    let types: [NSPasteboard.PasteboardType]
}
struct FakePasteboard {
    let pasteboardItems: [FakePasteboardItem]?
}
"""
    cases = r"""
typealias Types = [NSPasteboard.PasteboardType]
let url = NSPasteboard.PasteboardType(UTType.url.identifier)
let finderMetadata = NSPasteboard.PasteboardType("com.apple.finder.node")
let appMetadata = NSPasteboard.PasteboardType("com.example.drag-metadata")
let cases: [(String, [Types]?, Bool, Bool)] = [
    ("absent pasteboard items", nil, false, false),
    ("empty pasteboard items", [], false, true),
    ("empty item types", [[]], false, true),
    ("unsupported metadata only", [[finderMetadata, appMetadata]], false, false),
    ("unsupported image only", [[.png]], false, false),
    ("unsupported rich text only", [[.rtf]], false, false),
    ("file URL", [[.fileURL]], true, true),
    ("URL", [[url]], true, true),
    ("text", [[.string]], true, true),
    ("file URL plus Finder metadata", [[.fileURL, finderMetadata]], true, false),
    ("URL plus app metadata", [[appMetadata, url]], true, false),
    ("text plus rich text and app metadata", [[.rtf, .string, appMetadata]], true, false),
    ("multiple supported representations", [[.fileURL, url, .string]], true, true),
    ("multiple supported items with metadata",
        [[.fileURL, finderMetadata], [url, appMetadata], [.string, .rtf]], true, false),
    ("supported then unsupported item", [[.fileURL], [appMetadata]], false, false),
    ("unsupported then supported item", [[appMetadata], [.string]], false, false),
    ("supported then empty item", [[.string], []], false, true),
    ("empty then supported item", [[], [url]], false, true),
]
var negativeControls = 0
for (name, types, expected, expectedOriginal) in cases {
    let pasteboard = FakePasteboard(pasteboardItems: types?.map { FakePasteboardItem(types: $0) })
    let actual = CurrentValidator(dragPasteboard: pasteboard).evaluate()
    let old = OriginalValidator(dragPasteboard: pasteboard).evaluate()
    precondition(actual == expected, "Current validator failed: \(name), got \(actual)")
    precondition(old == expectedOriginal, "Original control changed: \(name), got \(old)")
    if old != expected { negativeControls += 1 }
    print("\(name): current=\(actual), original=\(old), expected=\(expected)")
}
precondition(negativeControls == 8)
print("Passed \(cases.count) cases / \(cases.count * 2) validator assertions; \(negativeControls) original failures reproduced.")
"""
    source = work / "main.swift"
    source.write_text(standins + wrapper("CurrentValidator", current)
                      + wrapper("OriginalValidator", original) + cases)
    executable = work / "drag-regression"
    subprocess.run([
        "swiftc", "-module-cache-path", str(work / "module-cache"),
        str(source), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
