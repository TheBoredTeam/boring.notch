// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

import Combine
import Foundation

/// Inject a virtual scheduler in tests; advancing it never requires wall-clock waits.
@MainActor
protocol LiveActivityScheduling {
    var now: Date { get }
    func schedule(at deadline: Date, action: @escaping @MainActor () -> Void) -> AnyCancellable
}

@MainActor
final class LiveActivityScheduler: LiveActivityScheduling {
    var now: Date { Date() }

    func schedule(at deadline: Date, action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let task = Task { @MainActor in
            // Recheck the wall-clock deadline after waking. A machine sleep or a
            // clock adjustment must not let a stale scheduled callback end a renewal.
            while deadline > now {
                let delay = min(deadline.timeIntervalSince(now), 86_400)
                do {
                    try await Task.sleep(for: .seconds(max(0, delay)))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            action()
        }
        return AnyCancellable { task.cancel() }
    }
}
