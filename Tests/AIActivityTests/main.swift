import Darwin
import Foundation

var assertions = 0
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    assertions += 1
    do { if try !condition() { fatalError("FAILED: \(message)") } }
    catch { fatalError("FAILED: \(message): \(error)") }
}

let base = Date().timeIntervalSince1970
func event(_ kind: AIActivityEventKind, session: String = "desktop-session", run: String = "turn-1",
           at offset: Double, request: String? = nil, agent: String? = nil) -> AIActivityEvent {
    var result = AIActivityEvent(provider: .claudeCode, sessionID: session, runID: run, kind: kind,
                                 timestamp: base + offset)
    result.requestID = request
    result.agentID = agent
    return result
}
func apply(_ event: AIActivityEvent, to store: inout AIActivityStore) {
    store.apply(event, receivedAt: Date(timeIntervalSince1970: event.timestamp))
}
func state(_ store: AIActivityStore, session: String = "desktop-session") -> AIActivitySession {
    store.sessions["hook:claudeCode:\(session)"]!
}

// Parallel conversations, multiple pending requests, and exact resolution identity.
var store = AIActivityStore()
apply(event(.started, at: 0), to: &store)
expect(state(store).status == .working, "a GUI turn starts working")
apply(event(.attention, at: 1, request: "question"), to: &store)
apply(event(.attention, at: 2, request: "approval"), to: &store)
apply(event(.resolved, at: 3, request: "unrelated-tool"), to: &store)
expect(state(store).pendingRequests.count == 2, "unrelated tool output cannot clear user attention")
apply(event(.resolved, at: 4, request: "question"), to: &store)
expect(state(store).status == .needsAttention, "another pending request keeps yellow")
apply(event(.stopped, at: 5), to: &store)
store.advance(to: Date(timeIntervalSince1970: base + 8))
expect(state(store).status == .needsAttention, "a stopped response with pending input cannot turn green")
apply(event(.resolved, at: 9, request: "approval"), to: &store)
expect(state(store).status == .working, "resolving the last request resumes work")
apply(event(.started, session: "second-chat", at: 10), to: &store)
apply(event(.stopped, at: 11), to: &store)
store.advance(to: Date(timeIntervalSince1970: base + 13))
expect(state(store).status == .completed, "normal response stop settles after the continuation window")
expect(AIActivitySession.preferred(Array(store.sessions.values), at: Date(timeIntervalSince1970: base + 13))?.sessionID == "second-chat",
       "a completed chat cannot hide another running chat")
expect(state(store).appearsInNotch(at: Date(timeIntervalSince1970: base + 3600)), "green waits while you are away from the app")
store.observeFrontmost("com.apple.Terminal", at: Date(timeIntervalSince1970: base + 3600))
expect(state(store).acknowledgedAt == nil, "another app being frontmost does not acknowledge the result")
store.observeFrontmost(AIProvider.claudeCode.bundleIdentifier, at: Date(timeIntervalSince1970: base + 3601))
expect(state(store).appearsInNotch(at: Date(timeIntervalSince1970: base + 3603)), "green lingers briefly after you return")
expect(!state(store).appearsInNotch(at: Date(timeIntervalSince1970: base + 3604)), "green yields a few seconds after you return")
store.observeFrontmost(AIProvider.claudeCode.bundleIdentifier, at: Date(timeIntervalSince1970: base + 3700))
expect(state(store).acknowledgedAt == Date(timeIntervalSince1970: base + 3601), "staying in the app does not restart the delay")
var hosted = AIActivityStore()
var terminalTurn = event(.started, session: "cli", at: 0)
terminalTurn.hostBundleID = "com.googlecode.iterm2"
apply(terminalTurn, to: &hosted)
apply(event(.stopped, session: "cli", at: 1), to: &hosted)
hosted.advance(to: Date(timeIntervalSince1970: base + 3))
hosted.observeFrontmost(AIProvider.claudeCode.bundleIdentifier, at: Date(timeIntervalSince1970: base + 4))
expect(state(hosted, session: "cli").acknowledgedAt == nil, "a CLI result is acknowledged in its terminal, not the desktop app")
hosted.observeFrontmost("com.googlecode.iterm2", at: Date(timeIntervalSince1970: base + 5))
expect(state(hosted, session: "cli").acknowledgedAt != nil, "returning to the hosting terminal acknowledges the result")
apply(event(.started, session: "cli", run: "turn-2", at: 6), to: &hosted)
expect(state(hosted, session: "cli").acknowledgedAt == nil && state(hosted, session: "cli").hostBundleID == "com.googlecode.iterm2",
       "a new turn clears the acknowledgement but keeps the host app")

