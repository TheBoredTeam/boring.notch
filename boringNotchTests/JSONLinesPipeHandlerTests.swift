//
//  JSONLinesPipeHandlerTests.swift
//  boringNotchTests
//

import XCTest

@testable import boringNotch

private struct PipePayload: Codable, Sendable, Equatable {
    let id: Int
    let blob: String?

    init(id: Int, blob: String? = nil) {
        self.id = id
        self.blob = blob
    }
}

private actor Collector {
    private(set) var values: [PipePayload] = []
    func add(_ value: PipePayload) { values.append(value) }
}

private func line(_ payload: PipePayload) -> Data {
    var data = try! JSONEncoder().encode(payload)
    data.append(UInt8(ascii: "\n"))
    return data
}

final class JSONLinesPipeHandlerTests: XCTestCase {
    /// Runs the reader to completion while `write` feeds the pipe.
    private func run(
        write: @escaping @Sendable (FileHandle) -> Void
    ) async -> [PipePayload] {
        let handler = JSONLinesPipeHandler()
        let collector = Collector()
        let writer = handler.outputPipe.fileHandleForWriting

        // Detached: a payload bigger than the pipe buffer blocks the writer
        // until the reader drains it.
        let writing = Task.detached { write(writer) }

        await handler.readJSONLines(as: PipePayload.self) { value in
            await collector.add(value)
        }
        await writing.value
        handler.close()
        return await collector.values
    }

    func testMultipleLinesInOneChunkDecodeInOrder() async {
        let expected = [PipePayload(id: 1), PipePayload(id: 2), PipePayload(id: 3)]
        let values = await run { writer in
            var data = Data()
            for payload in expected {
                data.append(line(payload))
            }
            writer.write(data)
            try? writer.close()
        }

        XCTAssertEqual(values, expected)
    }

    func testObjectSpanningChunkBoundariesDecodes() async {
        // ~400 KB — larger than the 64 KiB pipe buffer, so the reader is
        // guaranteed several reads before the newline arrives.
        let payload = PipePayload(id: 7, blob: String(repeating: "a", count: 400_000))
        let encoded = line(payload)

        let values = await run { writer in
            // Split by hand as well, so the first half is seen with no newline.
            let half = encoded.count / 2
            writer.write(encoded.prefix(half))
            writer.write(encoded.suffix(from: half))
            try? writer.close()
        }

        XCTAssertEqual(values, [payload])
    }

    func testTrailingLineWithoutNewlineIsDropped() async {
        let complete = PipePayload(id: 1)
        let values = await run { writer in
            var data = line(complete)
            data.append(try! JSONEncoder().encode(PipePayload(id: 2))) // no "\n"
            writer.write(data)
            try? writer.close()
        }

        XCTAssertEqual(values, [complete])
    }

    func testThreeConsecutiveMalformedLinesStopTheStream() async {
        // The writer never closes the pipe: the reader must return on its own
        // once the third malformed line lands, and the good line after it must
        // never be delivered.
        let values = await run { writer in
            writer.write(Data("nope\nnope\nnope\n".utf8))
            writer.write(Data("{\"id\":9}\n".utf8))
        }

        XCTAssertEqual(values, [])
    }

    func testValidLineResetsMalformedCounter() async {
        let first = PipePayload(id: 1)
        let second = PipePayload(id: 2)
        let values = await run { writer in
            var data = Data("nope\nnope\n".utf8)
            data.append(line(first))
            data.append(Data("nope\nnope\n".utf8))
            data.append(line(second))
            writer.write(data)
            try? writer.close()
        }

        XCTAssertEqual(values, [first, second])
    }
}
