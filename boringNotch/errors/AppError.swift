//
//  AppError.swift
//  boringNotch
//
//  Created by boringNotch on 2025-07-28.
//

import Foundation

/// Comprehensive error types for the boringNotch application
public enum AppError: LocalizedError {
    // MARK: - Media Errors
    case musicServiceUnavailable
    case mediaControllerNotFound(MediaControllerType)
    case playbackFailed(reason: String)
    case mediaPermissionDenied
    
    // MARK: - System Errors
    case appleScriptExecutionFailed(script: String, error: String)
    case permissionDenied(permission: SystemPermission)
    case systemServiceUnavailable(service: String)
    
    // MARK: - Network Errors
    case networkError(URLError)
    case apiResponseInvalid(reason: String)
    
    // MARK: - State Errors
    case invalidState(description: String)
    case windowNotFound(identifier: String)
    
    // MARK: - File System Errors
    case fileNotFound(path: String)
    case fileOperationFailed(operation: String, path: String)
    
    // MARK: - Calendar Errors
    case calendarAccessDenied
    case eventNotFound(identifier: String)
    
    // MARK: - General Errors
    case unknown(Error)
    
    public var errorDescription: String? {
        switch self {
        case .musicServiceUnavailable:
            return "Music service is not available"
        case .mediaControllerNotFound(let type):
            return "\(type.displayName) is not available"
        case .playbackFailed(let reason):
            return "Playback failed: \(reason)"
        case .mediaPermissionDenied:
            return "Media library access denied"
        case .appleScriptExecutionFailed(let script, let error):
            return "Script execution failed: \(error)"
        case .permissionDenied(let permission):
            return "\(permission.displayName) access denied"
        case .systemServiceUnavailable(let service):
            return "\(service) service is unavailable"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiResponseInvalid(let reason):
            return "Invalid API response: \(reason)"
        case .invalidState(let description):
            return "Invalid state: \(description)"
        case .windowNotFound(let identifier):
            return "Window not found: \(identifier)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileOperationFailed(let operation, let path):
            return "\(operation) failed for: \(path)"
        case .calendarAccessDenied:
            return "Calendar access denied"
        case .eventNotFound(let identifier):
            return "Calendar event not found: \(identifier)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .musicServiceUnavailable:
            return "Make sure the music app is running and try again"
        case .mediaControllerNotFound(let type):
            return "Ensure \(type.displayName) is installed and running"
        case .playbackFailed:
            return "Check if the media file is valid and try again"
        case .mediaPermissionDenied:
            return "Grant media library access in System Settings > Privacy & Security"
        case .appleScriptExecutionFailed:
            return "Check if the target application is installed and running"
        case .permissionDenied(let permission):
            return permission.recoverySuggestion
        case .systemServiceUnavailable:
            return "Restart the application or check system settings"
        case .networkError:
            return "Check your internet connection and try again"
        case .apiResponseInvalid:
            return "Try again later or contact support if the issue persists"
        case .invalidState:
            return "Restart the application"
        case .windowNotFound:
            return "The window may have been closed. Try reopening it"
        case .fileNotFound:
            return "Check if the file exists at the specified location"
        case .fileOperationFailed:
            return "Check file permissions and available disk space"
        case .calendarAccessDenied:
            return "Grant calendar access in System Settings > Privacy & Security > Calendar"
        case .eventNotFound:
            return "The event may have been deleted or modified"
        case .unknown:
            return "An unexpected error occurred. Please try again"
        }
    }
    
    public var failureReason: String? {
        errorDescription
    }
}

/// System permissions that can be requested
public enum SystemPermission: String {
    case calendar = "Calendar"
    case mediaLibrary = "Media Library"
    case camera = "Camera"
    case microphone = "Microphone"
    case screenRecording = "Screen Recording"
    
    var displayName: String {
        rawValue
    }
    
    var recoverySuggestion: String {
        "Go to System Settings > Privacy & Security > \(rawValue) and enable access for Boring Notch"
    }
}

/// Extension to make MediaControllerType compatible with error handling
extension MediaControllerType {
    var displayName: String {
        switch self {
        case .nowPlaying:
            return "Now Playing"
        case .appleMusic:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        case .youtubeMusic:
            return "YouTube Music"
        }
    }
}