// Continuation, delayed event timestamps, stale runs, interruption and replay.
var continuation = AIActivityStore()
apply(event(.started, at: 0), to: &continuation)
apply(event(.stopped, at: 1), to: &continuation)
apply(event(.activity, at: 2), to: &continuation)
continuation.advance(to: Date(timeIntervalSince1970: base + 5))
expect(state(continuation).status == .working, "continuation cancels a pending green light")
apply(event(.stopped, at: 6), to: &continuation)
continuation.advance(to: Date(timeIntervalSince1970: base + 10))
// A local transition timestamp must not reject a genuine delayed runtime event.
apply(event(.activity, at: 9), to: &continuation)
expect(state(continuation).status == .working, "late runtime events are compared with runtime timestamps")
let newTurn = event(.started, run: "turn-2", at: 11)
apply(newTurn, to: &continuation)
apply(event(.failed, run: "turn-1", at: 12), to: &continuation)
expect(state(continuation).status == .working, "an old run cannot fail the current run")
apply(event(.attention, run: "turn-2", at: 10), to: &continuation)
expect(state(continuation).status == .working, "out-of-order events cannot replace newer evidence")
var replay = newTurn
replay.kind = .failed
apply(replay, to: &continuation)
expect(state(continuation).status == .working, "replayed event IDs are ignored")
apply(event(.interrupted, run: "turn-2", at: 13), to: &continuation)
continuation.advance(to: Date(timeIntervalSince1970: base + 20))
expect(state(continuation).status == .interrupted, "interruption never produces green")

var children = AIActivityStore()
apply(event(.started, at: 0), to: &children)
apply(event(.subagentStarted, at: 1, agent: "child"), to: &children)
apply(event(.stopped, at: 2), to: &children)
children.advance(to: Date(timeIntervalSince1970: base + 5))
expect(state(children).status == .working, "parent stop cannot finish active background work")
children.dismiss(state(children).id)
expect(children.sessions.count == 1, "dismiss cannot resolve an active task")
apply(event(.subagentStopped, at: 6, agent: "child"), to: &children)
expect(state(children).status != .completed, "a child stop is not a parent completion event")
expect(state(children).status == .unknown, "finished children do not leave a permanently busy parent")
apply(event(.failed, at: 7), to: &children)
expect(state(children).status == .needsAttention, "response failure uses yellow rather than working red")
var invalid = event(.started, at: 8)
invalid.version = 9
apply(invalid, to: &children)
expect(state(children).status == .needsAttention, "unknown event schemas are rejected")
var closedApp = AIActivityStore()
apply(event(.started, at: 0), to: &closedApp)
apply(event(.stopped, at: 1), to: &closedApp)
closedApp.markDesktopUnavailable(.claudeCode, at: Date(timeIntervalSince1970: base + 2))
closedApp.advance(to: Date(timeIntervalSince1970: base + 5))
expect(state(closedApp).status == .unknown, "closing a desktop app cancels an unconfirmed completion")
closedApp.disconnect(.claudeCode)
expect(closedApp.sessions.isEmpty, "disconnect removes that provider's stale live state")

