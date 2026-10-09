//
//  main.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import Security

private enum XPCClientCodeSigningRequirement {
    private static let bundleIdentifier = "theboringteam.boringnotch"

    static let value: String = {
        let identifierRequirement = #"identifier "\(bundleIdentifier)""#

        #if DEBUG
        // Developer builds are ad-hoc signed, so a stable Team ID is unavailable.
        // This is a local-development constraint; never use this weaker check for Release.
        return identifierRequirement
        #else
        var code: SecCode?
        var staticCode: SecStaticCode?
        var signingInfo: CFDictionary?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code,
              SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode,
              SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &signingInfo
              ) == errSecSuccess,
              let dictionary = signingInfo as? [CFString: Any],
              let teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier] as? String,
              !teamIdentifier.isEmpty,
              teamIdentifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else {
            // Fail closed if the embedded helper does not have a valid signing team.
            return #"identifier "theboringteam.invalid-client" and anchor apple"#
        }

        return #"identifier "\(bundleIdentifier)" and anchor apple generic and certificate leaf[subject.OU] = "\#(teamIdentifier)""#
        #endif
    }()
}

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    /// This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Defense in depth: the code-signing requirement is installed on the listener
        // before it resumes, and this additionally restricts the service to this user.
        guard newConnection.effectiveUserIdentifier == geteuid() else {
            newConnection.invalidate()
            return false
        }

        // Configure the connection.
        // First, set the interface that the exported object implements.
        newConnection.exportedInterface = NSXPCInterface(with: (any BoringNotchXPCHelperProtocol).self)

        // Configure the interface for callbacks from the helper to the app.
        let listenerInterface = NSXPCInterface(with: (any BoringNotchXPCAppDelegate).self)
        listenerInterface.setClasses(
            NSSet(array: [BNLunarBrightnessEvent.self]) as! Set<AnyHashable>,
            for: #selector(BoringNotchXPCHelperLunarListener.lunarEventDidUpdate(_:)),
            argumentIndex: 0,
            ofReply: false
        )
        newConnection.remoteObjectInterface = listenerInterface

        // Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
        let exportedObject = BoringNotchXPCHelper(connection: newConnection)
        newConnection.exportedObject = exportedObject

        // Resuming the connection allows the system to deliver more incoming messages.
        newConnection.resume()

        // Returning true from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call invalidate() on the connection and return false.
        return true
    }
}

// Create the delegate for the service.
let delegate = ServiceDelegate()

// Set up the one NSXPCListener for this service. It will handle all incoming connections.
let listener = NSXPCListener.service()
listener.setConnectionCodeSigningRequirement(XPCClientCodeSigningRequirement.value)
listener.delegate = delegate

// Resuming the serviceListener starts this service. This method does not return.
listener.resume()
