//
//  AnimatedFace.swift
//  boringNotch
//
//  Created by Harsh Vardhan Goswami on 04/08/24.
//  Transformed into Notch Pet by Antigravity on 2026-05-24.
//

import SwiftUI
import AppKit
import Intents
import Combine
import Defaults

enum PetState: String, Codable {
    case idle
    case sleepy
    case excited
    case stressed
    case focused
    case happy
    
    var moodEmoji: String {
        switch self {
        case .idle: return "🙂"
        case .sleepy: return "🥱"
        case .excited: return "🤩"
        case .stressed: return "😰"
        case .focused: return "🧐"
        case .happy: return "😊"
        }
    }
    
    var moodName: String {
        switch self {
        case .idle: return "Relaxed"
        case .sleepy: return "Sleepy"
        case .excited: return "Excited!"
        case .stressed: return "Stressed"
        case .focused: return "Focused"
        case .happy: return "Happy"
        }
    }
}

@MainActor
final class PetManager: ObservableObject {
    static let shared = PetManager()
    
    @Published var state: PetState = .idle
    
    // Personality levels (0 to 100)
    @Published var energyLevel: Double = 80.0
    @Published var happinessLevel: Double = 75.0
    @Published var stressLevel: Double = 15.0
    @Published var attentionLevel: Double = 30.0
    
    @Published var currentActivity: String = "Relaxing"
    @Published var totalClicks: Int = 0
    @Published var totalFeeds: Int = 0
    
    @Published var activeViewCount: Int = 0 {
        didSet {
            updateMonitoringState()
        }
    }
    
    private let cpuUtility = ProcessorLoadUtility()
    private var timer: Timer?
    private var defaultsCancellable: AnyCancellable?
    
    private init() {
        self.totalClicks = UserDefaults.standard.integer(forKey: "pet_total_clicks")
        self.totalFeeds = UserDefaults.standard.integer(forKey: "pet_total_feeds")
        
        // Listen to settings changes to start/stop dynamically
        self.defaultsCancellable = Defaults.publisher(.showNotHumanFace)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMonitoringState()
            }
        
        updateMonitoringState()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func updateMonitoringState() {
        if activeViewCount > 0 && Defaults[.showNotHumanFace] {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    func startMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePetState()
            }
        }
        updatePetState()
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func recordClick() {
        totalClicks += 1
        UserDefaults.standard.set(totalClicks, forKey: "pet_total_clicks")
        
        // Clicking makes the pet happier and slightly more energetic
        happinessLevel = min(100.0, happinessLevel + 8.0)
        energyLevel = min(100.0, energyLevel + 5.0)
        stressLevel = max(0.0, stressLevel - 5.0)
    }
    
    func feedPet() {
        totalFeeds += 1
        UserDefaults.standard.set(totalFeeds, forKey: "pet_total_feeds")
        
        // Feeding restores energy and increases happiness
        energyLevel = min(100.0, energyLevel + 25.0)
        happinessLevel = min(100.0, happinessLevel + 15.0)
        stressLevel = max(0.0, stressLevel - 10.0)
    }
    
