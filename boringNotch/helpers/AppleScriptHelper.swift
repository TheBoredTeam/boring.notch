//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import OSLog

class AppleScriptHelper {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringNotch", category: "AppleScript")
    
    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        logger.debug("Executing AppleScript")
        
        // Log script for debugging (be careful with sensitive data)
        if scriptText.count < 200 {
            logger.debug("Script: \(scriptText)")
        } else {
            logger.debug("Script: \(scriptText.prefix(100))... (truncated)")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                guard let script = NSAppleScript(source: scriptText) else {
                    logger.error("Failed to create NSAppleScript from source")
                    continuation.resume(throwing: AppError.appleScriptExecutionFailed(
                        script: scriptText.prefix(100) + "...",
                        error: "Failed to create script object"
                    ))
                    return
                }
                
                var errorDict: NSDictionary?
                let descriptor = script.executeAndReturnError(&errorDict)
                
                if let descriptor = descriptor {
                    logger.info("AppleScript executed successfully")
                    continuation.resume(returning: descriptor)
                } else if let errorDict = errorDict {
                    let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? -1
                    
                    logger.error("AppleScript execution failed: \(errorMessage) (code: \(errorNumber))")
                    
                    continuation.resume(throwing: AppError.appleScriptExecutionFailed(
                        script: scriptText.prefix(100) + "...",
                        error: "\(errorMessage) (code: \(errorNumber))"
                    ))
                } else {
                    logger.error("AppleScript execution failed with unknown error")
                    continuation.resume(throwing: AppError.appleScriptExecutionFailed(
                        script: scriptText.prefix(100) + "...",
                        error: "Unknown error occurred"
                    ))
                }
            }
        }
    }
    
    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
    
    // MARK: - Safe Script Execution
    /// Execute a pre-validated script template with parameters
    class func executeSafe(template: String, parameters: [String: Any] = [:]) async throws -> NSAppleEventDescriptor? {
        logger.debug("Executing safe script template")
        
        // Sanitize parameters to prevent injection
        var sanitizedScript = template
        for (key, value) in parameters {
            let sanitizedValue = sanitizeValue(value)
            sanitizedScript = sanitizedScript.replacingOccurrences(of: "{\(key)}", with: sanitizedValue)
        }
        
        return try await execute(sanitizedScript)
    }
    
    private class func sanitizeValue(_ value: Any) -> String {
        let stringValue = String(describing: value)
        // Escape quotes and backslashes for AppleScript
        return stringValue
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
