//
//  MediaChecker.swift
//  boringNotch
//
//  Created by Alexander on 2025-07-26.
//

import Foundation

struct MediaChecker: Sendable {
    func checkAvailability(maxAttempts: Int = 3) async throws -> NowPlayingAvailability {
        let attempts = max(1, maxAttempts)

        for attempt in 1...attempts {
            try Task.checkCancellation()
            do {
                if try await runAvailabilityCheck() {
                    return .available
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A failed launch can be as transient as a failed probe, so retry it too.
            }

            if attempt < attempts {
                try await Task.sleep(for: .milliseconds(350 * attempt))
            }
        }

        return .unavailable
    }

    private func runAvailabilityCheck() async throws -> Bool {
        let resources = try NowPlayingResources.load()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            resources.adapterScriptURL.path,
            resources.adapterFrameworkPath,
            resources.testClientURL.path,
            "test",
        ]

        return try await TimedProcessRunner.exitsSuccessfully(
            process,
            timeout: .seconds(10)
        )
    }
}