    private func updatePetState() {
        // 1. Gather inputs
        let cpuUsage = cpuUtility.getCPULoad()
        let memUsage = getSystemMemoryUsage()
        let isMusicPlaying = MusicManager.shared.isPlaying
        let isCharging = BatteryStatusViewModel.shared.isCharging
        let batteryLevel = BatteryStatusViewModel.shared.levelBattery
        
        // Check active application
        let activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let isCoding = isCodingApplication(activeAppName)
        
        // Check time of day
        let hour = Calendar.current.component(.hour, from: Date())
        let isNightTime = (hour >= 23 || hour < 6)
        
        // 2. Adjust levels based on inputs
        
        // Stress
        if cpuUsage > 70.0 || memUsage > 85.0 {
            stressLevel = min(100.0, stressLevel + 10.0)
            energyLevel = max(0.0, energyLevel - 3.0)
        } else if cpuUsage < 25.0 {
            stressLevel = max(0.0, stressLevel - 5.0)
        }
        
        // Music boosts happiness and energy, reduces stress
        if isMusicPlaying {
            happinessLevel = min(100.0, happinessLevel + 6.0)
            energyLevel = min(100.0, energyLevel + 3.0)
            stressLevel = max(0.0, stressLevel - 4.0)
        }
        
        // Battery status
        if batteryLevel < 20.0 && !isCharging {
            stressLevel = min(100.0, stressLevel + 4.0)
            energyLevel = max(0.0, energyLevel - 2.0)
            happinessLevel = max(0.0, happinessLevel - 2.0)
        } else if isCharging {
            happinessLevel = min(100.0, happinessLevel + 4.0)
            stressLevel = max(0.0, stressLevel - 4.0)
        }
        
        // Work focus / Coding
        if isCoding {
            attentionLevel = min(100.0, attentionLevel + 12.0)
            happinessLevel = min(100.0, happinessLevel + 2.0)
        } else {
            attentionLevel = max(0.0, attentionLevel - 6.0)
        }
        
        // Night sleepiness
        if isNightTime {
            energyLevel = max(0.0, energyLevel - 6.0)
        } else {
            energyLevel = min(100.0, energyLevel + 2.0)
        }
        
        // General decays & balancing towards homeostatic values
        if !isMusicPlaying && !isCharging && cpuUsage < 40.0 {
            // Gradual normalize
            stressLevel = max(0.0, stressLevel - 2.0)
            
            if happinessLevel > 50 {
                happinessLevel = max(50.0, happinessLevel - 1.0)
            } else {
                happinessLevel = min(50.0, happinessLevel + 1.0)
            }
            
            if energyLevel > 50 {
                energyLevel = max(50.0, energyLevel - 0.5)
            } else {
                energyLevel = min(50.0, energyLevel + 0.5)
            }
        }
        
        // 3. Determine current state
        if stressLevel > 60.0 {
            state = .stressed
            currentActivity = "Panicking (High CPU usage)"
        } else if isMusicPlaying {
            state = .excited
            currentActivity = "Dancing to music"
        } else if isNightTime && energyLevel < 35.0 {
            state = .sleepy
            currentActivity = "Dozing off"
        } else if energyLevel < 20.0 {
            state = .sleepy
            currentActivity = "Extremely tired"
        } else if attentionLevel > 65.0 {
            state = .focused
            currentActivity = "Concentrating on \(activeAppName)"
        } else if happinessLevel > 70.0 {
            state = .happy
            currentActivity = "Feeling joyful"
        } else {
            state = .idle
            currentActivity = "Chilling in the Notch"
        }
    }
    
    private func isCodingApplication(_ name: String) -> Bool {
        let lowercaseName = name.lowercased()
        let IDEs = ["xcode", "code", "intellij", "studio", "terminal", "sublime", "eclipse", "pycharm", "webstorm", "cursor"]
        return IDEs.contains(where: { lowercaseName.contains($0) })
    }
    
    private func getSystemMemoryUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0.0 }
        let active = Double(stats.active_count)
        let wire = Double(stats.wire_count)
        let free = Double(stats.free_count)
        let total = active + wire + free
        guard total > 0 else { return 0.0 }
        return (active + wire) / total * 100.0
    }
}

// MARK: - CPU Load Utility

class ProcessorLoadUtility {
    private var previousInfo: host_cpu_load_info_data_t?
    
    func getCPULoad() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0.0 }
        
        guard let prev = previousInfo else {
            previousInfo = info
            return 0.0
        }
        
        let userDiff = Double(info.cpu_ticks.0 - prev.cpu_ticks.0)
        let sysDiff = Double(info.cpu_ticks.1 - prev.cpu_ticks.1)
        let idleDiff = Double(info.cpu_ticks.2 - prev.cpu_ticks.2)
        let niceDiff = Double(info.cpu_ticks.3 - prev.cpu_ticks.3)
        
        previousInfo = info
        
        let total = userDiff + sysDiff + idleDiff + niceDiff
        guard total > 0 else { return 0.0 }
        
        return (userDiff + sysDiff + niceDiff) / total * 100.0
    }
}

// MARK: - Notch Pet Closed-Notch View

struct MinimalFaceFeatures: View {
    @ObservedObject var manager = PetManager.shared
    @EnvironmentObject var vm: BoringViewModel
    
    var height: CGFloat = 22
    var width: CGFloat = 32
    
    @State private var isBlinking = false
    @State private var breathingScale: CGFloat = 1.0
    @State private var yawnAnim = false
    @State private var shiverOffset: CGFloat = 0
    @State private var sweatDropY: CGFloat = -5
    @State private var clickBounce = false
    @State private var clickSpin = 0.0
    @State private var lookOffset: CGSize = .zero
    
    @State private var zLetters: [String] = []
    
    @State private var trackingTimer: Timer?
    @State private var isViewActive = false
    
