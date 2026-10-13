//
//  JSONLinesPipeHandler.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Shared source compiled into BOTH targets (via the Shared synchronized
//  group). There is intentionally one copy — edit once, both sides build it.
//

import Foundation
import Darwin

/// Streams newline-delimited JSON from a pipe, decoding each line.
/// Used by the app (mediaremote-adapter now-playing stream) and the XPC
/// helper (Lunar daemon event stream).
actor JSONLinesPipeHandler {
    nonisolated let outputPipe: Pipe
    nonisolated let fileHandle: FileHandle
    private nonisolated let chunks: AsyncStream<Data>
    private nonisolated let continuation: AsyncStream<Data>.Continuation

    init(pipe: Pipe = Pipe()) {
        outputPipe = pipe
        fileHandle = pipe.fileHandleForReading
        let channel = AsyncStream<Data>.makeStream()
        chunks = channel.stream
        continuation = channel.continuation
    }

    func readJSONLines<Value: Decodable & Sendable>(
        as type: Value.Type,
        onValue: @escaping @Sendable (Value) async -> Void
    ) async {
        let handle = fileHandle
        let descriptor = handle.fileDescriptor
        let continuation = continuation
        handle.readabilityHandler = { handle in
            var data = Data(count: 65_536)
            let count = data.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.count = count
                continuation.yield(data)
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                handle.readabilityHandler = nil
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in handle.readabilityHandler = nil }
        defer { handle.readabilityHandler = nil }
        var buffer = Data()
        var malformedLines = 0
        for await chunk in chunks {
            guard !Task.isCancelled else { return }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                var line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if line.last == 0x0D { line.removeLast() }
                guard !line.isEmpty,
                      let value = try? JSONDecoder().decode(Value.self, from: line) else {
                    malformedLines += 1
                    if malformedLines >= 3 { return }
                    continue
                }
                malformedLines = 0
                await onValue(value)
            }
        }
        if !Task.isCancelled, !buffer.isEmpty,
           let value = try? JSONDecoder().decode(Value.self, from: buffer) {
            await onValue(value)
        }
    }

    nonisolated func close() {
        continuation.finish()
        fileHandle.readabilityHandler = nil
        try? fileHandle.close()
        try? outputPipe.fileHandleForWriting.close()
    }
}
