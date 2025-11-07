//
//  LoftHeader.swift
//  Zenith Loft (LoftOS)
//
//  Clean-room replacement for BoringHeader.swift.
//  - No Defaults / BoringViewModel / singletons
//  - Pass flags & battery values as inputs
//  - Provide custom “tabs” content via a ViewBuilder
//  - Middle notch mask keeps the visual “pill” feel
//

import SwiftUI
import AppKit

// MARK: - Simple local notch state (so we don't depend on app state types)
public enum LoftNotchState {
    case closed, open
}

// MARK: - Simple notch mask (capsule-like)
public struct LoftNotchShape: Shape {
    public func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.height, rect.width) / 2)
    }
}

// MARK: - Header
public struct LoftHeader<Tabs: View>: View {

    // State you’d normally get from a view model
    public var notchState: LoftNotchState = .open
    public var closedNotchSize: CGSize = .init(width: 120, height: 32)

    // Left “tabs” content (or leave empty)
    @ViewBuilder public var tabs: () -> Tabs

    // Flags
    public var showTabs: Bool = true
    public var alwaysShowTabs: Bool = false
    public var showMirror: Bool = false
    public var showSettingsIcon: Bool = true
    public var showBatteryIndicator: Bool = true

    // Battery values
    public var batteryWidth: CGFloat = 30
    public var batteryLevel: Float = 85
    public var batteryCharging: Bool = false
    public var batteryPluggedIn: Bool = false
    public var batteryLowPower: Bool = false
    public var batteryMaxCapacity: Float = 100
    public var batteryTimeToFull: Int = 0

