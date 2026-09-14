import XCTest
@testable import boringNotch

@MainActor
final class ScreenContextTests: XCTestCase {
    private final class Context {
        let id: String
        init(_ id: String) { self.id = id }
    }

    func testOneHundredTopologyChangesKeepOneOwnerPerScreen() {
        let store = ScreenContextStore<Context>()
        var creations = 0
        var removals = 0
        let sequences = [["built-in"], ["built-in", "external"], ["external"], [], ["external", "built-in"]]
        for index in 0..<100 {
            let previous = store.contexts
            let ids = sequences[index % sequences.count]
            let snapshot = Dictionary(uniqueKeysWithValues: ids.map { ($0, index) })
            store.reconcile(screens: snapshot, create: { id, _ in
                creations += 1
                return Context(id)
            }, remove: { _ in removals += 1 })
            XCTAssertEqual(Set(store.contexts.keys), Set(ids))
            XCTAssertEqual(creations - removals, ids.count)
            for id in ids where previous[id] != nil {
                XCTAssertTrue(previous[id] === store.contexts[id], "Retain owners across geometry and mode changes")
            }
        }
        store.reconcile(screens: [String: Int](), create: { id, _ in Context(id) }, remove: { _ in removals += 1 })
        XCTAssertEqual(creations, removals)
    }

    func testRemovedOwnerIsReleasedAndReconnectGetsNewIdentity() {
        let store = ScreenContextStore<Context>()
        store.reconcile(screens: ["external": 0], create: { id, _ in Context(id) }, remove: { _ in })
        weak var removed = store.contexts["external"]
        store.reconcile(screens: [String: Int](), create: { id, _ in Context(id) }, remove: { _ in })
        XCTAssertNil(removed, "Removed contexts cannot retain old view models or observers")
        store.reconcile(screens: ["external": 1], create: { id, _ in Context(id) }, remove: { _ in })
        XCTAssertNotNil(store.contexts["external"])
    }

    func testSingleAllSingleRetainsOnlySelectedOwner() {
        let store = ScreenContextStore<Context>()
        let create: (String, Int) -> Context = { id, _ in Context(id) }
        var removed: [String] = []
        let remove: (Context) -> Void = { removed.append($0.id) }
        store.reconcile(screens: ["a": 0], create: create, remove: remove)
        let selected = store.contexts["a"]
        store.reconcile(screens: ["a": 1, "b": 1], create: create, remove: remove)
        store.reconcile(screens: ["a": 2], create: create, remove: remove)
        XCTAssertTrue(selected === store.contexts["a"])
        XCTAssertEqual(removed, ["b"])
    }
}

final class FullscreenVisibilityPolicyTests: XCTestCase {
    private let spaces: [(screenUUID: String?, runningApps: [String])] = [
        ("a", ["player", "split-view-app"]), ("b", ["other-app"]), (nil, ["player"])
    ]

    func testPreferenceChangesReevaluateSameSpaces() {
        XCTAssertEqual(FullscreenVisibilityPolicy.status(spaces: spaces, option: .always, mediaSource: "player"), ["a": true, "b": true])
        XCTAssertEqual(FullscreenVisibilityPolicy.status(spaces: spaces, option: .nowPlayingOnly, mediaSource: "player"), ["a": true, "b": false])
        XCTAssertEqual(FullscreenVisibilityPolicy.status(spaces: spaces, option: .never, mediaSource: "player"), ["a": false, "b": false])
    }

    func testMediaSourceChangesReevaluateSameSpaces() {
        XCTAssertEqual(FullscreenVisibilityPolicy.status(spaces: spaces, option: .nowPlayingOnly, mediaSource: "other-app"), ["a": false, "b": true])
        XCTAssertEqual(FullscreenVisibilityPolicy.status(spaces: spaces, option: .nowPlayingOnly, mediaSource: nil), ["a": false, "b": false])
        XCTAssertEqual(FullscreenVisibilityPolicy.status(spaces: spaces, option: .nowPlayingOnly, mediaSource: ""), ["a": false, "b": false])
        XCTAssertEqual(FullscreenVisibilityPolicy.status(spaces: [], option: .always, mediaSource: "player"), [:])
    }

    func testMultipleSpacesOnDisplayDoNotOverwriteMatchingSource() {
        let spaces: [(screenUUID: String?, runningApps: [String])] = [("a", ["player"]), ("a", ["other-app"])]
        XCTAssertEqual(FullscreenVisibilityPolicy.status(spaces: spaces, option: .nowPlayingOnly, mediaSource: "player"), ["a": true])
    }
}
