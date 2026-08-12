//
//  MessagesSender.swift
//  BoringNotchXPCHelper
//
//  Sends iMessage replies through the Messages scripting dictionary.
//
//  Why this exists: replying to a notification normally means typing into
//  the system banner's own AX reply field, which stops working the moment
//  that banner fades (~5s) — the element is destroyed, measured, not
//  assumed. Messages is the one supported app with a real scripting
//  dictionary (`send <text> to <chat|participant>`), so an iMessage reply
//  can be delivered properly at any time, with no dependency on the
//  notification still existing.
//
//  There is no equivalent for WhatsApp/Telegram/Discord — none ship a
//  scripting dictionary, and driving their UI with simulated clicks is far
//  too brittle to put behind a send button. Those keep the clipboard
//  hand-off.
//
//  Lives in the helper because the app is sandboxed; sending Apple events
//  to another app needs the unsandboxed context the helper already has.
//

import Foundation
import AppKit

enum MessagesSender {
    /// Matches the notification's sender against a Messages chat (then a
    /// participant) and sends. Returns false if the chat can't be resolved
    /// or automation permission was denied, so the caller can fall back to
    /// the clipboard hand-off.
    static func send(_ text: String, toChatNamed name: String) -> Bool {
        // Participants only — deliberately not chats. Verified against a
        // real Messages library: `name of chat` returns `missing value` for
        // every chat, so matching on it can never succeed. Participants do
        // carry the display name the notification shows ("Harsh Vardhan
        // Goswami"), which is the only thing a notification gives us.
        //
        // The first match wins. Duplicate participant entries for the same
        // person are normal (one per handle/service — e:me@…, +9198…), and
        // they all reach the same human, so picking the first is fine.
        let script = """
        tell application "Messages"
            repeat with p in participants
                try
                    if (name of p as string) is equal to "\(escape(name))" then
                        send "\(escape(text))" to p
                        return "ok"
                    end if
                end try
            end repeat
        end tell
        return "notfound"
        """

        guard let scriptObject = NSAppleScript(source: script) else { return false }

        var error: NSDictionary?
        let output = scriptObject.executeAndReturnError(&error)

        if let error {
            // -1743 is "not authorized to send Apple events" — the user
            // declined the Automation prompt, which is a legitimate choice,
            // not a bug. Everything else is worth seeing in the log.
            NSLog("[boringNotch] Messages send failed: \(error)")
            return false
        }

        let ok = output.stringValue == "ok"
        if !ok {
            NSLog("[boringNotch] Messages: no chat or participant named \(name.debugDescription)")
        }
        return ok
    }

    /// Message text is arbitrary user input going into an AppleScript
    /// string literal, so backslashes and quotes have to be neutralised —
    /// otherwise a quote in a reply breaks the script (or worse, changes
    /// what it does). Backslash first, or it would re-escape the escapes.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
