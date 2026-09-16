#!/usr/bin/env python3
"""Compile actual YouTube reset paths and playback guards with inert app stand-ins."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--work-dir", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.work_dir or Path(tempfile.mkdtemp(prefix="pr1057-playback-"))
work.mkdir(parents=True, exist_ok=True)
controller = (root / "boringNotch/MediaControllers/YouTubeMusicController/YouTubeMusicController.swift").read_text()
manager = (root / "boringNotch/managers/MusicManager.swift").read_text()


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    end, depth = opening + 1, 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


initial_start = controller.index("    @Published var playbackState = PlaybackState(")
initial = controller[initial_start:controller.index("\n    )", initial_start) + 6]
inactive_start = controller.index("    func updatePlaybackInfo() async {")
inactive = controller[inactive_start:controller.index("        do {", inactive_start)] + "    }\n"
assert "resetPlaybackState()" in inactive
termination = block(controller, "    private func handleAppTerminated(")
assert "resetPlaybackState()" in termination
reset = block(controller, "    private func resetPlaybackState()")
sink = block(manager, ".sink { [weak self, controller] state in")
update = block(manager, "    private func updateFromPlaybackState(")
update_guard = next(line for line in update.splitlines() if "guard state.lastUpdated" in line)
fixture = '''
import Foundation
import Combine
struct YouTubeMusicConfiguration {
    static let `default` = Self()
    let bundleIdentifier = "test.youtube.music"
}
enum NSWorkspace { static let applicationUserInfoKey = "application" }
final class NSRunningApplication { let bundleIdentifier = "test.youtube.music" }
@MainActor final class Controller {
    private let configuration = YouTubeMusicConfiguration.default
    var active = true
    func isActive() -> Bool { active }
    func takeWebSocketClient() -> Int? { nil }
    func stopPeriodicUpdates() {}
    func cancelReconnect(resetDelay: Bool) {}
    func disconnectClient(_ client: Int?) {}
'''
subscriber = '''
}
@MainActor final class GuardedSubscriber {
    let activeController: Controller
    var accepted: [PlaybackState] = []
    private var subscription: AnyCancellable?
    init(_ controller: Controller) {
        activeController = controller
        subscription = controller.$playbackState
'''
checks = '''
}
@main struct PlaybackRegression {
    @MainActor static func main() async {
        let controller = Controller()
        let subscriber = GuardedSubscriber(controller)
        precondition(controller.playbackState.lastUpdated == .distantPast)
        precondition(subscriber.accepted.isEmpty, "startup publisher snapshot must be rejected")
        subscriber.updateFromPlaybackState(controller.playbackState)
        precondition(subscriber.accepted.isEmpty, "direct startup update must be rejected")
        print("PASS: fresh startup snapshot is rejected by both actual MusicManager timestamp guards")
        let playing = PlaybackState(bundleIdentifier: "test.youtube.music", isPlaying: true,
            title: "Fixture song", artist: "Fixture artist", album: "Fixture album",
            currentTime: 42, duration: 180, lastUpdated: Date(), artwork: Data([1, 2]))
        controller.playbackState = playing
        precondition(subscriber.accepted.count == 1 && subscriber.accepted.last?.isPlaying == true)
        for terminated in [true, false] {
            if !terminated { controller.playbackState = playing }
            let count = subscriber.accepted.count
            let before = Date()
            if terminated {
                await controller.handleAppTerminated(Notification(name: Notification.Name("terminated"),
                    userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication()]))
            } else {
                controller.active = false
                await controller.updatePlaybackInfo()
            }
            guard let state = subscriber.accepted.last else { preconditionFailure("missing reset") }
            precondition(subscriber.accepted.count == count + 1, "reset must reach guarded subscriber")
            precondition(!state.isPlaying && state.lastUpdated >= before && state.lastUpdated <= Date())
            precondition(state.bundleIdentifier == playing.bundleIdentifier)
            precondition(state.title.isEmpty && state.artist.isEmpty && state.album.isEmpty)
            precondition(state.currentTime == 0 && state.duration == 0 && state.artwork == nil)
            print("PASS: \\(terminated ? "termination" : "inactive polling") publishes stopped state and clears metadata, progress and artwork")
        }
        var resumed = playing
        resumed.lastUpdated = Date()
        controller.playbackState = resumed
        precondition(subscriber.accepted.count == 5 && subscriber.accepted.last?.isPlaying == true)
        print("PASS: subsequent resumed playback reaches the guarded subscriber")
    }
}
'''
swift = work / "PlaybackRegression.swift"
swift.write_text(fixture + initial + "\n" + inactive + termination.replace("private func", "func", 1)
                 + "\n" + reset + subscriber + sink + "\n    }\n    func updateFromPlaybackState(_ state: PlaybackState) {\n"
                 + update_guard + "\n        accepted.append(state)\n    }\n" + checks)
binary = work / "playback-regression"
subprocess.run(["swiftc", "-module-cache-path", str(work / "module-cache"), "-parse-as-library",
                str(root / "boringNotch/models/PlaybackState.swift"), str(swift), "-o", str(binary)], check=True)
subprocess.run([str(binary)], check=True)
