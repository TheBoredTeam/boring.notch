//
//  ErrorAlert.swift
//  boringNotch
//
//  Created by weitheng on 2025-07-28.
//

import AppKit
import SwiftUI
import OSLog

/// Helper class for presenting error alerts to the user
public class ErrorAlert {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "boringNotch", category: "ErrorAlert")
    
    /// Present an error alert to the user
    /// - Parameters:
    ///   - error: The error to present
    ///   - window: Optional window to attach the alert to
    ///   - completion: Optional completion handler called when the alert is dismissed
    public static func present(_ error: Error, in window: NSWindow? = nil, completion: (() -> Void)? = nil) {
        logger.error("Presenting error: \(error.localizedDescription)")
        
        let alert = NSAlert()
        
        // Configure alert based on error type
        if let appError = error as? AppError {
            alert.messageText = appError.localizedDescription
            alert.informativeText = appError.recoverySuggestion ?? ""
            
            // Add custom icon based on error type
            switch appError {
            case .permissionDenied, .mediaPermissionDenied, .calendarAccessDenied:
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "OK")
            case .musicServiceUnavailable, .mediaControllerNotFound:
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
            default:
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
            }
        } else {
            // Generic error presentation
            alert.messageText = "An error occurred"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
        }
        
        // Present the alert
        if let window = window {
            alert.beginSheetModal(for: window) { response in
                handleAlertResponse(response, for: error)
                completion?()
            }
        } else {
            let response = alert.runModal()
            handleAlertResponse(response, for: error)
            completion?()
        }
    }
    
    /// Present an error using SwiftUI alert modifier
    /// - Parameter error: The error to convert to alert data
    /// - Returns: Alert configuration for SwiftUI
    public static func alertData(for error: Error) -> Alert {
        if let appError = error as? AppError {
            switch appError {
            case .permissionDenied, .mediaPermissionDenied, .calendarAccessDenied:
                return Alert(
                    title: Text("Permission Required"),
                    message: Text(appError.localizedDescription),
                    primaryButton: .default(Text("Open Settings")) {
                        openSystemSettings(for: appError)
                    },
                    secondaryButton: .cancel()
                )
            default:
                return Alert(
                    title: Text("Error"),
                    message: Text(appError.localizedDescription + "\n\n" + (appError.recoverySuggestion ?? "")),
                    dismissButton: .default(Text("OK"))
                )
            }
        } else {
            return Alert(
                title: Text("Error"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private static func handleAlertResponse(_ response: NSApplication.ModalResponse, for error: Error) {
        if response == .alertFirstButtonReturn {
            if let appError = error as? AppError {
                switch appError {
                case .permissionDenied, .mediaPermissionDenied, .calendarAccessDenied:
                    openSystemSettings(for: appError)
                default:
                    break
                }
            }
        }
    }
    
    private static func openSystemSettings(for error: AppError) {
        var settingsPane = ""
        
        switch error {
        case .permissionDenied(let permission):
            switch permission {
            case .calendar:
                settingsPane = "Privacy_Calendars"
            case .mediaLibrary:
                settingsPane = "Privacy_Media"
            case .camera:
                settingsPane = "Privacy_Camera"
            case .microphone:
                settingsPane = "Privacy_Microphone"
            case .screenRecording:
                settingsPane = "Privacy_ScreenCapture"
            }
        case .calendarAccessDenied:
            settingsPane = "Privacy_Calendars"
        case .mediaPermissionDenied:
            settingsPane = "Privacy_Media"
        default:
            return
        }
        
        if !settingsPane.isEmpty {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsPane)")!
            NSWorkspace.shared.open(url)
            logger.info("Opened system settings for: \(settingsPane)")
        }
    }
}

// MARK: - SwiftUI View Extension
public extension View {
    /// Present an error alert when the error binding is not nil
    func errorAlert(_ error: Binding<Error?>) -> some View {
        self.alert(isPresented: .constant(error.wrappedValue != nil)) {
            if let error = error.wrappedValue {
                return ErrorAlert.alertData(for: error)
            } else {
                return Alert(title: Text("Error"), message: nil, dismissButton: .default(Text("OK")))
            }
        }
        .onChange(of: error.wrappedValue == nil) { _ in
            if error.wrappedValue == nil {
                // Error was cleared
            }
        }
    }
}