// The current action follows tools, falls back to thinking between them, and clears when not working.
var actions = AIActivityStore()
apply(event(.started, at: 0), to: &actions)
expect(state(actions).action == .thinking, "a new turn starts thinking")
var editing = event(.activity, at: 1)
editing.action = .editing
editing.actionDetail = "Notch.swift"
apply(editing, to: &actions)
expect(state(actions).caption == "Editing Notch.swift", "a tool call becomes the caption")
apply(event(.resolved, at: 2, request: "tool:edit"), to: &actions)
expect(state(actions).action == .thinking, "between tools the caption returns to thinking")
apply(event(.attention, at: 3, request: "approval"), to: &actions)
expect(state(actions).caption == nil, "yellow shows its reason, not a stale action")
apply(event(.resolved, at: 4, request: "approval"), to: &actions)
apply(event(.stopped, at: 5), to: &actions)
expect(state(actions).action == nil, "a stopped response has no action")

// Yellow drops a banner under the notch until you go to the waiting app; a new question drops it again.
var banner = AIActivityStore()
apply(event(.started, at: 0), to: &banner)
apply(event(.attention, at: 1, request: "approval"), to: &banner)
expect(state(banner).showsAttentionBanner(at: Date(timeIntervalSince1970: base + 600)), "an unanswered question keeps the banner down")
banner.observeFrontmost(AIProvider.claudeCode.bundleIdentifier, at: Date(timeIntervalSince1970: base + 600))
expect(state(banner).showsAttentionBanner(at: Date(timeIntervalSince1970: base + 602)), "the banner lingers briefly after you switch")
expect(!state(banner).showsAttentionBanner(at: Date(timeIntervalSince1970: base + 603)), "the banner retracts once you are in the app")
expect(state(banner).status == .needsAttention, "seeing a question does not answer it")
apply(event(.activity, at: 604), to: &banner)
expect(!state(banner).showsAttentionBanner(at: Date(timeIntervalSince1970: base + 604)), "unrelated activity does not drop the banner again")
apply(event(.attention, at: 605, request: "question"), to: &banner)
expect(state(banner).showsAttentionBanner(at: Date(timeIntervalSince1970: base + 605)), "a new question drops the banner again")
apply(event(.resolved, at: 606, request: "approval"), to: &banner)
apply(event(.resolved, at: 607, request: "question"), to: &banner)
expect(!state(banner).showsAttentionBanner(at: Date(timeIntervalSince1970: base + 607)), "answering retracts the banner")

// Real Claude Code hook sequences: PermissionRequest has no tool_use_id, a failed tool fires
// PostToolUseFailure, and a manual denial fires nothing afterwards.
func hook(_ name: String, _ tool: String? = nil, id: String? = nil, at offset: Double) -> AIActivityEvent {
    var json: [String: Any] = ["hook_event_name": name, "session_id": "desktop-session"]
    if let tool { json["tool_name"] = tool; json["tool_input"] = [String: Any]() }
    if let id { json["tool_use_id"] = id }
    var result = AIActivityHookClient.normalize(json, provider: .claudeCode, environment: [:])!
    result.timestamp = base + offset
    return result
}
var answered = AIActivityStore()
apply(event(.started, at: 0), to: &answered)
apply(hook("PreToolUse", "AskUserQuestion", id: "toolu_q", at: 1), to: &answered)
apply(hook("PermissionRequest", "AskUserQuestion", at: 2), to: &answered)
expect(state(answered).status == .needsAttention, "a question waits for you")
apply(hook("PostToolUse", "AskUserQuestion", id: "toolu_q", at: 3), to: &answered)
expect(state(answered).status == .working && state(answered).pendingRequests.isEmpty,
       "answering a question clears its permission request too")
