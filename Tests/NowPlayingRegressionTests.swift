import Foundation

actor ReceivedTitles {
    var values: [String] = []
    func append(_ title: String) { values.append(title) }
}

@main
struct NowPlayingRegressionTests {
    static func update(_ json: String) throws -> NowPlayingUpdate {
        try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(json.utf8))
    }

    static func main() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var previous = PlaybackState(bundleIdentifier: "com.spotify.client")
        previous.title = "Previous song"
        previous.artist = "Artist"
        previous.duration = 200
        previous.currentTime = 50
        previous.isPlaying = true
        previous.playbackRate = 2
        previous.lastUpdated = now.addingTimeInterval(-5)
        previous.artwork = Data([1, 2, 3])

        let diff = try update(#"{"diff":true,"payload":{"playing":false}}"#)
        let paused = diff.applying(to: previous, at: now)
        precondition(paused.artwork == previous.artwork, "Partial updates must retain artwork")
        precondition(paused.currentTime == 60, "Pausing must anchor elapsed time at the update")
        precondition(paused.lastUpdated == now)
        let pausedAgain = diff.applying(to: paused, at: now.addingTimeInterval(10))
        precondition(pausedAgain.currentTime == 60, "Paused playback must not advance")

        let snapshot = try update(#"{"diff":false,"payload":{"title":"New song","bundleIdentifier":"org.videolan.vlc"}}"#)
        let next = snapshot.applying(to: previous, at: now)
        precondition(next.title == "New song" && next.bundleIdentifier == "org.videolan.vlc")
        precondition(next.artwork == nil && next.artist.isEmpty && next.duration == 0)
        precondition(next.currentTime == 0 && !next.isPlaying)
        let empty = try update(#"{"diff":false,"payload":{}}"#).applying(to: previous, at: now)
        precondition(empty.title.isEmpty && empty.bundleIdentifier.isEmpty && empty.artwork == nil)
        let excessive = try update(#"{"diff":false,"payload":{"elapsedTime":250,"duration":100}}"#).applying(to: previous, at: now)
        precondition(excessive.currentTime == 100)

        let reader = JSONLinesPipeHandler()
        let pipe = reader.outputPipe
        let titles = ReceivedTitles()
        let reading = Task {
            await reader.readJSONLines(as: NowPlayingUpdate.self) { value in
                await titles.append(value.payload.title ?? "")
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let artwork = String(repeating: "A", count: 100_000)
        let bytes = Data("{\"payload\":{\"title\":\"Geëk\",\"artworkData\":\"\(artwork)\"}}\n{\"payload\":{\"title\":\"Final line\"}}".utf8)
        let split = bytes.firstIndex(of: 0xC3)! + 1
        try pipe.fileHandleForWriting.write(contentsOf: bytes[..<split])
        try await Task.sleep(for: .milliseconds(20))
        try pipe.fileHandleForWriting.write(contentsOf: bytes[split...])
        try await Task.sleep(for: .milliseconds(100))
        let beforeEOF = await titles.values
        precondition(beforeEOF == ["Geëk"], "Artwork messages must arrive while the stream remains open, without another event")
        try pipe.fileHandleForWriting.close()
        await reading.value
        let received = await titles.values
        precondition(received == ["Geëk", "Final line"], "Split UTF-8 and final unterminated lines must decode")
        reader.close()

        let cancellable = JSONLinesPipeHandler()
        let waiting = Task {
            await cancellable.readJSONLines(as: NowPlayingUpdate.self) { _ in }
        }
        try await Task.sleep(for: .milliseconds(20))
        waiting.cancel()
        await waiting.value
        cancellable.close()
        let completed = Process()
        completed.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let completedSuccessfully = try await TimedProcessRunner.exitsSuccessfully(completed, timeout: .seconds(1))
        precondition(completedSuccessfully)

        let hanging = Process()
        hanging.executableURL = URL(fileURLWithPath: "/bin/sleep")
        hanging.arguments = ["5"]
        let hangingSucceeded = try await TimedProcessRunner.exitsSuccessfully(hanging, timeout: .milliseconds(100))
        precondition(!hangingSucceeded, "A hanging capability check must time out")
        try await Task.sleep(for: .milliseconds(50))
        precondition(!hanging.isRunning)
        print("Now Playing regression checks passed")
    }
}
