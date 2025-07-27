//
//  MediaChecker.swift
//  boringNotch
//
//  Created by Alexander on 2025-07-26.
//

import Foundation

@MainActor
final class MediaChecker: Sendable {
    private(set) var isNowPlayingDeprecated: Bool = false

    enum MediaCheckerError: Error {
        case missingResources
        case processExecutionFailed
        case timeout
    }

    func checkDeprecationStatus() async throws -> Bool {
        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let nowPlayingTestClientPath = Bundle.main.url(forResource: "NowPlayingTestClient", withExtension: nil)?.path,
              let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            throw MediaCheckerError.missingResources
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, nowPlayingTestClientPath, "test"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            throw MediaCheckerError.processExecutionFailed
        }

        // Timeout after 10 seconds
        let result: String = try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                if process.isRunning {
                    process.terminate()
                }
                return "0" // Default value if process takes too long
            }
            for try await output in group {
                if let output = output {
                    group.cancelAll()
                    return output
                }
            }
            throw MediaCheckerError.timeout
        }

        let isDeprecated = result.trimmingCharacters(in: .whitespacesAndNewlines).last == "1"
        self.isNowPlayingDeprecated = isDeprecated
        return isDeprecated
    }
}
