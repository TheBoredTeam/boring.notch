import Foundation
import Combine

struct PortEntry: Identifiable, Equatable {
    var id: String { "\(pid)-\(port)-\(proto)" }
    let port: Int
    let pid: Int32
    let command: String
    let user: String
    let proto: String
    var uptime: String = "" // how long the owning process has been running, e.g. "2h 14m"
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

                    // Enrich with process uptime (etime) in one ps call.
                    let uptimes = Self.uptimes(forPIDs: Array(Set(parsedEntries.map { $0.pid })))
                    let enrichedEntries = parsedEntries.map { entry -> PortEntry in
                        var e = entry
                        e.uptime = uptimes[entry.pid] ?? ""
                        return e
                    }

                    await MainActor.run {
                        self?.entries = enrichedEntries
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

    /// Maps PID → human-readable process uptime via `ps -o pid=,etime=`.
    private nonisolated static func uptimes(forPIDs pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=,etime=", "-p", pids.map(String.init).joined(separator: ",")]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [:]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int32: String] = [:]
        for line in out.components(separatedBy: .newlines) {
            let cols = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard cols.count >= 2, let pid = Int32(cols[0]) else { continue }
            result[pid] = humanizeEtime(cols[1])
        }
        return result
    }

    /// Converts ps etime ("[[DD-]hh:]mm:ss") to a compact string like "2d 3h", "1h 5m", "5m", "23s".
    private nonisolated static func humanizeEtime(_ etime: String) -> String {
        var days = 0
        var rest = etime
        if let dash = etime.firstIndex(of: "-") {
            days = Int(etime[..<dash]) ?? 0
            rest = String(etime[etime.index(after: dash)...])
        }
        let parts = rest.components(separatedBy: ":").map { Int($0) ?? 0 }
        var h = 0, m = 0, s = 0
        switch parts.count {
        case 3: h = parts[0]; m = parts[1]; s = parts[2]
        case 2: m = parts[0]; s = parts[1]
        case 1: s = parts[0]
        default: break
        }
        if days > 0 { return "\(days)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
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
