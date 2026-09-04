//
//  AudioDeviceConnectedView.swift
//  boringNotch
//
//  Created for AirPods Connected Reveal Feature
//

import SwiftUI
import RealityKit
import Defaults

// MARK: - AudioDeviceConnectedView

/// Displays a connected audio device notification with 3D animation and battery ring.
///
/// This view is shown in the notch when a Bluetooth audio device (like AirPods)
/// connects. It features:
/// - A 3D rotating AirPods model on the left (using RealityKit on macOS 15+)
/// - The notch area in the center
/// - An animated battery ring on the right
///
/// ## Animation Sequence
/// 1. AirPods model rotates from -185° to -305°
/// 2. Battery ring appears with spring animation
/// 3. Battery progress fills based on device battery level
///
/// ## Usage
/// This view is automatically displayed by `BoringViewCoordinator` when
/// `AudioDeviceManager` detects a Bluetooth device connection.
struct AudioDeviceConnectedView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @EnvironmentObject var vm: BoringViewModel
    
    /// Current rotation angle of the AirPods 3D model
    @State private var airPodsRotation: Double = -185
    
    /// Battery ring fill progress (0.0 - 1.0)
    @State private var batteryProgress: CGFloat = 0
    
    /// Controls battery ring visibility with spring animation
    @State private var showBatteryRing = false
    
    /// Timer for smooth AirPods rotation animation
    @State private var rotationTimer: Timer?
    
    /// Extra height added to accommodate the expanded view
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
    
    /// Returns the appropriate color for a battery level.
    ///
    /// Color coding: Red (≤20%), Yellow (21-50%), Green (>50%)
    private func batteryColor(for level: Int?) -> Color {
        guard let level = level else { return .green }
        if level <= 20 { return .red }
        else if level <= 50 { return .yellow }
        else { return .green }
    }
    
    /// Starts the entry animation sequence.
    ///
    /// - Parameter batteryLevel: Device battery level for the progress ring
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
    
    /// Starts the smooth AirPods rotation animation using a timer.
    ///
    /// Rotates from -185° to -305° at 60 FPS for a smooth showcase effect.
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
    
    /// Stops and cleans up the rotation animation timer.
    private func stopAnimation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
}

// MARK: - AudioDeviceExpandedView

/// Expanded view displayed when hovering over the AirPods notification.
///
/// Shows more detailed information including:
/// - Device 3D model or icon (with continuous rotation)
/// - "Connected" label
/// - Device name
/// - Individual battery levels for AirPods (L/R/Case)
///
/// This view is displayed when the notch is in the expanded (open) state.
struct AudioDeviceExpandedView: View {
    @ObservedObject var audioDeviceManager = AudioDeviceManager.shared
    @EnvironmentObject var vm: BoringViewModel
    
    @State private var airPodsRotation: Double = -185
    @State private var showContent = false
    @State private var rotationTimer: Timer?
    