apply(hook("PreToolUse", "Bash", id: "toolu_b", at: 4), to: &answered)
apply(hook("PermissionRequest", "Bash", at: 5), to: &answered)
apply(hook("PostToolUseFailure", "Bash", id: "toolu_b", at: 6), to: &answered)
expect(state(answered).status == .working, "an approved command that fails still clears the request")
apply(hook("PreToolUse", "Bash", id: "toolu_c", at: 7), to: &answered)
apply(hook("PermissionRequest", "Bash", at: 8), to: &answered)
apply(hook("Stop", at: 9), to: &answered)
answered.advance(to: Date(timeIntervalSince1970: base + 12))
expect(state(answered).status == .completed, "a manually denied permission does not stick once the response ends")

// Simultaneous providers: one companion each, most urgent first, sessions counted per provider.
let groupNow = Date(timeIntervalSince1970: base + 100)
func session(_ provider: AIProvider, _ id: String, _ status: AIActivityStatus, updated: Double) -> AIActivitySession {
    var result = AIActivitySession(provider: provider, sessionID: id, status: status)
    result.updatedAt = Date(timeIntervalSince1970: base + updated)
    if status == .completed { result.completedAt = result.updatedAt }
    return result
}
let groups = AIActivitySession.grouped([
    session(.codex, "c1", .working, updated: 90),
    session(.claudeCode, "a1", .working, updated: 95),
    session(.codex, "c2", .needsAttention, updated: 80),
    session(.claudeCode, "a2", .unknown, updated: 99),
], at: groupNow)
expect(groups.map(\.provider) == [.codex, .claudeCode], "the provider with the most urgent session leads")
expect(groups[0].lead.sessionID == "c2" && groups[0].count == 2, "a provider leads with its most urgent session and counts the rest")
expect(groups[1].count == 1, "sessions hidden from the notch are not counted")
expect(AIActivitySession.preferred([session(.codex, "c1", .working, updated: 90), session(.claudeCode, "a1", .completed, updated: 99)],
                                   at: groupNow)?.provider == .codex, "the lamps still follow the most urgent session")

// Lost final hooks: silent sessions dim after a generous limit and never turn green.
var stale = AIActivityStore()
apply(event(.started, at: 0), to: &stale)
stale.advance(to: Date(timeIntervalSince1970: base + AIActivityStore.workingStaleInterval - 1))
expect(state(stale).status == .working, "a long silent tool keeps working within the stale limit")
stale.advance(to: Date(timeIntervalSince1970: base + AIActivityStore.workingStaleInterval))
expect(state(stale).status == .unknown, "a session without a final hook does not stay red forever")
apply(event(.activity, at: AIActivityStore.workingStaleInterval + 1), to: &stale)
expect(state(stale).status == .working, "fresh activity resumes a stale session")
apply(event(.attention, at: AIActivityStore.workingStaleInterval + 2, request: "question"), to: &stale)
stale.advance(to: Date(timeIntervalSince1970: base + AIActivityStore.workingStaleInterval * 3))
expect(state(stale).status == .needsAttention, "an unanswered question outlasts the working limit")
stale.advance(to: Date(timeIntervalSince1970: base + AIActivityStore.attentionStaleInterval * 2))
expect(state(stale).status == .unknown && state(stale).pendingRequests.isEmpty, "an abandoned question eventually dims")

// GUI hooks: forward identity only, never prompts, tool input, output or environment secrets.
let guiInput: [String: Any] = ["hook_event_name": "UserPromptSubmit", "session_id": "engine-id", "turn_id": "turn-id",
                             "cwd": "/private/work/project", "prompt": "PRIVATE PROMPT"]
let gui = AIActivityHookClient.normalize(guiInput, provider: .claudeCode,
    environment: ["CLAUDE_CODE_HOST_SESSION_ID": "local_123", "UNRELATED_SECRET": "PRIVATE SECRET"])!
