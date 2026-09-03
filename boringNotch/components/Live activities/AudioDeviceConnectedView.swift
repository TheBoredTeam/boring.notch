//
//  AudioDeviceConnectedView.swift
//  boringNotch
//
//  Created for AirPods Connected Reveal Feature
//

import SwiftUI
import RealityKit
import Defaults

/// A view that displays the connected audio device with 3D AirPods animation and battery ring
struct AudioDeviceConnectedView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @EnvironmentObject var vm: BoringViewModel
    
    @State private var airPodsRotation: Double = -185
    @State private var batteryProgress: CGFloat = 0
    @State private var showBatteryRing = false
    @State private var rotationTimer: Timer?
    
    // Extra height for expanded view
    private let extraHeight: CGFloat = 10
    
    var body: some View {
        if let device = audioDeviceManager.lastConnectedDevice {
            HStack(spacing: 0) {
                // Left side - Device Icon (3D for AirPods Pro, SF Symbol for others)
                DeviceIconView(deviceType: device.deviceType, rotation: airPodsRotation)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight + 15),
                        height: max(0, vm.effectiveClosedNotchHeight + 15)
                    )
                    .clipShape(Circle())
                    .padding(.leading, -6)
                    .padding(.bottom, 4)
                
                // Center - Black spacer (notch area)
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
                
                // Right side - Battery Ring
                ZStack {
                    Circle()
                        .stroke(batteryColor(for: device.batteryLevel).opacity(0.3), lineWidth: 3.2)
                    Circle()
                        .trim(from: 0, to: batteryProgress)
                        .stroke(batteryColor(for: device.batteryLevel),
                                style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    
                    if let battery = device.batteryLevel, Defaults[.showAudioDeviceBatteryPercentage] {
                        Text("\(battery)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 4),
                    height: max(0, vm.effectiveClosedNotchHeight - 4)
                )
                .padding(.trailing, 4)
                .padding(.bottom, 6)
                .opacity(showBatteryRing ? 1 : 0)
                .scaleEffect(showBatteryRing ? 1 : 0.5)
            }
            .frame(height: vm.effectiveClosedNotchHeight + extraHeight, alignment: .center)
            .onAppear { startAnimation(batteryLevel: device.batteryLevel) }
            .onDisappear { stopAnimation() }
        }
    }
    
    private func batteryColor(for level: Int?) -> Color {
        guard let level = level else { return .green }
        if level <= 20 { return .red }
        else if level <= 50 { return .yellow }
        else { return .green }
    }
    
    private func startAnimation(batteryLevel: Int?) {
        airPodsRotation = -185
        showBatteryRing = false
        batteryProgress = 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { startAirPodsRotation() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showBatteryRing = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.8)) {
                batteryProgress = CGFloat(batteryLevel ?? 100) / 100.0
            }
        }
    }
    
    private func startAirPodsRotation() {
        airPodsRotation = -185
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            airPodsRotation -= 0.35
            if airPodsRotation <= -305 {
                airPodsRotation = -305
                rotationTimer?.invalidate()
                rotationTimer = nil
            }
        }
    }
    
    private func stopAnimation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
}

// MARK: - Expanded Audio Device View (for open notch state)

/// Expanded view shown when hovering over the AirPods notification
struct AudioDeviceExpandedView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @EnvironmentObject var vm: BoringViewModel
    
    @State private var airPodsRotation: Double = -245
    @State private var showContent = false
    
    var body: some View {
        if let device = audioDeviceManager.lastConnectedDevice {
            HStack(spacing: 12) {
                // Left side - Device Icon
                DeviceIconView(deviceType: device.deviceType, rotation: airPodsRotation)
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                
                // Center - Connection status and device name
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verbunden")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                    
                    Text(device.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Right side - Battery indicators
                if let airPodsBattery = device.airPodsBattery, airPodsBattery.hasDetailedInfo {
                    // Show individual battery levels for AirPods
                    AirPodsBatteryDetailView(battery: airPodsBattery, deviceType: device.deviceType)
                } else if let battery = device.batteryLevel {
                    // Fallback: single battery ring
                    SingleBatteryRingView(level: battery)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(height: 70)
            .opacity(showContent ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { showContent = true }
            }
        }
    }
}

// MARK: - Single Battery Ring (fallback)
struct SingleBatteryRingView: View {
    let level: Int
    @State private var progress: CGFloat = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(batteryColor.opacity(0.3), lineWidth: 4.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(batteryColor, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(level)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 48, height: 48)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                progress = CGFloat(level) / 100.0
            }
        }
    }
    
    private var batteryColor: Color {
        if level <= 20 { return .red }
        else if level <= 50 { return .yellow }
        else { return .green }
    }
}

// MARK: - AirPods Detailed Battery View
struct AirPodsBatteryDetailView: View {
    let battery: AirPodsBatteryInfo
    let deviceType: AudioDeviceInfo.AudioDeviceType
    
