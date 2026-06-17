import Foundation
import Combine

struct PortEntry: Identifiable, Equatable {
    var id: String { "\(pid)-\(port)-\(proto)" }
    let port: Int
    let pid: Int32
    let command: String
    let user: String
    let proto: String
}

@MainActor
class PortsManager: ObservableObject {
    static let shared = PortsManager()
    
    @Published var entries: [PortEntry] = []
    @Published var isLoading = false
    
    private var refreshTask: Task<Void, Never>?
    
    private init() {}
    
    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        
        refreshTask = Task.detached { [weak self] in
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP"]
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let parsedEntries = Self.parseLsofOutput(output)
                    
                    await MainActor.run {
                        self?.entries = parsedEntries
                        self?.isLoading = false
                    }
                } else {
                    await MainActor.run { self?.isLoading = false }
                }
            } catch {
                print("Failed to run lsof: \(error)")
                await MainActor.run { self?.isLoading = false }
            }
        }
    }
    
    private nonisolated static func parseLsofOutput(_ output: String) -> [PortEntry] {
        var parsed: [PortEntry] = []
        var seen = Set<String>()
        
        let lines = output.components(separatedBy: .newlines)
        guard lines.count > 1 else { return [] }
        
        // Skipping the header line
        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard cols.count >= 9 else { continue }
            
            let command = cols[0]
            guard let pid = Int32(cols[1]) else { continue }
            let user = cols[2]
            let proto = cols[7]
            let nameCol = cols[8...].joined(separator: " ")
            
            // Name format usually looks like: *:8080 (LISTEN) or localhost:5000 (LISTEN)
            // For UDP: *:123
            let nameParts = nameCol.components(separatedBy: .whitespaces)[0].components(separatedBy: ":")
            guard let portStr = nameParts.last, let port = Int(portStr) else { continue }
            
            let id = "\(pid)-\(port)-\(proto)"
            if !seen.contains(id) {
                seen.insert(id)
                parsed.append(PortEntry(port: port, pid: pid, command: command, user: user, proto: proto))
            }
        }
        
        return parsed.sorted { $0.port < $1.port }
    }
    
    enum StopResult {
        case success
        case survived
        case error(Error)
    }
    
    func stopProcess(pid: Int32, force: Bool = false) async -> StopResult {
        let signal = force ? SIGKILL : SIGTERM
        let result = Darwin.kill(pid, signal)
        
        if result != 0 {
            let err = NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to send signal \(signal) to PID \(pid)"])
            return .error(err)
        }
        
        if force {
            return .success
        }
        
        // Wait ~1.5s to see if it survives
        do {
            try await Task.sleep(nanoseconds: 1_500_000_000)
        } catch {
            return .error(error)
        }
        
        // Check if still alive using kill with signal 0
        let checkResult = Darwin.kill(pid, 0)
        if checkResult == 0 {
            // Still alive
            return .survived
        } else {
            // Process terminated
            return .success
        }
    }
}
