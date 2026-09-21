//
//  MessagesSender.swift
//  BoringNotchXPCHelper
//
//  Compatibility entry point for clients using the existing XPC interface.
//

import Foundation

enum MessagesSender {
    /// A notification display name cannot identify its originating account,
    /// handle, or conversation, even when only one matching name exists.
    /// Keep the XPC entry point compatible, but never send using a name.
    static func send(_ text: String, toChatNamed name: String) -> Bool {
        false
    }
}
