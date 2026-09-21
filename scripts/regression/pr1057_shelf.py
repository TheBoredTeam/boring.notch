#!/usr/bin/env python3
"""Compile real shelf models with inert bookmark, persistence and storage services.

Run the current view model and f4372f5 as a negative control. The harness only
uses synthetic bookmark bytes; it never opens user files or starts the app.
"""

import argparse
from pathlib import Path
import subprocess


def method(source, signature):
    start = source.index(signature)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True)
    work = parser.parse_args().work_dir.resolve()
    work.mkdir(parents=True, exist_ok=True)
    repo = Path(__file__).resolve().parents[2]
    shelf = Path("boringNotch/components/Shelf")
    state_path = shelf / "ViewModels/ShelfStateViewModel.swift"
    current = (repo / state_path).read_text()
    original = subprocess.check_output(
        ["git", "show", f"f4372f5:{state_path}"], cwd=repo, text=True
    ).replace("ShelfStateViewModel", "OriginalShelfStateViewModel")
    model = (repo / shelf / "Models/ShelfItem.swift").read_text()
    selection = method(
        (repo / shelf / "ViewModels/ShelfSelectionModel.swift").read_text(),
        "    func selectedItems(in allItems: [ShelfItem]) -> [ShelfItem] {",
    )
    standins = """
import Combine

// No security-scoped bookmarks or filesystem access, including during cleanup.
struct Bookmark {
    let data: Data
    var resolvedURL: URL? { nil }
    func resolve() -> (url: URL?, refreshedData: Data?) { (nil, nil) }
    func validate() async -> Bool { false }
}
@MainActor
final class ShelfPersistenceService {
    static let shared = ShelfPersistenceService()
    func load() -> [ShelfItem] { [] }
    func save(_ items: [ShelfItem]) {}
    func saveAsync(_ items: [ShelfItem]) async {}
}
@MainActor
final class TemporaryFileStorageService {
    static let shared = TemporaryFileStorageService()
    func removeTemporaryFileIfNeeded(at url: URL) {
        preconditionFailure("Synthetic bookmarks must never resolve to files")
    }
}
enum ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] { [] }
}
@MainActor
protocol ShelfHarness: AnyObject {
    var items: [ShelfItem] { get }
    func add(_ items: [ShelfItem])
    func updateBookmark(for item: ShelfItem, bookmark: Data)
    func remove(_ item: ShelfItem)
    func flushSync()
}
extension ShelfStateViewModel: ShelfHarness {}
extension OriginalShelfStateViewModel: ShelfHarness {}
"""
    cases = r"""
@main
struct Regression {
    @MainActor
    static func main() {
        var assertions = 0
        var originalFailures = 0
        func check(_ condition: Bool, _ message: String) {
            assertions += 1
            precondition(condition, message)
        }
        let variants: [(String, any ShelfHarness, Bool)] = [
            ("original", OriginalShelfStateViewModel.shared, false),
            ("current", ShelfStateViewModel.shared, true),
        ]
        for (label, state, preservesIdentity) in variants {
            for temporary in [false, true] {
                let text = ShelfItem(kind: .text(string: "shelf regression"))
                let file = ShelfItem(kind: .file(bookmark: Data([1])), isTemporary: temporary)
                let link = ShelfItem(kind: .link(url: URL(string: "https://example.invalid/shelf")!))
                let draggedSnapshot = file
                let selection = SelectionHarness(selectedIDs: [file.id])
                state.add([text, file, link])
                check(state.items == [text, file, link], "Fixture order")

                let unchanged = state.items
                state.updateBookmark(for: text, bookmark: Data([8]))
                state.updateBookmark(for: link, bookmark: Data([8]))
                state.updateBookmark(for: ShelfItem(kind: .file(bookmark: Data([9]))), bookmark: Data([8]))
                check(state.items == unchanged, "Text, URL and missing item updates are no-ops")

                // Metadata belongs to the stored item, even with an outdated caller snapshot.
                let staleMetadata = ShelfItem(id: file.id, kind: file.kind, isTemporary: !temporary)
                state.updateBookmark(for: staleMetadata, bookmark: Data([2]))
                check(state.items.count == 3 && state.items[0] == text && state.items[2] == link,
                      "Refresh preserves ordering and neighbors")
                check(state.items[1].kind == .file(bookmark: Data([2])), "Bookmark bytes replaced")
                check(state.items[1].isTemporary == temporary, "Stored temporary flag preserved")
                let identity = state.items[1].id == file.id
                let selected = selection.selectedItems(in: state.items).map(\.id) == [file.id]
                check(identity == preservesIdentity, "Identity expectation")
                check(selected == preservesIdentity, "Selection using original UUID")

                state.updateBookmark(for: file, bookmark: Data([3]))
                state.updateBookmark(for: file, bookmark: Data([4]))
                let repeated = state.items[1].kind == .file(bookmark: Data([4]))
                check(repeated == preservesIdentity, "Repeated refresh using original snapshot")
                check(state.items[1].isTemporary == temporary, "Repeated refresh keeps temporary flag")
                check(state.items.count == 3 && state.items[0] == text && state.items[2] == link,
                      "Repeated refresh preserves ordering")
                check((state.items[1].id == file.id) == preservesIdentity, "Repeated refresh identity")

                state.remove(draggedSnapshot)
                let removed = state.items == [text, link]
                check(removed == preservesIdentity, "Drag removal using original snapshot")
                print("\(label) temporary=\(temporary): identity=\(identity), selection=\(selected), repeatedRefresh=\(repeated), originalSnapshotRemoval=\(removed)")
                if !preservesIdentity {
                    originalFailures += [identity, selected, repeated, removed].filter { !$0 }.count
                }
                for item in state.items { state.remove(item) }
                state.flushSync() // Cancels debounce tasks; the persistence implementation is inert.
                check(state.items.isEmpty, "Fixture cleanup")
            }
        }
        check(originalFailures == 8, "Original failures reproduced for both temporary flags")
        print("Passed 4 scenarios / \(assertions) assertions; \(originalFailures) original failures reproduced.")
    }
}
"""
    source = work / "main.swift"
    source.write_text(
        model + current + original + standins
        + "\n@MainActor\nstruct SelectionHarness {\n    let selectedIDs: Set<UUID>\n"
        + selection + "\n}\n" + cases
    )
    executable = work / "shelf-regression"
    subprocess.run([
        "swiftc", "-parse-as-library", "-module-cache-path", str(work / "module-cache"),
        str(source), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