expect(gui.isDesktop && gui.hostSessionID == "local_123", "GUI host identity survives normalization")
expect(gui.project == "project", "only the project basename is forwarded")
expect(AIActivityHookClient.normalize(guiInput, provider: .claudeCode,
       environment: ["__CFBundleIdentifier": "com.microsoft.VSCode"])?.hostBundleID == "com.microsoft.VSCode",
       "the launching app's bundle identity is forwarded so green can wait for you there")
let encoded = String(data: try JSONEncoder().encode(gui), encoding: .utf8)!
expect(!encoded.contains("PRIVATE") && !encoded.contains("/private/work"), "hook transport excludes private content and full paths")
let idleNotification: [String: Any] = ["hook_event_name": "Notification", "session_id": "s", "notification_type": "idle_prompt"]
expect(AIActivityHookClient.normalize(idleNotification, provider: .claudeCode, environment: [:]) == nil,
       "idle reminders are not user-attention requests")
let permissionNotification: [String: Any] = ["hook_event_name": "Notification", "session_id": "s", "notification_type": "permission_prompt"]
expect(AIActivityHookClient.normalize(permissionNotification, provider: .claudeCode, environment: [:]) == nil,
       "a delayed permission reminder cannot leave an unresolvable duplicate request")
let elicitationInput: [String: Any] = ["hook_event_name": "Elicitation", "session_id": "s", "elicitation_id": "form-1"]
let elicitationOutput: [String: Any] = ["hook_event_name": "ElicitationResult", "session_id": "s", "elicitation_id": "form-1"]
expect(AIActivityHookClient.normalize(elicitationInput, provider: .claudeCode, environment: [:])?.requestID
       == AIActivityHookClient.normalize(elicitationOutput, provider: .claudeCode, environment: [:])?.requestID,
       "connected-tool forms use the same request identity on request and result")
let codexInput: [String: Any] = ["hook_event_name": "UserPromptSubmit", "session_id": "codex-session"]
expect(AIActivityHookClient.normalize(codexInput, provider: .codex,
       environment: ["__CFBundleIdentifier": "com.apple.Terminal"])?.isDesktop == false,
       "a terminal Codex session is not cleared when the Codex app is closed")
expect(AIActivityHookClient.normalize(codexInput, provider: .codex,
       environment: ["__CFBundleIdentifier": AIProvider.codex.bundleIdentifier])?.isDesktop == true,
       "a Codex app session is tied to the app's lifetime")
// Action captions: tool category plus a basename, program, host or agent type only.
func toolEvent(_ tool: String, _ input: [String: Any]) -> AIActivityEvent? {
    AIActivityHookClient.normalize(["hook_event_name": "PreToolUse", "session_id": "s", "tool_name": tool,
                                    "tool_input": input], provider: .claudeCode, environment: [:])
}
let readEvent = toolEvent("Read", ["file_path": "/Users/me/secret-project/Sources/Notch.swift"])!
expect(readEvent.action == .reading && readEvent.actionDetail == "Notch.swift", "reading forwards only the file basename")
expect(!String(decoding: try JSONEncoder().encode(readEvent), as: UTF8.self).contains("secret-project"),
       "file directories never leave the hook")
let bashEvent = toolEvent("Bash", ["command": "API_TOKEN=PRIVATE git push origin PRIVATE-branch"])!
expect(bashEvent.action == .running && bashEvent.actionDetail == "git", "commands forward only the program name")
expect(!String(decoding: try JSONEncoder().encode(bashEvent), as: UTF8.self).contains("PRIVATE"),
       "command arguments and environment assignments never leave the hook")
expect(toolEvent("Bash", ["command": "sh Tests/AIActivityTests/run.sh"])?.action == .testing, "test scripts read as testing")
expect(toolEvent("Bash", ["command": "xcodebuild test -scheme App"])?.action == .testing, "test subcommands read as testing")
expect(toolEvent("Grep", ["pattern": "PRIVATE"])?.actionDetail == nil, "search patterns are not forwarded")
expect(toolEvent("WebFetch", ["url": "https://example.com/private?q=PRIVATE"])?.actionDetail == "example.com",
       "web fetches forward only the host")
