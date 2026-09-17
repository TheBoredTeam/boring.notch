#!/usr/bin/env python3
"""Compile the production reply flow with in-memory stand-ins; no app services."""

import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--work-dir", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
work = args.work_dir or Path(tempfile.mkdtemp(prefix="pr1057-reply-"))
work.mkdir(parents=True, exist_ok=True)
source = (root / "boringNotch/managers/SystemNotificationManager.swift").read_text()
helper = root / "BoringNotchXPCHelper/MessagesSender.swift"
# Refuse to compile a historical helper that could invoke real Apple events.
assert "NSAppleScript" not in helper.read_text(), "Unsafe name-based sender remains"
assert "sendIMessage" not in source, "App still attempts a name-based send"
assert "imessageScriptTimeout" not in source, "Unused script timeout remains"
drafts = source[source.index("    private var replyDrafts:"):source.index("    /// Shows the oldest queued")]
reply = source[source.index("    enum ReplyOutcome {"):source.index("    /// Only on a real send.")]
fixture = r'''
import Foundation
struct SystemNotification: Sendable {
    let id = "fixture"
    let appName: String? = "Fixture App"
    let bundleID: String?
    let sender: String?
    var isLive = false
}
@MainActor enum Fixture {
    static var events: [String] = []
    static var banner: Bool? = false
    static var opens = true
    static var phone: String? = "+15551234567"
    static var openedURL: URL?
}
@MainActor final class XPCHelperClient {
    static let shared = XPCHelperClient()
    func replyToNotification(token: String, text: String) async -> Bool {
        Fixture.events.append("banner")
        if let result = Fixture.banner { return result }
        try? await Task.sleep(for: .seconds(30))
        return true // A late successful callback must not start another send.
    }
}
@MainActor final class ContactAvatarManager {
    static let shared = ContactAvatarManager()
    func phoneNumber(forContactNamed name: String) async -> String? {
        Fixture.events.append("contacts")
        return Fixture.phone
    }
}
@MainActor final class NSWorkspace {
    static let shared = NSWorkspace()
    func open(_ url: URL) -> Bool {
        Fixture.events.append("open-url")
        Fixture.openedURL = url
        return Fixture.opens
    }
}
@MainActor final class NSPasteboard {
    static let general = NSPasteboard()
    enum PasteboardType { case string }
    func clearContents() { Fixture.events.append("clear-clipboard") }
    func setString(_ text: String, forType: PasteboardType) { Fixture.events.append("clipboard") }
}
@MainActor final class SystemNotificationManager {
    func playSentSound() { Fixture.events.append("sent-sound") }
    func playHandOffSound() { Fixture.events.append("handoff-sound") }
    func dismissActive(token: String) { Fixture.events.append("dismiss") }
    func open(_ notification: SystemNotification) async { Fixture.events.append("open-app") }
'''
checks = r'''
}
@main struct ReplyRegression {
    static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        precondition(condition(), label)
    }
    @MainActor static func main() async throws {
        for name in ["", "   ", "Shared Name", "Unique Name", "\"\\\n", "नमस्ते"] {
            check(!MessagesSender.send("draft", toChatNamed: name), "name sender must refuse")
        }
        print("PASS: all display names are refused, including empty, ambiguous, unique and escaped names")
        let manager = SystemNotificationManager()
        let text = "Hello & goodbye+again #100% \"quoted\" 'single' नमस्ते 👋\nline 2"
        manager.setDraft(text, for: "fixture")
        for name: String? in [nil, "", "Shared Name", "Unique Name"] {
            Fixture.events = []
            let notification = SystemNotification(bundleID: "com.apple.MobileSMS", sender: name)
            let result = await manager.reply(to: notification, text: text)
            check(result == .failed, "expired Messages must fail")
            check(manager.draft(for: "fixture") == text, "failed must preserve draft")
            check(Fixture.events == ["banner"], "failed must have no fallback or dismissal")
        }
        print("PASS: expired Messages returns failed, preserves draft and performs no fallback")
        Fixture.banner = true
        Fixture.events = []
        var live = SystemNotification(bundleID: "com.apple.MobileSMS", sender: "Shared Name")
        live.isLive = true
        let sent = await manager.reply(to: live, text: text)
        check(sent == .sent, "live banner send unchanged")
        check(Fixture.events == ["banner", "sent-sound", "dismiss"], "live send effects")
        print("PASS: live banner delivery still returns sent")
        for bundle in ["com.apple.MobileSMS", "net.whatsapp.WhatsApp"] {
            Fixture.banner = nil
            Fixture.events = []
            let result = await manager.reply(to: .init(bundleID: bundle, sender: "Shared Name"), text: text)
            check(result == .unknown, "deadline must remain unknown")
            check(Fixture.events == ["banner"], "unknown must not fall back")
            check(manager.draft(for: "fixture") == text, "unknown must preserve draft")
        }
        print("PASS: Messages and WhatsApp timeouts return unknown with draft intact and no fallback")
        Fixture.banner = false
        for opens in [true, false] {
            Fixture.opens = opens
            Fixture.events = []
            let result = await manager.reply(to: .init(bundleID: "net.whatsapp.WhatsApp", sender: "Fixture"), text: text)
            check(result == (opens ? .draftedInApp : .failed), "draft outcome must match URL opening")
            check(Fixture.openedURL == SystemNotificationManager.whatsAppDraftURL(phone: "+15551234567", text: text), "open the exact encoded draft")
            check(Fixture.events == (opens ? ["banner", "contacts", "open-url", "handoff-sound", "dismiss"] : ["banner", "contacts", "open-url"]), "WhatsApp effects")
            check(manager.draft(for: "fixture") == text, "manager retains draft")
        }
        print("PASS: WhatsApp URL-open success returns draftedInApp; failure returns failed without handoff")
        for value in [text, "hello&text=injected+tail", "&phone=999&text=injected#fragment", "%26 %2B + & # = ? /", ""] {
            guard let url = SystemNotificationManager.whatsAppDraftURL(phone: "+15551234567", text: value),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                preconditionFailure("URL construction failed")
            }
            check(components.fragment == nil, "text must not become a fragment")
            check(components.queryItems == [URLQueryItem(name: "phone", value: "+15551234567"), URLQueryItem(name: "text", value: value)], "query round trip")
            check(!(components.percentEncodedQuery ?? "").contains("+"), "form decoders must preserve plus")
        }
        print("PASS: &, +, #, %, quotes, Unicode and injection-like text round-trip as one query value")
        let oldText = "hello&text=injected+tail"
        guard let encoded = oldText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let old = URLComponents(string: "whatsapp://send?phone=1555&text=\(encoded)") else {
            preconditionFailure("baseline reproduction failed")
        }
        check(old.queryItems?.count == 3, "baseline must reproduce split text")
        print("BEFORE: hello&text=injected+tail becomes 3 query items; AFTER: it remains one text value")
    }
}
'''
swift = work / "ReplyRegression.swift"
swift.write_text(fixture + drafts + reply + checks)
binary = work / "reply-regression"
subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(work / "module-cache"),
                "-parse-as-library", str(swift), str(helper), "-o", str(binary)], check=True)
subprocess.run([str(binary)], check=True)