    var body: some View {
        ZStack {
            // Idle/Breathing/Action Container
            VStack(spacing: 3) {
                // Eyes Row
                HStack(spacing: 5) {
                    eyeView(isLeft: true)
                    eyeView(isLeft: false)
                }
                .offset(lookOffset)
                
                // Nose and Mouth
                VStack(spacing: 1) {
                    // Nose
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: 2, height: 3)
                    
                    // Mouth
                    mouthView
                }
            }
            .scaleEffect(y: breathingScale, anchor: .bottom)
            .offset(x: shiverOffset, y: clickBounce ? -6 : 0)
            .rotationEffect(.degrees(clickSpin))
            
            // Sweating droplet (Stressed)
            if manager.state == .stressed {
                sweatDroplet
                    .offset(x: 10, y: sweatDropY)
            }
            
            // Sleep particles (zZz)
            if manager.state == .sleepy {
                ZStack {
                    ForEach(zLetters.indices, id: \.self) { idx in
                        Text("z")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .offset(x: CGFloat(idx * 6) - 10, y: -10 - CGFloat(idx * 6))
                    }
                }
            }
        }
        .frame(width: self.width, height: self.height)
        .contentShape(Rectangle())
        .onAppear {
            isViewActive = true
            setupTimers()
            PetManager.shared.activeViewCount += 1
        }
        .onDisappear {
            isViewActive = false
            trackingTimer?.invalidate()
            trackingTimer = nil
            PetManager.shared.activeViewCount -= 1
        }
        .onTapGesture {
            manager.recordClick()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                clickBounce = true
                clickSpin += 360.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                clickBounce = false
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func eyeView(isLeft: Bool) -> some View {
        Group {
            switch manager.state {
            case .sleepy:
                // Sleeping closed eyelids: u u
                Path { path in
                    path.addArc(center: CGPoint(x: 2, y: 1), radius: 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                }
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 4, height: 2)
                
            case .excited:
                // Happy curved eyes: ^ ^
                Path { path in
                    path.addArc(center: CGPoint(x: 2, y: 2), radius: 2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                }
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 4, height: 2)
                
            case .stressed:
                // Anxious slanted/slanting look: \ /
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
                    .rotationEffect(.degrees(isLeft ? 15 : -15))
                
            case .focused:
                // Flat focused lines: - -
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 4, height: 1.2)
                
            default:
                // Idle or Happy standard winking/blinking eyes
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
                    .frame(width: 3.5, height: isBlinking ? 1 : 3.5)
            }
        }
    }
    
    @ViewBuilder
    private var mouthView: some View {
        Group {
            switch manager.state {
            case .excited:
                // Open happy mouth
                GeometryReader { geo in
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w / 2, y: h))
                    }
                    .fill(Color.white)
                }
                .frame(width: 12, height: 6)
                