expect(toolEvent("Task", ["subagent_type": "Explore", "prompt": "PRIVATE"])?.actionDetail == "Explore",
       "delegation forwards only the agent type")
expect(toolEvent("mcp__github__create_issue", ["body": "PRIVATE"])?.actionDetail == "github", "MCP tools show their server")
expect(toolEvent("Read", ["file_path": "/tmp/" + String(repeating: "檔", count: 200)])?.isValid == true,
       "long non-ASCII file names are truncated rather than dropping the event")

let asyncResult: [String: Any] = ["hook_event_name": "PostToolUse", "session_id": "s", "tool_name": "request_user_input_async"]
expect(AIActivityHookClient.normalize(asyncResult, provider: .codex, environment: [:]) == nil,
       "presenting an async question is not the same as answering it")

// Installer uses an isolated fake home; never touch real agent settings in tests.
// Darwin's Unix socket path limit is short; NSTemporaryDirectory can already
// consume most of it on macOS. Production uses a short per-user /tmp path too.
let temporary = URL(fileURLWithPath: "/tmp").appendingPathComponent("bn-ai-tests-" + UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let configURL = AIActivityHookInstaller.configurationURL(for: .claudeCode, home: temporary)!
try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let unrelated: [String: Any] = ["theme": "dark", "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "keep-me"]]]]]]
try JSONSerialization.data(withJSONObject: unrelated).write(to: configURL)
let fakeExecutable = temporary.appendingPathComponent("Helper 'quoted'/helper")
try FileManager.default.createDirectory(at: fakeExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$CAPTURE_ARGS\"\n".utf8).write(to: fakeExecutable)
chmod(fakeExecutable.path, 0o700)
_ = try AIActivityHookInstaller.update(.claudeCode, remove: false, executableURL: fakeExecutable, home: temporary)
expect(AIActivityHookInstaller.isConnected(.claudeCode, executableURL: fakeExecutable, home: temporary),
       "installer connects GUI hooks")
expect(AIActivityHookInstaller.connection(.claudeCode, executableURL: fakeExecutable, home: temporary).executablePath
       == fakeExecutable.path, "the installed helper path is reported without shell quoting")
let otherCopy = temporary.appendingPathComponent("Other Copy/helper")
expect(AIActivityHookInstaller.connection(.claudeCode, executableURL: otherCopy, home: temporary).state == .needsReconnect,
       "hooks that run another copy of the helper are not reported as connected")
let installed = try Data(contentsOf: configURL)
var withoutFailureHook = try JSONSerialization.jsonObject(with: installed) as! [String: Any]
var trimmedHooks = withoutFailureHook["hooks"] as! [String: Any]
trimmedHooks.removeValue(forKey: "PostToolUseFailure")
withoutFailureHook["hooks"] = trimmedHooks
let olderHome = temporary.appendingPathComponent("older-install")
let olderConfig = AIActivityHookInstaller.configurationURL(for: .claudeCode, home: olderHome)!
try FileManager.default.createDirectory(at: olderConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: withoutFailureHook).write(to: olderConfig)
expect(AIActivityHookInstaller.connection(.claudeCode, executableURL: fakeExecutable, home: olderHome).state == .needsReconnect,
       "an install missing the failure hook asks to reconnect")
expect(!String(decoding: installed, as: UTF8.self).contains("\\/"), "rewriting settings does not escape every slash")
_ = try AIActivityHookInstaller.update(.claudeCode, remove: false, executableURL: fakeExecutable, home: temporary)
expect(try Data(contentsOf: configURL) == installed, "repeated installation is idempotent")
let parsed = try JSONSerialization.jsonObject(with: installed) as! [String: Any]
let hookGroups = (parsed["hooks"] as! [String: Any])["UserPromptSubmit"] as! [[String: Any]]
let command = (hookGroups[0]["hooks"] as! [[String: Any]])[0]["command"] as! String
let capture = temporary.appendingPathComponent("captured-args")
let shell = Process()
shell.executableURL = URL(fileURLWithPath: "/bin/sh")
shell.arguments = ["-c", command]
shell.environment = ["CAPTURE_ARGS": capture.path]
try shell.run(); shell.waitUntilExit()
expect(shell.terminationStatus == 0, "paths with spaces and single quotes are safely shell-quoted")
expect(try String(contentsOf: capture, encoding: .utf8) == "--boring-notch-ai-hook\n--provider\nclaudeCode\n", "hook command forwards literal arguments")
_ = try AIActivityHookInstaller.update(.claudeCode, remove: false, executableURL: otherCopy, home: temporary)
expect(AIActivityHookInstaller.isConnected(.claudeCode, executableURL: otherCopy, home: temporary),
       "reconnecting replaces hooks that ran another copy")
let backups = try FileManager.default.contentsOfDirectory(atPath: configURL.deletingLastPathComponent().path)
    .filter { $0.contains("boring-notch-backup") }
expect(backups == ["settings.json.boring-notch-backup"], "repeated connections keep one rolling backup")
_ = try AIActivityHookInstaller.update(.claudeCode, remove: true, executableURL: fakeExecutable, home: temporary)
let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! NSDictionary
expect(restored == unrelated as NSDictionary, "disconnect preserves unrelated configuration and matchers")
let afterRemoval = try Data(contentsOf: configURL)
_ = try AIActivityHookInstaller.update(.claudeCode, remove: true, executableURL: fakeExecutable, home: temporary)
expect(try Data(contentsOf: configURL) == afterRemoval, "removing nonexistent hooks does not reformat settings")
try Data("{invalid".utf8).write(to: configURL)
do {
    _ = try AIActivityHookInstaller.update(.claudeCode, remove: false, executableURL: fakeExecutable, home: temporary)
    expect(false, "malformed configuration must fail")
} catch {
    expect(try String(contentsOf: configURL, encoding: .utf8) == "{invalid", "malformed configuration remains byte-for-byte intact")
}

// Exercise the real BSD transport in a separate private temporary directory.
let socketDirectory = temporary.appendingPathComponent("socket").path
let received = DispatchSemaphore(value: 0)
let listener = AIActivitySocketListener(directory: socketDirectory) { data in
    if (try? JSONDecoder().decode(AIActivityEvent.self, from: data))?.sessionID == "engine-id" { received.signal() }
}
try listener.start()
let client = AIActivitySocket.connect(socketPath: socketDirectory + "/events.sock")!
var wire = try JSONEncoder().encode(gui)
wire.append(10)
_ = wire.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
close(client)
expect(received.wait(timeout: .now() + 2) == .success, "send-and-close hooks reach the actual Unix listener")
// A client that connects before sending must not be dropped when the listener wakes in between.
let slowClient = AIActivitySocket.connect(socketPath: socketDirectory + "/events.sock")!
usleep(100_000)
_ = wire.withUnsafeBytes { send(slowClient, $0.baseAddress, $0.count, 0) }
close(slowClient)
expect(received.wait(timeout: .now() + 2) == .success, "a hook that sends shortly after connecting is still received")
let second = AIActivitySocketListener(directory: socketDirectory) { _ in }
do { try second.start(); expect(false, "a second listener must not steal the first socket") }
catch { expect(FileManager.default.fileExists(atPath: socketDirectory + "/events.sock"), "existing listener remains intact") }
listener.stop()
try listener.start()
listener.stop()
expect(!FileManager.default.fileExists(atPath: socketDirectory + "/events.sock"), "restart and cleanup work with an existing private directory")
print("Passed \(assertions) AI activity assertions.")