    // Callbacks
    public var onToggleCameraPreview: () -> Void = {}
    public var onOpenSettings: () -> Void = { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) }

    // Which display are we rendering on (for notch-mask color heuristics)
    public var selectedScreenName: String? = NSScreen.main?.localizedName

    public init(
        notchState: LoftNotchState = .open,
        closedNotchSize: CGSize = .init(width: 120, height: 32),
        showTabs: Bool = true,
        alwaysShowTabs: Bool = false,
        showMirror: Bool = false,
        showSettingsIcon: Bool = true,
        showBatteryIndicator: Bool = true,
        batteryWidth: CGFloat = 30,
        batteryLevel: Float = 85,
        batteryCharging: Bool = false,
        batteryPluggedIn: Bool = false,
        batteryLowPower: Bool = false,
        batteryMaxCapacity: Float = 100,
        batteryTimeToFull: Int = 0,
        selectedScreenName: String? = NSScreen.main?.localizedName,
        onToggleCameraPreview: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        @ViewBuilder tabs: @escaping () -> Tabs
    ) {
        self.notchState = notchState
        self.closedNotchSize = closedNotchSize
        self.showTabs = showTabs
        self.alwaysShowTabs = alwaysShowTabs
        self.showMirror = showMirror
        self.showSettingsIcon = showSettingsIcon
        self.showBatteryIndicator = showBatteryIndicator
        self.batteryWidth = batteryWidth
        self.batteryLevel = batteryLevel
        self.batteryCharging = batteryCharging
        self.batteryPluggedIn = batteryPluggedIn
        self.batteryLowPower = batteryLowPower
        self.batteryMaxCapacity = batteryMaxCapacity
        self.batteryTimeToFull = batteryTimeToFull
        self.selectedScreenName = selectedScreenName
        self.onToggleCameraPreview = onToggleCameraPreview
        self.onOpenSettings = onOpenSettings
        self.tabs = tabs
    }

    public var body: some View {
        HStack(spacing: 0) {

            // LEFT: tabs (if any)
            HStack {
                if (showTabs && alwaysShowTabs) || (showTabs && notchState == .open) {
                    tabs()
                } else if notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(notchState == .closed ? 0 : 1)
            .blur(radius: notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: notchState)
            .zIndex(2)

            // MIDDLE: the “notch mask” (only visible when open)
            if notchState == .open {
                Rectangle()
                    .fill(hasNotchOnSelectedScreen ? .black : .clear)
                    .frame(width: closedNotchSize.width, height: closedNotchSize.height)
                    .mask {
                        LoftNotchShape()
                    }
            }

            // RIGHT: utility buttons + battery
            HStack(spacing: 4) {
                if notchState == .open {
                    if showMirror {
                        buttonCapsule(systemName: "web.camera") {
                            onToggleCameraPreview()
                        }
                    }
                    if showSettingsIcon {
                        buttonCapsule(systemName: "gear") {
                            onOpenSettings()
                        }
                    }
                    if showBatteryIndicator {
                        // Uses the drop-in Battery view we already created
                        BoringBatteryView(
                            batteryWidth: batteryWidth,
                            isCharging: batteryCharging,
                            isInLowPowerMode: batteryLowPower,
                            isPluggedIn: batteryPluggedIn,
                            levelBattery: batteryLevel,
                            maxCapacity: batteryMaxCapacity,
                            timeToFullCharge: batteryTimeToFull,
                            isForNotification: false
                        )
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(notchState == .closed ? 0 : 1)
            .blur(radius: notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
    }

    // MARK: helpers

    private var hasNotchOnSelectedScreen: Bool {
        guard let name = selectedScreenName,
              let screen = NSScreen.screens.first(where: { $0.localizedName == name }) else {
            return false
        }
        // Macs with a notch report a non-zero top safeArea inset
        return screen.safeAreaInsets.top > 0
    }

    @ViewBuilder
    private func buttonCapsule(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: systemName)
                        .foregroundColor(.white)
                        .imageScale(.medium)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Convenience overload (no tabs)
public extension LoftHeader where Tabs == EmptyView {
    init(
        notchState: LoftNotchState = .open,
        closedNotchSize: CGSize = .init(width: 120, height: 32),
        showTabs: Bool = false,
        alwaysShowTabs: Bool = false,
        showMirror: Bool = false,
        showSettingsIcon: Bool = true,
        showBatteryIndicator: Bool = true,
        batteryWidth: CGFloat = 30,
        batteryLevel: Float = 85,
        batteryCharging: Bool = false,
        batteryPluggedIn: Bool = false,
        batteryLowPower: Bool = false,
        batteryMaxCapacity: Float = 100,
        batteryTimeToFull: Int = 0,
        selectedScreenName: String? = NSScreen.main?.localizedName,
        onToggleCameraPreview: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.init(
            notchState: notchState,
            closedNotchSize: closedNotchSize,
            showTabs: showTabs,
            alwaysShowTabs: alwaysShowTabs,
            showMirror: showMirror,
            showSettingsIcon: showSettingsIcon,
            showBatteryIndicator: showBatteryIndicator,
            batteryWidth: batteryWidth,
            batteryLevel: batteryLevel,
            batteryCharging: batteryCharging,
            batteryPluggedIn: batteryPluggedIn,
            batteryLowPower: batteryLowPower,
            batteryMaxCapacity: batteryMaxCapacity,
            batteryTimeToFull: batteryTimeToFull,
            selectedScreenName: selectedScreenName,
            onToggleCameraPreview: onToggleCameraPreview,
            onOpenSettings: onOpenSettings
        ) { EmptyView() }
    }
}

// MARK: - Optional: keep old name working during migration
public typealias BoringHeader = LoftHeader<EmptyView>

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        LoftHeader(
            notchState: .open,
            closedNotchSize: .init(width: 140, height: 32),
            showTabs: true,
            alwaysShowTabs: true,
            showMirror: true,
            showSettingsIcon: true,
            showBatteryIndicator: true,
            batteryWidth: 30,
            batteryLevel: 78,
            batteryCharging: true,
            batteryPluggedIn: true,
            batteryLowPower: false,
            batteryMaxCapacity: 95,
            batteryTimeToFull: 22,
            selectedScreenName: NSScreen.main?.localizedName,
            onToggleCameraPreview: { print("toggle camera preview") },
            onOpenSettings: { print("open settings") }
        ) {
            // Example “tabs” placeholder
            HStack(spacing: 8) {
                Text("Calendar").foregroundStyle(.white)
                Text("Timers").foregroundStyle(.white.opacity(0.7))
                Text("Downloads").foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
    }
    .frame(width: 520, height: 80)
}
