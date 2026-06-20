import SwiftUI

struct PortsView: View {
    @ObservedObject private var manager = PortsManager.shared
    @State private var searchText = ""
    @State private var myProcessesOnly = true
    
    @State private var timer: Timer?
    @State private var showConfirmStop = false
    @State private var showForceKill = false
    @State private var showRootWarning = false
    @State private var selectedProcess: PortEntry?
    
    var filteredEntries: [PortEntry] {
        manager.entries.filter { entry in
            let matchesUser = !myProcessesOnly || entry.user == NSUserName()
            let matchesSearch = searchText.isEmpty || 
                entry.command.localizedCaseInsensitiveContains(searchText) ||
                String(entry.port).contains(searchText) ||
                entry.user.localizedCaseInsensitiveContains(searchText)
            return matchesUser && matchesSearch
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header Row: Segment Control & Search
            HStack(spacing: 12) {
                // Custom Segmented Control for Process Filter
                HStack(spacing: 2) {
                    Text("MINE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(myProcessesOnly ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(myProcessesOnly ? Color.white.opacity(0.9) : Color.clear))
                        .contentShape(Capsule())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { myProcessesOnly = true } }
                        
                    Text("ALL")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(!myProcessesOnly ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(!myProcessesOnly ? Color.white.opacity(0.9) : Color.clear))
                        .contentShape(Capsule())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { myProcessesOnly = false } }
                }
                .padding(2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                
                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 10, weight: .semibold))
                    TextField("Search ports or apps", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                
                // Refresh Button
                Button(action: { manager.refresh() }) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.08)).frame(width: 24, height: 24)
                        if manager.isLoading {
                            ProgressView()
                                .scaleEffect(0.5)
                                .colorScheme(.dark)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoading)
            }
            
            // Custom List using ScrollView
            ScrollView {
                LazyVStack(spacing: 6) {
                    if filteredEntries.isEmpty {
                        Text(manager.isLoading ? "Scanning ports..." : "No matching ports found.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.top, 20)
                    } else {
                        ForEach(filteredEntries) { entry in
                            HStack(spacing: 12) {
                                // Port & Protocol
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.port)")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text(entry.proto)
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundColor(entry.proto == "TCP" ? .blue.opacity(0.8) : .purple.opacity(0.8))
                                }
                                .frame(width: 45, alignment: .leading)
                                
                                // Divider
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 1, height: 24)
                                
                                // Command & Details
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.command)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    HStack(spacing: 4) {
                                        Text("PID: \(entry.pid)")
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("•")
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.3))
                                        Text(entry.user)
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundColor(entry.user != NSUserName() ? .orange.opacity(0.8) : .white.opacity(0.5))
                                        if !entry.uptime.isEmpty {
                                            Text("•")
                                                .font(.system(size: 9))
                                                .foregroundColor(.white.opacity(0.3))
                                            Image(systemName: "clock")
                                                .font(.system(size: 8, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.45))
                                            Text(entry.uptime)
                                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                                .foregroundColor(.white.opacity(0.55))
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // Stop Button
                                Button(action: {
                                    initiateStop(entry)
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.red.opacity(0.9))
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(Color.red.opacity(0.15)))
                                }
                                .buttonStyle(.plain)
                                .help("Stop Process")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            manager.refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                manager.refresh()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            releaseNotchLock()
        }
        .alert(isPresented: Binding<Bool>(
            get: { showRootWarning || showConfirmStop || showForceKill },
            set: { _ in
                showRootWarning = false
                showConfirmStop = false
                showForceKill = false
            }
        )) {
            if showRootWarning {
                return Alert(
                    title: Text("System Process"),
                    message: Text("You are about to stop a process owned by \(selectedProcess?.user ?? "another user"). This may cause system instability. Are you sure?"),
                    primaryButton: .destructive(Text("Continue")) {
                        showRootWarning = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showConfirmStop = true
                        }
                    },
                    secondaryButton: .cancel(Text("Cancel")) { releaseNotchLock() }
                )
            } else if showForceKill {
                return Alert(
                    title: Text("Process Survived"),
                    message: Text("The process \(selectedProcess?.command ?? "") on port \(selectedProcess?.port ?? 0) is still running. Force kill?"),
                    primaryButton: .destructive(Text("Force Kill")) {
                        if let process = selectedProcess {
                            Task {
                                await performStop(process, force: true)
                            }
                        }
                    },
                    secondaryButton: .cancel(Text("Cancel")) { releaseNotchLock() }
                )
            } else {
                return Alert(
                    title: Text("Stop Process"),
                    message: Text("Are you sure you want to stop \(selectedProcess?.command ?? "") on port \(selectedProcess?.port ?? 0)?"),
                    primaryButton: .destructive(Text("Stop")) {
                        if let process = selectedProcess {
                            Task {
                                await performStop(process, force: false)
                            }
                        }
                    },
                    secondaryButton: .cancel(Text("Cancel")) { releaseNotchLock() }
                )
            }
        }
    }
    
    private func initiateStop(_ entry: PortEntry) {
        selectedProcess = entry
        // Keep the notch open while a confirmation alert is up — otherwise it
        // auto-closes on mouse-leave and tears down the alert before you confirm.
        SharingStateManager.shared.preventNotchClose = true
        if entry.user != NSUserName() {
            showRootWarning = true
        } else {
            showConfirmStop = true
        }
    }

    private func releaseNotchLock() {
        SharingStateManager.shared.preventNotchClose = false
    }

    private func performStop(_ entry: PortEntry, force: Bool) async {
        let result = await manager.stopProcess(pid: entry.pid, force: force)
        switch result {
        case .success:
            releaseNotchLock()
            manager.refresh()
        case .survived:
            showForceKill = true // keep the notch locked for the follow-up prompt
        case .error(let error):
            releaseNotchLock()
            print("Stop error: \(error.localizedDescription)")
        }
    }
}