    var body: some View {
        if let device = audioDeviceManager.lastConnectedDevice {
            HStack(spacing: 16) {
                // Left side - Device Icon with continuous rotation
                DeviceIconView(deviceType: device.deviceType, rotation: airPodsRotation)
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                
                // Center - Connection status and device name
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                    
                    Text(device.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Right side - Battery indicators (always show L/R/Case circles for AirPods)
                if device.isAirPods {
                    // Always show L/R/Case circles for AirPods
                    ExpandedAirPodsBatteryView(
                        airPodsBattery: device.airPodsBattery,
                        overallBattery: device.batteryLevel,
                        deviceType: device.deviceType
                    )
                } else if let battery = device.batteryLevel {
                    // Fallback: single battery ring for non-AirPods
                    SingleBatteryRingView(level: battery)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(height: 70)
            .opacity(showContent ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) { showContent = true }
                startContinuousRotation()
            }
            .onDisappear {
                stopRotation()
            }
        }
    }
    
    /// Starts continuous rotation animation for the 3D model
    private func startContinuousRotation() {
        airPodsRotation = -185
        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { _ in
            airPodsRotation -= 0.3
            // Loop back when reaching -360
            if airPodsRotation <= -360 {
                airPodsRotation = -185
            }
        }
    }
    
    /// Stops the rotation animation timer
    private func stopRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
}

// MARK: - SingleBatteryRingView

/// Fallback battery ring view for devices without individual battery info.
///
/// Displays a single circular progress ring with the overall battery percentage.
/// Used when detailed L/R/Case battery info is not available.
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

// MARK: - ExpandedAirPodsBatteryView

/// Battery view for expanded AirPods notification.
/// Always shows L/R/Case circles, using detailed info if available or overall battery as fallback.
struct ExpandedAirPodsBatteryView: View {
    let airPodsBattery: AirPodsBatteryInfo?
    let overallBattery: Int?
    let deviceType: AudioDeviceInfo.AudioDeviceType
    
    var body: some View {
        HStack(spacing: 20) {
            // Left earpiece
            BatteryCircleView(
                level: airPodsBattery?.left ?? overallBattery,
                label: "L"
            )
            
            // Right earpiece
            BatteryCircleView(
                level: airPodsBattery?.right ?? overallBattery,
                label: "R"
            )
            
            // Case (only for AirPods with case, not Max)
            if deviceType != .airpodsMax {
                BatteryCircleView(
                    level: airPodsBattery?.caseLevel ?? overallBattery,
                    label: nil,
                    isCase: true,
                    deviceType: deviceType
                )
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - BatteryCircleView

/// A battery circle indicator for the expanded view.
/// Shows a circular progress ring with label (L/R) or case icon.
struct BatteryCircleView: View {
    let level: Int?
    var label: String? = nil
    var isCase: Bool = false
    var deviceType: AudioDeviceInfo.AudioDeviceType = .other
    
    @State private var progress: CGFloat = 0
    
    private var displayLevel: Int {
        level ?? 0
    }
    
    private var hasData: Bool {
        level != nil
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(batteryColor.opacity(0.3), lineWidth: 4)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(batteryColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                // Label or icon
                if isCase {
                    Image(systemName: deviceType.caseIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                } else if let label = label {
                    Text(label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            
            // Battery percentage
            Text(hasData ? "\(displayLevel)%" : "--")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.gray)
        }
        .onAppear {
            if hasData {
                withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                    progress = CGFloat(displayLevel) / 100.0
                }
            }
        }
    }
    
    private var batteryColor: Color {
        guard hasData else { return .gray }
        if displayLevel <= 20 { return .red }
        else if displayLevel <= 50 { return .yellow }
        else { return .green }
    }
}

// MARK: - AirPodsBatteryDetailView

/// Displays individual battery levels for AirPods components.
///
/// Shows up to three battery rings:
/// - Left earpiece (L)
/// - Right earpiece (R)
/// - Charging case (with case icon)
///
/// The case icon changes based on the AirPods model type.
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

// MARK: - BatteryItemView

/// A single battery indicator with circular progress ring and label.
///
/// Used within `AirPodsBatteryDetailView` to show individual component batteries.
/// Supports both text labels (L/R) and icons (charging case).
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

// MARK: - DeviceIconView

/// Displays the appropriate icon or 3D model based on device type.
///
/// For AirPods variants (Pro, normal, Gen3, 4, Max), shows a 3D model using RealityKit.
/// For other devices (Beats, generic Bluetooth), shows the appropriate SF Symbol.
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

// MARK: - AirPods3DModelView

/// Wrapper view that chooses between RealityKit (macOS 15+) and fallback animation.
///
/// Loads USDZ models for different AirPods types:
/// - `airpods_pro.usdz` - AirPods Pro
/// - `apple airpods_4.usdz` - AirPods (normal/Gen3/4)
/// - `apple airpods_max_sky_blue.usdz` - AirPods Max
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

// MARK: - AirPods3DView (Legacy)

/// Legacy wrapper for backwards compatibility.
///
/// Simply wraps `AirPods3DModelView` with the AirPods Pro model.
/// Kept for any existing code that may reference this view directly.
struct AirPods3DView: View {
    var rotation: Double
    
    var body: some View {
        AirPods3DModelView(modelName: "airpods_pro", rotation: rotation)
    }
}

// MARK: - AirPods3DRealityView

/// RealityKit-based 3D model view for macOS 15+.
///
/// Loads a USDZ model asynchronously and displays it with:
/// - Auto-scaling based on model bounds
/// - Y-axis rotation controlled by the `rotation` parameter
/// - Directional and ambient lighting
///
/// Falls back to a white sphere if the model fails to load.
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

// MARK: - AirPodsFallbackView

/// Fallback animated view for macOS 14 (without RealityKit).
///
/// Displays a pulsing circle animation with an AirPods SF Symbol.
/// Used when RealityKit is not available (macOS < 15).
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
