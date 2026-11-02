import Foundation

// Hosted in an isolated temporary .app by run-xpc-smoke.sh so launchd can find
// the actual embedded XPC service. This never installs user hooks or opens an AI app.
@main struct XPCSmokeTest {
    static func main() throws {
        guard let serviceName = Bundle.main.infoDictionary?["AIActivitySmokeService"] as? String,
              let socketDirectory = Bundle.main.infoDictionary?["AIActivitySmokeSocketDirectory"] as? String else {
            fatalError("Missing isolated smoke-test configuration")
        }
        let connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: BoringNotchXPCHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            fputs("XPC error: \(error.localizedDescription)\n", stderr)
        }) as? BoringNotchXPCHelperProtocol else { fatalError("No XPC proxy") }
        defer {
            proxy.stopAIActivityMonitoring()
            Thread.sleep(forTimeInterval: 0.2)
        }

        func snapshot() throws -> AIActivitySnapshot {
            let semaphore = DispatchSemaphore(value: 0)
            var result: Data?
            proxy.aiActivitySnapshot(observeDesktop: false, frontmostBundleID: nil) { result = $0; semaphore.signal() }
            guard semaphore.wait(timeout: .now() + 5) == .success, let result else { fatalError("XPC snapshot timed out") }
            return try JSONDecoder().decode(AIActivitySnapshot.self, from: result)
        }
        let metadataReady = DispatchSemaphore(value: 0)
        var metadataData: Data?
        proxy.aiActivityHookStatus { metadataData = $0; metadataReady.signal() }
        guard metadataReady.wait(timeout: .now() + 5) == .success, let metadataData,
              (try? JSONDecoder().decode([String: AIHookConnection].self, from: metadataData)) != nil else {
            fatalError("Readonly hook status failed")
        }
        guard !FileManager.default.fileExists(atPath: socketDirectory + "/events.sock") else {
            fatalError("Reading connection settings unexpectedly started monitoring")
        }
        let initial = try snapshot()
        guard initial.bridgeReady else { fatalError(initial.message ?? "Bridge is not ready") }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/BoringNotchXPCHelper.xpc/Contents/MacOS/BoringNotchXPCHelper")
        let sessionID = "smoke-test-" + UUID().uuidString

        func send(_ name: String, extra: [String: Any] = [:]) throws {
            var input: [String: Any] = ["hook_event_name": name, "session_id": sessionID, "cwd": "/tmp/bridge-smoke-test"]
            extra.forEach { input[$0.key] = $0.value }
            let pipe = Pipe()
            let process = Process()
            process.executableURL = helper
            process.arguments = ["--boring-notch-ai-hook", "--provider", "claudeCode"]
            process.environment = ["BORING_NOTCH_AI_SOCKET_DIRECTORY": socketDirectory]
            process.standardInput = pipe
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            try pipe.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: input))
            try pipe.fileHandleForWriting.close()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { fatalError("Hook client failed") }
        }
        func waitFor(_ status: AIActivityStatus) throws {
            for _ in 0..<30 {
                if try snapshot().sessions.contains(where: { $0.sessionID == sessionID && $0.status == status }) { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            fatalError("Did not observe \(status.rawValue) through XPC")
        }

        try send("UserPromptSubmit")
        try waitFor(.working)
        try send("PermissionRequest", extra: ["tool_name": "Bash", "tool_use_id": "permission-1"])
        try waitFor(.needsAttention)
        try send("PostToolUse", extra: ["tool_name": "Bash", "tool_use_id": "permission-1"])
        try waitFor(.working)
        try send("Stop")
        try waitFor(.completed)
        print("Passed real embedded-helper XPC smoke test: red → yellow → red → green.")
    }
}
