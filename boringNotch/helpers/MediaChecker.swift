//
//  MediaChecker.swift
//  boringNotch
//
//  Created by Alexander on 2025-07-26.
//

import Foundation

struct MediaChecker: NowPlayingAvailabilityChecking {
    func checkAvailability(maxAttempts: Int = 3) async throws -> NowPlayingAvailability {
        let attempts = max(1, maxAttempts)

        for attempt in 1...attempts {
            try Task.checkCancellation()
            let availability = try await runAvailabilityCheck()
            guard availability.shouldRetry, attempt < attempts else {
                return availability
            }

            try await Task.sleep(for: .milliseconds(350 * attempt))
        }

        return .unchecked
    }

    private func runAvailabilityCheck() async throws -> NowPlayingAvailability {
        let resources: NowPlayingResources
        do {
            resources = try NowPlayingResources.load(requiresTestClient: true)
        } catch let failure as NowPlayingSetupFailure {
            return .setupFailure(failure)
        } catch {
            return .setupFailure(.missingAdapterScript)
        }

        guard let testClientURL = resources.testClientURL else {
            return .setupFailure(.missingTestClient)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            resources.adapterScriptURL.path,
            resources.adapterFrameworkPath,
            testClientURL.path,
            "test",
        ]

        let result: TimedProcessResult
        do {
            result = try await TimedProcessRunner.run(process, timeout: .seconds(10))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .temporaryFailure(.launchFailed)
        }

        switch result {
        case .timedOut:
            return .temporaryFailure(.timedOut)
        case .terminated(let termination):
            return Self.availability(for: termination)
        }
    }

    static func availability(
        for termination: ChildProcessTermination
    ) -> NowPlayingAvailability {
        switch termination {
        case .exited(0):
            return .available
        case .exited(1):
            return .temporaryFailure(.helperPathMissing)
        case .exited(2):
            return .temporaryFailure(.helperLaunchFailed)
        case .exited(3):
            return .temporaryFailure(.helperSetupTimedOut)
        case .exited(4):
            return .temporaryFailure(.noData)
        case .exited(64):
            return .temporaryFailure(.wrapperFailed)
        case .exited(let status):
            return .temporaryFailure(.unexpectedExit(status))
        case .signaled(let signal):
            return .temporaryFailure(.signaled(signal))
        case .unknown(let status):
            return .temporaryFailure(.unexpectedExit(status))
        }
    }
}
