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
    /// Resolves the notification's sender to a Messages conversation and
    /// sends the reply INTO that conversation, so the account, service
    /// (iMessage/SMS/RCS), handle, and thread of the originating chat are
    /// preserved. Returns false when no conversation resolves
    /// unambiguously (or automation permission was denied) — a
    /// wrong-person/wrong-thread send is worse than no send, and the
    /// caller falls back to the clipboard hand-off.
    static func send(_ text: String, toChatNamed name: String) -> Bool {
        // Chat-first, matching on the chat's PARTICIPANTS — never on the
        // chat's own name: verified against a real Messages library,
        // `name of chat` returns `missing value` for every 1:1 chat, so
        // matching on it can never succeed. Participants do carry the
        // display name the notification shows ("Harsh Vardhan Goswami"),
        // which is the only thing a notification gives us. AppleScript's
        // `is equal to` on strings ignores case by default, which is what
        // we want here.
        //
        // Resolution order:
        //   1. A chat with exactly ONE participant matching — the 1:1
        //      thread is the originating conversation; sending into the
        //      chat keeps its account/service/handle/thread.
        //   2. The first GROUP chat containing a matching participant —
        //      still a real conversation, so routing is preserved.
        //   3. A bare participant, ONLY if exactly one participant in the
        //      whole library matches. A participant has no thread context,
        //      and duplicates for the same person across handles/services
        //      (e:me@…, +9198…) are normal — 2+ matches is ambiguous and
        //      must not be guessed.
        let script = """
        tell application "Messages"
            set targetName to "\(escape(name))"
            set replyText to "\(escape(text))"

            set groupMatch to missing value
            repeat with c in chats
                try
                    set matched to false
                    repeat with p in participants of c
                        try
                            if (name of p as string) is equal to targetName then
                                set matched to true
                                exit repeat
                            end if
                        end try
                    end repeat
                    if matched then
                        if (count of participants of c) is 1 then
                            send replyText to c
                            return "ok-chat-1v1"
                        else if groupMatch is missing value then
                            set groupMatch to c
                        end if
                    end if
                end try
            end repeat
            if groupMatch is not missing value then
                send replyText to groupMatch
                return "ok-chat-group"
            end if

            set matchCount to 0
            set soleMatch to missing value
            repeat with p in participants
                try
                    if (name of p as string) is equal to targetName then
                        set matchCount to matchCount + 1
                        set soleMatch to p
                    end if
                end try
            end repeat
            if matchCount is 1 then
                send replyText to soleMatch
                return "ok-participant"
            else if matchCount is 0 then
                return "notfound"
            else
                return "ambiguous"
            end if
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

        // Any "ok-*" status is a successful send; the suffix says which
        // resolution path delivered it so routing decisions are
        // diagnosable from the log. "notfound" and "ambiguous" both map
        // to false — never send when unsure.
        let status = output.stringValue ?? ""
        switch status {
        case "ok-chat-1v1":
            NSLog("[boringNotch] Messages: sent into 1:1 chat with \(name.debugDescription) (account/service/handle/thread preserved)")
        case "ok-chat-group":
            NSLog("[boringNotch] Messages: no 1:1 chat for \(name.debugDescription); sent into first matching group chat")
        case "ok-participant":
            NSLog("[boringNotch] Messages: no chat matched \(name.debugDescription); sent to the single matching participant")
        case "notfound":
            NSLog("[boringNotch] Messages: no chat or participant named \(name.debugDescription)")
        case "ambiguous":
            NSLog("[boringNotch] Messages: \(name.debugDescription) matches multiple participants across handles/services — refusing to guess")
        default:
            NSLog("[boringNotch] Messages: unexpected status \(status.debugDescription) for \(name.debugDescription)")
        }
        return status.hasPrefix("ok")
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
