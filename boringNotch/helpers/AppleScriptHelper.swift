//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

class AppleScriptHelper {
    /// `NSAppleScript.executeAndReturnError` is a *blocking* call, and an Apple Event to an
    /// unresponsive app can block for up to the Apple Event timeout (~2 min). The previous
    /// implementation ran it via `Task.detached`, i.e. on Swift's *shared cooperative thread pool*
    /// (~one thread per core). A hung target app (e.g. Kaset with a broken API) polled every couple
    /// of seconds then piled up blocked calls and starved that pool, wedging app-wide async work and
    /// freezing the notch.
    ///
    /// Running it on a dedicated *serial* queue isolates the blocking from the cooperative pool: a
    /// hung app blocks only this one queue (its data just goes stale) and never freezes the UI, and
    /// serial execution caps it at a single blocked thread even under repeated polling.
    private static let queue = DispatchQueue(
        label: "com.theboringteam.boringnotch.applescript",
        qos: .userInitiated
    )

    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }

    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