            case .sleepy:
                // Tiny yawn circle
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: yawnAnim ? 4 : 2, height: yawnAnim ? 4 : 2)
                
            case .stressed:
                // Anxious squiggly line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 2))
                    path.addLine(to: CGPoint(x: 3, y: 0))
                    path.addLine(to: CGPoint(x: 6, y: 4))
                    path.addLine(to: CGPoint(x: 9, y: 2))
                }
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 9, height: 4)
                
            case .focused:
                // Serious straight mouth
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.white)
                    .frame(width: 8, height: 1)
                
            case .happy:
                // Big smile curve
                GeometryReader { geo in
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height
                        path.move(to: CGPoint(x: 0, y: 1))
                        path.addQuadCurve(to: CGPoint(x: w, y: 1), control: CGPoint(x: w / 2, y: h))
                    }
                    .stroke(Color.white, lineWidth: 1.5)
                }
                .frame(width: 10, height: 4)
                
            default:
                // Default tiny curve
                GeometryReader { geo in
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height
                        path.move(to: CGPoint(x: 0, y: 1))
                        path.addQuadCurve(to: CGPoint(x: w, y: 1), control: CGPoint(x: w / 2, y: h))
                    }
                    .stroke(Color.white, lineWidth: 1.5)
                }
                .frame(width: 8, height: 3)
            }
        }
    }
    
    private var sweatDroplet: some View {
        Path { path in
            path.move(to: CGPoint(x: 2, y: 0))
            path.addCurve(to: CGPoint(x: 4, y: 5), control1: CGPoint(x: 3.5, y: 2), control2: CGPoint(x: 4, y: 3.5))
            path.addArc(center: CGPoint(x: 2, y: 5), radius: 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            path.addCurve(to: CGPoint(x: 2, y: 0), control1: CGPoint(x: 0, y: 3.5), control2: CGPoint(x: 0.5, y: 2))
        }
        .fill(Color.blue)
        .frame(width: 4, height: 7)
    }
    
    // MARK: - Animation Timers & Loop
    
    private func setupTimers() {
        // 1. Blinking timer (every 3-5s randomly)
        scheduleBlink()
        
        // 2. Breathing/Idle animation
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            breathingScale = 0.94
        }
        
        // 3. Loop tracking mouse and state updates
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard isViewActive else { return }
            
            // Sub-animations based on states
            if manager.state == .stressed {
                // Shiver effect
                shiverOffset = CGFloat.random(in: -1.2...1.2)
                
                // Sweat droplet drop
                withAnimation(.linear(duration: 0.1)) {
                    sweatDropY += 0.8
                    if sweatDropY > 15 {
                        sweatDropY = -5
                    }
                }
            } else {
                shiverOffset = 0
                sweatDropY = -5
            }
            
            if manager.state == .sleepy {
                // zZz floating particles
                if Double.random(in: 0...1) < 0.15 {
                    withAnimation(.easeOut(duration: 2.0)) {
                        if zLetters.count < 3 {
                            zLetters.append("z")
                        } else {
                            zLetters.removeFirst()
                            zLetters.append("z")
                        }
                    }
                }
                
                // Slow yawn mouth animation
                if Double.random(in: 0...1) < 0.08 {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        yawnAnim.toggle()
                    }
                }
            } else {
                zLetters.removeAll()
                yawnAnim = false
            }
            
            // Only track cursor look-offset when closed
            guard vm.notchState == .closed else {
                if lookOffset != .zero {
                    withAnimation(.easeOut(duration: 0.2)) {
                        lookOffset = .zero
                    }
                }
                return
            }
            
            // Cursor-look calculation
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.main {
                let notchX = screen.frame.midX
                let notchY = screen.frame.maxY
                let dx = mouse.x - notchX
                let dy = mouse.y - notchY
                let distance = hypot(dx, dy)
                
                if distance > 20 && distance < 350 {
                    let maxOffset: CGFloat = 1.8
                    lookOffset = CGSize(
                        width: (dx / distance) * maxOffset,
                        height: (dy / distance) * maxOffset * 0.7 // slightly less vertically
                    )
                } else {
                    if lookOffset != .zero {
                        withAnimation(.easeOut(duration: 0.2)) {
                            lookOffset = .zero
                        }
                    }
                }
            }
        }
    }
    
    private func scheduleBlink() {
        let interval = Double.random(in: 2.5...6.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            guard isViewActive else { return }
            guard manager.state != .sleepy && manager.state != .focused else {
                self.scheduleBlink()
                return
            }
            
            withAnimation(.spring(duration: 0.12)) {
                isBlinking = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard isViewActive else { return }
                withAnimation(.spring(duration: 0.12)) {
                    isBlinking = false
                }
                self.scheduleBlink()
            }
        }
    }
}

// MARK: - Expanded Pet Panel View

struct ExpandedPetPanelView: View {
    @ObservedObject var manager = PetManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @State private var feedScale: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: 20) {
            // Interactive Pet Avatar on Left
            VStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 80, height: 80)
                    
                    MinimalFaceFeatures()
                        .scaleEffect(2.2)
                }
                Spacer()
            }
            .frame(width: 110)
            
            // Stats Panel
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Notch Pet Details")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(manager.state.moodEmoji) \(manager.state.moodName)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                }
                
                Text(manager.currentActivity)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // Energy Bar
                progressBar(title: "Energy", val: manager.energyLevel, color: .orange)
                
                // Stress Bar
                progressBar(title: "Stress", val: manager.stressLevel, color: .red)
                
                // Interactive Buttons
                HStack(spacing: 12) {
                    Button(action: {
                        manager.feedPet()
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
                            feedScale = 1.2
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation {
                                feedScale = 1.0
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "fork.knife")
                            Text("Feed Cookie")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .scaleEffect(feedScale)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Text("🍖 x\(manager.totalFeeds)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    Text("Clicks: \(manager.totalClicks)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.gray)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .onAppear {
            PetManager.shared.activeViewCount += 1
        }
        .onDisappear {
            PetManager.shared.activeViewCount -= 1
        }
    }
    
    @ViewBuilder
    private func progressBar(title: String, val: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 50, alignment: .leading)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: CGFloat(val / 100.0) * geo.size.width)
                }
            }
            .frame(height: 6)
            
            Text("\(Int(val))%")
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(.gray)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

// Previews
struct AnimatedFace_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            MinimalFaceFeatures()
        }
        .frame(width: 100, height: 100)
    }
}