    var body: some View {
        HStack(spacing: 14) {
            // Left earpiece
            if let left = battery.left {
                BatteryItemView(level: left, icon: "l.circle.fill", label: "L")
            }
            
            // Right earpiece
            if let right = battery.right {
                BatteryItemView(level: right, icon: "r.circle.fill", label: "R")
            }
            
            // Case (only for AirPods/AirPods Pro, not Max)
            if let caseLevel = battery.caseLevel, deviceType != .airpodsMax {
                BatteryItemView(level: caseLevel, icon: "case.fill", label: nil, isCase: true, deviceType: deviceType)
            }
        }
    }
}

// MARK: - Individual Battery Item
struct BatteryItemView: View {
    let level: Int
    let icon: String
    let label: String?
    var isCase: Bool = false
    var deviceType: AudioDeviceInfo.AudioDeviceType = .other
    
    @State private var progress: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(batteryColor.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(batteryColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                if isCase {
                    Image(systemName: deviceType.caseIcon)
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                } else if let label = label {
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 28, height: 28)
            
            Text("\(level)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.gray)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                progress = CGFloat(level) / 100.0
            }
        }
    }
    
    private var batteryColor: Color {
        if level <= 20 { return .red }
        else if level <= 50 { return .yellow }
        else { return .green }
    }
}

// MARK: - Device Icon View (shows different icons based on device type)

struct DeviceIconView: View {
    var deviceType: AudioDeviceInfo.AudioDeviceType
    var rotation: Double
    
    var body: some View {
        switch deviceType {
        case .airpodsPro:
            // 3D model for AirPods Pro
            AirPods3DModelView(modelName: "airpods_pro", rotation: rotation)
        case .airpods, .airpodsGen3, .airpods4:
            // 3D model for AirPods (normal/Gen3/4)
            AirPods3DModelView(modelName: "apple airpods_4", rotation: rotation)
        case .airpodsMax:
            // 3D model for AirPods Max
            AirPods3DModelView(modelName: "apple airpods_max_sky_blue", rotation: rotation)
        case .beatsHeadphones:
            // SF Symbol for Beats
            Image(systemName: "beats.headphones")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
        case .genericBluetooth:
            // Generic headphones icon
            Image(systemName: "headphones")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
        case .builtInSpeaker, .other:
            // Speaker icon for built-in/other
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - 3D Model View (supports different models)

struct AirPods3DModelView: View {
    var modelName: String
    var rotation: Double
    
    var body: some View {
        if #available(macOS 15.0, *) {
            AirPods3DRealityView(modelName: modelName, rotation: rotation)
        } else {
            // Fallback for macOS 14: Animated icon
            AirPodsFallbackView(rotation: rotation)
        }
    }
}

// Legacy wrapper for backwards compatibility
struct AirPods3DView: View {
    var rotation: Double
    
    var body: some View {
        AirPods3DModelView(modelName: "airpods_pro", rotation: rotation)
    }
}

// MARK: - RealityKit View (macOS 15+)

@available(macOS 15.0, *)
struct AirPods3DRealityView: View {
    var modelName: String
    var rotation: Double
    
    var body: some View {
        RealityView { content in
            if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "usdz") {
                do {
                    let entity = try await Entity(contentsOf: modelURL)
                    let bounds = entity.visualBounds(relativeTo: nil)
                    let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
                    let scale = maxExtent > 0 ? 1.5 / maxExtent : 0.01
                    
                    entity.scale = SIMD3<Float>(repeating: scale)
                    let center = bounds.center
                    entity.position = SIMD3<Float>(-center.x * scale, -center.y * scale, -center.z * scale)
                    content.add(entity)
                } catch {
                    // Inline fallback sphere
                    let sphere = MeshResource.generateSphere(radius: 0.02)
                    let mat = SimpleMaterial(color: .white, isMetallic: false)
                    content.add(ModelEntity(mesh: sphere, materials: [mat]))
                }
            } else {
                // Inline fallback sphere
                let sphere = MeshResource.generateSphere(radius: 0.02)
                let mat = SimpleMaterial(color: .white, isMetallic: false)
                content.add(ModelEntity(mesh: sphere, materials: [mat]))
            }
            
            let light = DirectionalLight()
            light.light.intensity = 2000
            light.look(at: .zero, from: SIMD3<Float>(0.5, 1, 1), relativeTo: nil)
            content.add(light)
            
            let ambient = PointLight()
            ambient.light.intensity = 500
            ambient.position = SIMD3<Float>(0, 0.5, 0)
            content.add(ambient)
            
        } update: { content in
            for entity in content.entities where !(entity is DirectionalLight || entity is PointLight) {
                entity.transform.rotation = simd_quatf(angle: Float(rotation * .pi / 180), axis: SIMD3<Float>(0, 1, 0))
            }
        }
        .background(Color.black)
    }
}

// MARK: - Fallback View (macOS 14)

struct AirPodsFallbackView: View {
    var rotation: Double
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
                .scaleEffect(pulseScale)
            
            Circle()
                .fill(Color.white.opacity(0.15))
                .scaleEffect(pulseScale * 0.8)
            
            Image(systemName: "airpodspro")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(rotation + 185)) // Compensate for initial offset
        }
        .background(Color.black)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }
}

#Preview {
    AirPods3DView(rotation: -220)
        .frame(width: 60, height: 60)
        .clipShape(Circle())
        .background(Color.black)
}
