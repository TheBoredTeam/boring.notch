//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import AppKit
import ApplicationServices
import IOKit
import OSLog
import Security

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {

    private static let codexLogger = Logger(
        subsystem: "theboringteam.boringnotch",
        category: "CodexNotificationAuthentication"
    )

    private weak var connection: NSXPCConnection?

    private let lunarStateQueue = DispatchQueue(label: "BoringNotchXPCHelper.lunar.state")
    private let lunarExecutableURL = URL(fileURLWithPath: "/Applications/Lunar.app/Contents/MacOS/Lunar")
    private var lunarProcess: Process?
    private var lunarPipeHandler: JSONLinesPipeHandler?
    private var lunarStreamTask: Task<Void, Never>?
    private var lunarListener: BoringNotchXPCHelperLunarListener?

    init(connection: NSXPCConnection) {
        self.connection = connection
        super.init()
    }

    override init() {
        super.init()
    }

    deinit {
        var processToTerminate: Process?
        var taskToCancel: Task<Void, Never>?
        var pipeHandlerToClose: JSONLinesPipeHandler?

        lunarStateQueue.sync {
            processToTerminate = self.lunarProcess
            self.lunarProcess = nil

            taskToCancel = self.lunarStreamTask
            self.lunarStreamTask = nil

            pipeHandlerToClose = self.lunarPipeHandler
            self.lunarPipeHandler = nil

            self.lunarListener = nil
        }

        taskToCancel?.cancel()
        if let p = processToTerminate, p.isRunning { p.terminate() }
        if let ph = pipeHandlerToClose {
            Task { await ph.close() }
        }
    }
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }

    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    private func brightnessDisplayID() -> CGDirectDisplayID {
        let mainDisplayID = CGMainDisplayID()
        var tmp: Float = 0

        if displayServicesGetBrightness(displayID: mainDisplayID, out: &tmp) || ioServiceFor(displayID: mainDisplayID) != nil {
            return mainDisplayID
        }

        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        let allocated = Int(count)
        var ids = [CGDirectDisplayID](repeating: 0, count: allocated)
        CGGetOnlineDisplayList(count, &ids, &count)
        for id in ids {
            if CGDisplayIsBuiltin(id) != 0 {
                return id
            }
        }

        return mainDisplayID
    }

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        let displayID = brightnessDisplayID()
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: displayID, out: &b) || ioServiceFor(displayID: displayID) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        let displayID = brightnessDisplayID()
        var b: Float = 0
        if displayServicesGetBrightness(displayID: displayID, out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        let displayID = brightnessDisplayID()
        if displayServicesSetBrightness(displayID: displayID, value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }
    
    @objc func adjustScreenBrightness(by value: Float, with reply: @escaping (Bool) -> Void) {
        let displayID = brightnessDisplayID()
        if displayServicesSetBrightnessSmooth(displayID: displayID, value: value) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: displayID) {
            var ioCurrent: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &ioCurrent) == kIOReturnSuccess {
                let target = max(0, min(1, ioCurrent + value))
                let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, target) == kIOReturnSuccess
                IOObjectRelease(io)
                reply(ok)
                return
            }
            IOObjectRelease(io)
        }
        reply(false)
    }

    // MARK: - Lunar Events

    @objc func displayIDForBrightness(with reply: @escaping (NSNumber?) -> Void) {
        let id = brightnessDisplayID()
        reply(NSNumber(value: id))
    }

    @objc func isLunarAvailable(with reply: @escaping (Bool) -> Void) {
        reply(FileManager.default.isExecutableFile(atPath: lunarExecutableURL.path))
    }

    @objc func startLunarEventStream(with reply: @escaping (Bool) -> Void) {
        lunarStateQueue.async { [weak self] in
            guard let self else {
                reply(false)
                return
            }

            if let lunarProcess = self.lunarProcess, lunarProcess.isRunning {
                reply(true)
                return
            }

            guard FileManager.default.isExecutableFile(atPath: self.lunarExecutableURL.path) else {
                reply(false)
                return
            }

            guard let connection = self.connection else {
                reply(false)
                return
            }

            let listenerProxy = connection.remoteObjectProxyWithErrorHandler { _ in
                self.stopLunarEventStream()
            } as? BoringNotchXPCHelperLunarListener

            guard let listenerProxy else {
                reply(false)
                return
            }

            let process = Process()
            process.executableURL = self.lunarExecutableURL
            process.arguments = ["@", "listen", "--only-user-adjustments", "-j"]

            let pipeHandler = JSONLinesPipeHandler(decoder: JSONDecoder())
            process.standardOutput = pipeHandler.getPipe()
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { [weak self] _ in
                self?.stopLunarEventStream(reason: "Lunar stream ended")
            }

            do {
                try process.run()
            } catch {
                reply(false)
                return
            }

            self.lunarProcess = process
            self.lunarPipeHandler = pipeHandler
            self.lunarListener = listenerProxy

            let currentPipeHandler = pipeHandler
            self.lunarStreamTask = Task { [weak self] in
                await self?.readLunarEvents(pipeHandler: currentPipeHandler)
            }

            reply(true)
        }
    }

    @objc func stopLunarEventStream() {
        stopLunarEventStream(reason: nil)
    }

    private func stopLunarEventStream(reason: String?) {
        lunarStateQueue.async { [weak self] in
            guard let self else { return }

            self.lunarStreamTask?.cancel()
            self.lunarStreamTask = nil

            if let lunarProcess = self.lunarProcess, lunarProcess.isRunning {
                lunarProcess.terminate()
            }

            self.lunarProcess = nil

            if let pipeHandler = self.lunarPipeHandler {
                Task { await pipeHandler.close() }
            }

            self.lunarPipeHandler = nil

            if let reason {
                self.lunarListener?.lunarStreamDidStop(reason)
            }

            self.lunarListener = nil
        }
    }

    private func readLunarEvents(pipeHandler: JSONLinesPipeHandler) async {
        await pipeHandler.readJSONLines(as: LunarBrightnessEvent.self) { [weak self] event in
            self?.emitLunarEvent(event)
        }
    }

    private func emitLunarEvent(_ event: LunarBrightnessEvent) {
        let payload = BNLunarBrightnessEvent(
            brightness: event.brightness,
            display: event.display
        )
        lunarStateQueue.async { [weak self] in
            self?.lunarListener?.lunarEventDidUpdate(payload)
        }
    }

    // MARK: - Lunar OSD preference (hideOSD)

    private static let lunarBundleID = "fyi.lunar.Lunar"
    private static let lunarHideOSDKey = "hideOSD"

    @objc func setLunarOSDHidden(_ hide: Bool, with reply: @escaping (Bool) -> Void) {
        let appID = Self.lunarBundleID as CFString
        let key = Self.lunarHideOSDKey as CFString
        let value = hide as CFBoolean
        NSLog("Hide OSD in Lunar: \(hide)")
        CFPreferencesSetValue(key, value, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let ok = CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        reply(ok)
    }

    // MARK: - Codex Notifications

    private static let codexHookEvents = CodexHookConfiguration.events
    private static let codexHookTrustEvents = [
        ("PermissionRequest", "permission_request"),
        ("UserPromptSubmit", "user_prompt_submit"),
        ("PostToolUse", "post_tool_use"),
        ("Stop", "stop"),
    ]
    private static let codexHookMarker = "boring-notch-notify.py"
    private static let codexHookSecretMarker = "boring-notch-notify.secret"
    private static let codexNotificationScript = #"""
    import base64
    import hashlib
    import hmac
    import json
    import os
    import secrets
    import subprocess
    import sys
    import time
    from http.server import BaseHTTPRequestHandler, HTTPServer

    MAX_PAYLOAD_BYTES = 256 * 1024
    MAX_PROMPT_CHARACTERS = 16_000
    MAX_DESCRIPTION_CHARACTERS = 16_000
    MAX_COMMAND_CHARACTERS = 96_000
    MAX_ADDITIONAL_INPUT_CHARACTERS = 64_000
    DELIVERY_TIMEOUT_SECONDS = 5
    DECISION_TIMEOUT_SECONDS = 60

    def short(value, limit=4000):
        if not isinstance(value, str):
            return value
        return value[:limit]

    def bounded_tool_input(value):
        if not isinstance(value, dict):
            return None

        bounded = {}
        description = value.get("description")
        if isinstance(description, str):
            bounded["description"] = short(description, MAX_DESCRIPTION_CHARACTERS)

        command = value.get("command")
        if isinstance(command, str):
            bounded["command"] = short(command, MAX_COMMAND_CHARACTERS)

        additional = {
            key: item
            for key, item in value.items()
            if key not in ("description", "command")
        }
        if additional:
            rendered = json.dumps(additional, separators=(",", ":"), ensure_ascii=False)
            if len(rendered) <= MAX_ADDITIONAL_INPUT_CHARACTERS:
                bounded.update(additional)
            else:
                bounded["additional_input"] = short(
                    rendered,
                    MAX_ADDITIONAL_INPUT_CHARACTERS,
                )
        return bounded

    def thread_metadata(session_id):
        metadata = {"chat_title": "Untitled chat"}
        if not isinstance(session_id, str) or not session_id:
            return metadata

        codex_home = os.path.dirname(os.path.abspath(__file__))
        try:
            with open(
                os.path.join(codex_home, "session_index.jsonl"),
                "r",
                encoding="utf-8",
            ) as index:
                for line in index:
                    try:
                        entry = json.loads(line)
                    except (TypeError, ValueError):
                        continue
                    if entry.get("id") != session_id:
                        continue
                    title = entry.get("thread_name")
                    if isinstance(title, str) and title.strip():
                        metadata["chat_title"] = short(title.strip(), 240)
        except (FileNotFoundError, OSError, UnicodeError):
            pass

        try:
            with open(
                os.path.join(codex_home, ".codex-global-state.json"),
                "r",
                encoding="utf-8",
            ) as state_file:
                state = json.load(state_file)

            atom_state = state.get("electron-persisted-atom-state", {})
            permissions_by_id = atom_state.get(
                "heartbeat-thread-permissions-by-id",
                {},
            )
            permissions = permissions_by_id.get(session_id)
            if isinstance(permissions, dict):
                reviewer = permissions.get("approvalsReviewer")
                if reviewer in ("auto_review", "user"):
                    metadata["boring_notch_approval_reviewer"] = reviewer

            projectless = state.get("projectless-thread-ids", [])
            if session_id in projectless:
                metadata["project_name"] = "No project"
                return metadata

            assignment = state.get("thread-project-assignments", {}).get(session_id)
            if isinstance(assignment, dict) and assignment.get("projectKind") == "local":
                project = state.get("local-projects", {}).get(assignment.get("projectId"))
                if isinstance(project, dict):
                    project_name = project.get("name")
                    if isinstance(project_name, str) and project_name.strip():
                        metadata["project_name"] = short(project_name.strip(), 240)
        except (FileNotFoundError, OSError, TypeError, ValueError, UnicodeError):
            pass
        return metadata

    def open_notch(payload):
        payload["boring_notch_auth"] = {
            "timestamp": time.time(),
            "nonce": secrets.token_hex(16),
        }
        serialized = json.dumps(
            payload,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode("utf-8")
        if len(serialized) > MAX_PAYLOAD_BYTES:
            return False

        encoded = base64.urlsafe_b64encode(
            serialized
        ).decode("ascii").rstrip("=")
        secret_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "boring-notch-notify.secret",
        )
        try:
            with open(secret_path, "rb") as secret_file:
                secret = secret_file.read()
        except OSError:
            return False
        if len(secret) != 32:
            return False

        signature = base64.urlsafe_b64encode(
            hmac.new(
                secret,
                encoded.encode("ascii"),
                hashlib.sha256,
            ).digest()
        ).decode("ascii").rstrip("=")
        result = subprocess.run(
            [
                "/usr/bin/open",
                "-g",
                "-b",
                "theboringteam.boringnotch",
                "boringnotch://codex-event?payload=" + encoded + "&signature=" + signature,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
        return result.returncode == 0

    class PermissionDecisionHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/decision":
                self.respond(404)
                return

            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self.respond(400)
                return
            if length <= 0 or length > 4096:
                self.respond(413)
                return

            try:
                body = json.loads(self.rfile.read(length))
            except (TypeError, ValueError):
                self.respond(400)
                return
            if not isinstance(body, dict):
                self.respond(400)
                return

            token = body.get("token")
            decision = body.get("decision")
            if not isinstance(token, str) or not hmac.compare_digest(
                token,
                self.server.approval_token,
            ):
                self.respond(403)
                return
            if decision not in ("ready", "allow", "deny", "codex"):
                self.respond(400)
                return
            if decision == "ready":
                if self.server.decision is not None:
                    self.respond(409)
                    return
                self.server.ready = True
                self.respond(204)
                return
            if self.server.decision is not None:
                self.respond(409)
                return

            self.server.decision = decision
            self.respond(204)

        def respond(self, status):
            self.send_response(status)
            self.send_header("Content-Length", "0")
            self.send_header("Connection", "close")
            self.end_headers()

        def log_message(self, format, *args):
            pass

    def wait_for_permission_decision(payload):
        token = secrets.token_urlsafe(32)
        server = HTTPServer(("127.0.0.1", 0), PermissionDecisionHandler)
        server.approval_token = token
        server.ready = False
        server.decision = None
        started_at = time.monotonic()
        delivery_deadline = started_at + DELIVERY_TIMEOUT_SECONDS
        decision_deadline = started_at + DECISION_TIMEOUT_SECONDS
        payload["boring_notch_approval"] = {
            "port": server.server_address[1],
            "token": token,
            "expires_at": time.time() + DECISION_TIMEOUT_SECONDS,
        }

        try:
            if not open_notch(payload):
                return None

            while not server.ready and server.decision is None:
                remaining = delivery_deadline - time.monotonic()
                if remaining <= 0:
                    return None
                server.timeout = min(0.25, remaining)
                server.handle_request()

            while server.decision is None:
                remaining = decision_deadline - time.monotonic()
                if remaining <= 0:
                    return None
                server.timeout = min(0.25, remaining)
                server.handle_request()
            return server.decision
        finally:
            server.server_close()

    def permission_hook_response(decision):
        if decision not in ("allow", "deny"):
            return {}
        return {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": decision},
            }
        }

    def validated_transcript_path(value):
        if not isinstance(value, str) or not value.endswith(".jsonl"):
            return None

        codex_home = os.path.dirname(os.path.abspath(__file__))
        sessions_root = os.path.realpath(os.path.join(codex_home, "sessions"))
        transcript_path = os.path.realpath(value)
        try:
            if os.path.commonpath((sessions_root, transcript_path)) != sessions_root:
                return None
        except ValueError:
            return None
        return transcript_path

    def watch_for_turn_end(transcript_path, start_offset, session_id, turn_id, cwd):
        deadline = time.monotonic() + (6 * 60 * 60)
        position = max(start_offset, 0)

        while time.monotonic() < deadline:
            try:
                current_size = os.path.getsize(transcript_path)
                if current_size < position:
                    position = 0

                with open(transcript_path, "r", encoding="utf-8") as transcript:
                    transcript.seek(position)
                    while True:
                        line = transcript.readline()
                        if not line:
                            break
                        position = transcript.tell()
                        try:
                            record = json.loads(line)
                        except (TypeError, ValueError):
                            continue

                        event = record.get("payload")
                        if not isinstance(event, dict) or event.get("turn_id") != turn_id:
                            continue

                        event_type = event.get("type")
                        if event_type == "turn_aborted":
                            failure_payload = {
                                "hook_event_name": "Stop",
                                "session_id": session_id,
                                "turn_id": turn_id,
                                "last_assistant_message": (
                                    "Codex task was interrupted before completion."
                                ),
                                "status": "failed",
                            }
                            if cwd:
                                failure_payload["cwd"] = cwd
                            failure_payload.update(thread_metadata(session_id))
                            open_notch(failure_payload)
                            return
                        if event_type == "task_complete":
                            return
            except (FileNotFoundError, OSError, UnicodeError):
                pass
            time.sleep(0.5)

    def start_turn_end_watcher(source):
        transcript_path = validated_transcript_path(source.get("transcript_path"))
        session_id = source.get("session_id")
        turn_id = source.get("turn_id")
        if transcript_path is None or not all(
            isinstance(value, str) and 0 < len(value) <= 240
            for value in (session_id, turn_id)
        ):
            return

        try:
            start_offset = os.path.getsize(transcript_path)
        except OSError:
            start_offset = 0

        cwd = source.get("cwd")
        if not isinstance(cwd, str):
            cwd = ""
        try:
            subprocess.Popen(
                [
                    sys.executable,
                    os.path.abspath(__file__),
                    "--watch-turn",
                    transcript_path,
                    str(start_offset),
                    session_id,
                    turn_id,
                    short(cwd, 4096),
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
                start_new_session=True,
            )
        except (OSError, ValueError):
            pass

    if len(sys.argv) == 7 and sys.argv[1] == "--watch-turn":
        try:
            watched_path = validated_transcript_path(sys.argv[2])
            if watched_path is not None:
                watch_for_turn_end(
                    watched_path,
                    int(sys.argv[3]),
                    sys.argv[4],
                    sys.argv[5],
                    sys.argv[6],
                )
        except (TypeError, ValueError, OSError, UnicodeError):
            pass
        sys.exit(0)

    try:
        source = json.load(sys.stdin)
        payload = {}
        for key in ("hook_event_name", "session_id", "turn_id", "cwd", "tool_name", "last_assistant_message", "error", "message", "status"):
            if key in source:
                payload[key] = short(source[key])
        if "prompt" in source:
            payload["prompt"] = short(source["prompt"], MAX_PROMPT_CHARACTERS)
        payload.update(thread_metadata(source.get("session_id")))
        tool_input = bounded_tool_input(source.get("tool_input"))
        if tool_input is not None:
            payload["tool_input"] = tool_input
        if source.get("hook_event_name") == "PermissionRequest":
            if payload.get("boring_notch_approval_reviewer") != "user":
                print("{}")
            else:
                decision = wait_for_permission_decision(payload)
                print(json.dumps(permission_hook_response(decision), separators=(",", ":")))
        else:
            if source.get("hook_event_name") == "UserPromptSubmit":
                start_turn_end_watcher(source)
            open_notch(payload)
            print("{}")
    except Exception:
        print("{}")
    """#

    @objc func validateCodexNotificationPayload(
        _ payload: String,
        signature: String,
        with reply: @escaping (Bool) -> Void
    ) {
        do {
            let secret = try Data(contentsOf: codexHookURLs().secret)
            switch CodexHookAuthenticator.validate(
                payload: payload,
                signature: signature,
                secret: secret
            ) {
            case .valid:
                reply(true)
                return
            case .malformedInput:
                Self.codexLogger.error("Rejected malformed Codex notification authentication input")
            case .invalidSecret:
                Self.codexLogger.error("Rejected Codex notification because the hook secret is invalid")
            case .invalidSignature:
                Self.codexLogger.error("Rejected Codex notification because its signature did not match")
            case .malformedPayload:
                Self.codexLogger.error("Rejected malformed authenticated Codex notification data")
            case .expired:
                Self.codexLogger.error("Rejected an expired Codex notification")
            }
            reply(false)
        } catch {
            Self.codexLogger.error("Codex notification authentication failed: \(error.localizedDescription, privacy: .public)")
            reply(false)
        }
    }

    @objc func isCodexNotificationHookInstalled(with reply: @escaping (Bool) -> Void) {
        do {
            let urls = codexHookURLs()
            guard FileManager.default.fileExists(atPath: urls.script.path) else {
                reply(false)
                return
            }
            guard try Data(contentsOf: urls.script) == Data(Self.codexNotificationScript.utf8) else {
                reply(false)
                return
            }
            guard try Data(contentsOf: urls.secret).count == 32 else {
                reply(false)
                return
            }
            let root = try readCodexHookConfiguration(at: urls.configuration)
            reply(Self.codexHookEvents.allSatisfy {
                containsCurrentOwnedCodexHook(
                    in: root,
                    event: $0,
                    scriptURL: urls.script
                )
            })
        } catch {
            reply(false)
        }
    }

    @objc func areCodexNotificationHooksTrusted(with reply: @escaping (Bool) -> Void) {
        do {
            let urls = codexHookURLs()
            let configURL = urls.configuration
                .deletingLastPathComponent()
                .appendingPathComponent("config.toml")
            let configuration = try String(contentsOf: configURL, encoding: .utf8)
            let root = try readCodexHookConfiguration(at: urls.configuration)
            let trustEntries = Self.codexHookTrustEvents.compactMap {
                codexHookTrustEntry(
                    in: root,
                    event: $0.0,
                    trustEvent: $0.1,
                    scriptURL: urls.script
                )
            }
            guard trustEntries.count == Self.codexHookTrustEvents.count,
                  Set(trustEntries.map(\.section)).count == Self.codexHookTrustEvents.count else {
                reply(false)
                return
            }
            let expectedSections = Set(trustEntries.map(\.section))
            let currentHashes = Dictionary(
                uniqueKeysWithValues: trustEntries.map {
                    ($0.section, $0.currentHash)
                }
            )
            reply(
                CodexHookTrustState(configuration: configuration).areTrusted(
                    expectedSections,
                    matching: currentHashes
                )
            )
        } catch {
            reply(false)
        }
    }

    @objc func setCodexNotificationHookInstalled(
        _ installed: Bool,
        with reply: @escaping (Bool, String?) -> Void
    ) {
        do {
            let urls = codexHookURLs()
            try FileManager.default.createDirectory(
                at: urls.configuration.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let root = try CodexHookConfiguration.updating(
                readCodexHookConfiguration(at: urls.configuration),
                installed: installed,
                ownedCommandFragment: Self.codexHookMarker,
                command: codexHookCommand(scriptURL: urls.script)
            )
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            if installed {
                _ = try ensureCodexHookSecret(at: urls.secret)
                try Data(Self.codexNotificationScript.utf8).write(to: urls.script, options: .atomic)
            }
            try data.write(to: urls.configuration, options: .atomic)

            if !installed {
                for url in [urls.script, urls.secret]
                    where FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    private func codexHookURLs() -> (configuration: URL, script: URL, secret: URL) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        return (
            directory.appendingPathComponent("hooks.json"),
            directory.appendingPathComponent(Self.codexHookMarker),
            directory.appendingPathComponent(Self.codexHookSecretMarker)
        )
    }

    private func ensureCodexHookSecret(at url: URL) throws -> Data {
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            guard existing.count == 32 else {
                throw NSError(
                    domain: "BoringNotch.CodexHooks",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The Codex hook secret is invalid. Disconnect and reconnect Codex."]
                )
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NSError(
                domain: "BoringNotch.CodexHooks",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "A secure Codex hook secret could not be generated."]
            )
        }
        let secret = Data(bytes)
        try secret.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return secret
    }

    private func readCodexHookConfiguration(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let root = object as? [String: Any] else {
            throw codexHookConfigurationError(
                code: 1,
                message: "Codex hooks.json must contain a JSON object."
            )
        }
        return root
    }

    private func containsCurrentOwnedCodexHook(
        in root: [String: Any],
        event: String,
        scriptURL: URL
    ) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return false }
        let ownedGroups = groups.filter(isOwnedCodexHookGroup)
        guard ownedGroups.count == 1,
              let handlers = ownedGroups[0]["hooks"] as? [[String: Any]],
              handlers.count == 1 else { return false }

        let handler = handlers[0]
        let expectedTimeout = event == "PermissionRequest" ? 75 : 5
        return handler["type"] as? String == "command"
            && handler["command"] as? String == codexHookCommand(scriptURL: scriptURL)
            && handler["timeout"] as? Int == expectedTimeout
            && handler["async"] == nil
    }

    private func codexHookTrustEntry(
        in root: [String: Any],
        event: String,
        trustEvent: String,
        scriptURL: URL
    ) -> (section: String, currentHash: String)? {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return nil }

        for (groupIndex, group) in groups.enumerated() {
            guard isOwnedCodexHookGroup(group),
                  let handlers = group["hooks"] as? [[String: Any]] else {
                continue
            }
            for (handlerIndex, handler) in handlers.enumerated()
                where handler["command"] as? String == codexHookCommand(scriptURL: scriptURL) {
                let timeout = max(handler["timeout"] as? Int ?? 600, 1)
                let additionalContextLimit: Int?
                if ["post_tool_use", "user_prompt_submit"].contains(trustEvent),
                   let limit = handler["additionalContextLimit"] as? Int,
                   limit != 2_500 {
                    additionalContextLimit = limit
                } else {
                    additionalContextLimit = nil
                }
                let currentHash = CodexHookTrustState.currentHash(
                    eventName: trustEvent,
                    matcher: group["matcher"] as? String,
                    command: codexHookCommand(scriptURL: scriptURL),
                    timeout: timeout,
                    asynchronous: handler["async"] as? Bool ?? false,
                    statusMessage: handler["statusMessage"] as? String,
                    additionalContextLimit: additionalContextLimit
                )
                return (
                    "\(codexHookURLs().configuration.path):\(trustEvent):\(groupIndex):\(handlerIndex)",
                    currentHash
                )
            }
        }
        return nil
    }

    private func isOwnedCodexHookGroup(_ group: [String: Any]) -> Bool {
        CodexHookConfiguration.isOwnedGroup(
            group,
            commandFragment: Self.codexHookMarker
        )
    }

    private func codexHookCommand(scriptURL: URL) -> String {
        let quotedPath = scriptURL.path.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "/usr/bin/python3 '\(quotedPath)'"
    }

    private func codexHookConfigurationError(code: Int, message: String) -> NSError {
        NSError(
            domain: "BoringNotch.CodexHooks",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }
    
    private func displayServicesSetBrightnessSmooth(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightnessSmooth") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}

// MARK: - Lunar Parsing

private struct LunarBrightnessEvent: Decodable {
    let brightness: Double
    let display: Int

    init(from decoder: NSCoder) {
        display = decoder.decodeInteger(forKey: "display")
        brightness = decoder.decodeDouble(forKey: "brightness")
    }
}

private actor JSONLinesPipeHandler {
    nonisolated let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    private let decoder: JSONDecoder

    init(decoder: JSONDecoder = JSONDecoder()) {
        let pipe = Pipe()
        self.pipe = pipe
        self.fileHandle = pipe.fileHandleForReading
        self.decoder = decoder
    }

    nonisolated func getPipe() -> Pipe {
        return pipe
    }

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) -> Void) async {
        do {
            try await processLines(as: type) { decodedObject in
                onLine(decodedObject)
            }
        } catch {
            // Ignore stream errors to keep the helper lightweight.
        }
    }

    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }

            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)

                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])

                    if !line.isEmpty {
                        processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }

    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) -> Void) {
        guard let data = line.data(using: .utf8) else { return }
        if let decodedObject = try? decoder.decode(T.self, from: data) {
            onLine(decodedObject)
        }
    }

    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }

    func close() async {
        do {
            fileHandle.readabilityHandler = nil

            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            // Ignore close errors.
        }
    }
}
