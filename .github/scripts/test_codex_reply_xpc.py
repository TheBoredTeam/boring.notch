#!/usr/bin/env python3
"""Verify the real reply helper from an app with the product's sandbox entitlements.

Requires a fresh Debug app and an explicitly authorized disposable Codex thread.
Sends one fixed synthetic message. Never use a private/production conversation.
"""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import uuid


ROOT = Path(__file__).resolve().parents[2]
PROBE = r'''
import AppKit
import Foundation

final class Probe: NSObject, NSApplicationDelegate {
    var connection: NSXPCConnection?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let sessionID = CommandLine.arguments[1]
            let turnID = CommandLine.arguments[2]
            let message = "This is an authorized Boring Notch sandbox-to-helper delivery test. Do not use tools or edit files. Reply exactly: Notch helper reply received."
            let executable = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")!
                .appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
            let direct = await CodexReplyTransport(executableURL: executable)
                .send(sessionID: sessionID, turnID: turnID, text: message)
            print("Direct sandboxed send:", direct.rawValue)
            guard direct == .unavailable || direct == .failed else { exit(1) }
            let conn = NSXPCConnection(serviceName: "theboringteam.boringnotch.BoringNotchXPCHelper")
            connection = conn
            conn.remoteObjectInterface = NSXPCInterface(with: BoringNotchXPCHelperProtocol.self)
            conn.resume()
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                print("Helper connection error code:", (error as NSError).code)
                exit(1)
            } as! BoringNotchXPCHelperProtocol
            proxy.sendCodexReply(sessionID: sessionID, turnID: turnID, message: message) { value in
                print("Helper send:", value)
                exit(value == "queued" || value == "queuedNeedsOpen" ? 0 : 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { exit(1) }
    }
}
let app = NSApplication.shared
let probe = Probe()
app.delegate = probe
app.setActivationPolicy(.prohibited)
app.run()
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--thread", type=uuid.UUID, required=True)
    parser.add_argument("--turn", type=uuid.UUID, required=True)
    args = parser.parse_args()
    helper = args.app / "Contents/XPCServices/BoringNotchXPCHelper.xpc"
    assert helper.is_dir(), "Build the Debug app and helper first"
    with tempfile.TemporaryDirectory(prefix="boring-notch-reply-xpc-") as directory:
        scratch = Path(directory)
        host = scratch / "ReplyProbe.app"
        contents = host / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "XPCServices").mkdir()
        info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
        # Reuse the product's container identity without reading/writing settings.
        probe_info = {key: info[key] for key in ["CFBundleIdentifier", "CFBundlePackageType"]}
        probe_info.update(CFBundleExecutable="ReplyProbe", CFBundleName="ReplyProbe", LSUIElement=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps(probe_info))
        subprocess.run(["/usr/bin/ditto", str(helper), str(contents / "XPCServices" / helper.name)], check=True)
        source = scratch / "main.swift"
        source.write_text(PROBE)
        binary = contents / "MacOS/ReplyProbe"
        subprocess.run([
            "swiftc", "-module-cache-path", "/tmp/boring-notch-swift-module-cache",
            str(ROOT / "boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift"),
            str(ROOT / "boringNotch/features/CodexNotifications/CodexReplyTransport.swift"),
            str(ROOT / "boringNotch/features/CodexNotifications/CodexReplyOutcome.swift"),
            str(source), "-o", str(binary),
        ], check=True)
        signed = subprocess.run([
            "/usr/bin/codesign", "-d", "--entitlements", ":-", str(args.app)
        ], capture_output=True, check=True)
        entitlements = plistlib.loads(signed.stdout)
        assert entitlements.get("com.apple.security.app-sandbox") is True
        entitlements_file = scratch / "probe.entitlements"
        entitlements_file.write_bytes(plistlib.dumps(entitlements))
        subprocess.run([
            "/usr/bin/codesign", "--force", "--sign", "-", "--entitlements",
            str(entitlements_file), str(host),
        ], capture_output=True, check=True)
        print("Probe uses the product's App Sandbox entitlements.", flush=True)
        environment = dict(os.environ)
        # Match GUI launch: a terminal's CODEX_HOME must not mask sandbox behavior.
        environment.pop("CODEX_HOME", None)
        subprocess.run([str(binary), str(args.thread), str(args.turn)], env=environment, check=True, timeout=50)


if __name__ == "__main__":
    main()
