//
//  LockScreenWidgetSupport.swift
//  boringNotch
//
//  Shared SkyLight window and display placement support for lock-screen widgets.
//

import AppKit
import CoreGraphics
import Defaults
import Foundation
import SkyLightWindow
import SwiftUI

enum LockScreenText {
    static func value(_ key: String) -> String {
        let localized = NSLocalizedString(key, comment: "")
        guard localized == key, usesSimplifiedChinese else { return localized }
        return simplifiedChinese[key] ?? key
    }

    private static var usesSimplifiedChinese: Bool {
        let selectedLanguage = Defaults[.appLanguage]
        return selectedLanguage.rawValue.hasPrefix("zh")
            || (selectedLanguage == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
    }

    private static let simplifiedChinese: [String: String] = [
        "Alignment": "对齐方式",
        "Allow location access": "允许访问位置",
        "Appearance": "外观",
        "Calendar look-ahead": "日历预览范围",
        "Cancel": "取消",
        "Cancel timer": "取消计时",
        "Center": "居中",
        "Charging": "正在充电",
        "Charging %@": "正在充电 %@",
        "Circular": "圆形",
        "Clear": "晴朗",
        "Celsius": "摄氏度",
        "Dark": "深色",
        "Displays the next incomplete reminder that is due within the calendar look-ahead window.": "显示日历预览范围内下一条未完成且到期的提醒事项。",
        "Drizzle": "毛毛雨",
        "Duration": "时长",
        "Fahrenheit": "华氏度",
        "Focus": "专注模式",
        "Focus is active": "专注模式已开启",
        "Focus name": "专注模式名称",
        "Foggy": "有雾",
        "Inline": "横向",
        "Left": "左侧",
        "Light": "浅色",
        "Lock Screen": "锁定屏幕",
        "minutes": "分钟",
        "Minutes": "分钟",
        "Next track": "下一首",
        "Not Playing": "未在播放",
        "Overcast": "阴天",
        "Partly cloudy": "晴间多云",
        "Pause": "暂停",
        "Pause timer": "暂停计时",
        "Play": "播放",
        "Plugged in": "已接通电源",
        "Previous track": "上一首",
        "px": "像素",
        "Rain": "下雨",
        "Reminder": "提醒事项",
        "Reminders": "提醒事项",
        "Remaining": "剩余时间",
        "Restart timer": "重新开始计时",
        "Resume timer": "继续计时",
        "Right": "右侧",
        "Show air quality": "显示空气质量",
        "Show Bluetooth audio output": "显示蓝牙音频输出",
        "Show charging percentage": "显示充电百分比",
        "Show charging state": "显示充电状态",
        "Show Focus status": "显示专注模式状态",
        "Show location": "显示位置",
        "Show Mac battery": "显示 Mac 电池",
        "Show media widget": "显示媒体小组件",
        "Show next calendar event": "显示下一个日历事件",
        "Show reminder widget": "显示提醒事项小组件",
        "Show sunrise": "显示日出时间",
        "Show timer widget": "显示计时器小组件",
        "Show weather and status widget": "显示天气与状态小组件",
        "Snow": "下雪",
        "Start timer": "开始计时",
        "Status rows": "状态信息",
        "Style": "样式",
        "Temperature": "温度单位",
        "Thunderstorm": "雷暴",
        "Timer": "计时器",
        "Vertical offset": "垂直偏移",
        "Weather": "天气",
        "Weather is provided by Open-Meteo. Boring Notch asks for your location only after you allow it.": "天气数据由 Open-Meteo 提供。只有在你允许后，Boring Notch 才会请求位置。",
        "Weather unavailable": "天气暂不可用",
        "Widgets": "小组件",
        "Widgets are only visible while the Mac is locked. Enable the widgets you want below.": "小组件只会在 Mac 锁定时显示。请在下方启用需要的组件。",
        "Width": "宽度",
        "h": "小时"
    ]
}

struct LockScreenDisplayContext {
    let screen: NSScreen
    let frame: NSRect
}

@MainActor
final class LockScreenDisplayContextProvider {
    static let shared = LockScreenDisplayContextProvider()

    private var context: LockScreenDisplayContext?
    private var observers: [NSObjectProtocol] = []

    private init() {
        refresh()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.refresh()
            }
        })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                _ = self?.refresh()
            }
        })
    }

    func snapshot() -> LockScreenDisplayContext? {
        context ?? refresh()
    }

    @discardableResult
    func refresh() -> LockScreenDisplayContext? {
        guard let screen = preferredScreen() else {
            context = nil
            return nil
        }

        let newContext = LockScreenDisplayContext(screen: screen, frame: screen.frame)
        context = newContext
        return newContext
    }

    private func preferredScreen() -> NSScreen? {
        if let builtIn = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }) {
            return builtIn
        }

        return NSScreen.main ?? NSScreen.screens.first
    }
}

@MainActor
final class LockScreenWidgetPanel {
    private var window: NSPanel?
    private var delegatedToSkyLight = false
    private let allowsInteraction: Bool

    init(allowsInteraction: Bool) {
        self.allowsInteraction = allowsInteraction
    }

    var isVisible: Bool { window?.isVisible == true }
    var frame: NSRect? { window?.frame }

    func show<Content: View>(
        _ content: Content,
        frame: NSRect,
        cornerRadius: CGFloat = 24
    ) {
        let panel = ensureWindow(frame: frame)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]

        panel.setFrame(frame, display: true)
        panel.contentView = hostingView
        panel.ignoresMouseEvents = !allowsInteraction
        panel.sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite

        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.masksToBounds = true
            contentView.layer?.cornerRadius = cornerRadius
        }

        if !delegatedToSkyLight {
            SkyLightOperator.shared.delegateWindow(panel)
            delegatedToSkyLight = true
        }

        panel.orderFrontRegardless()
    }

    func move(to frame: NSRect) {
        window?.setFrame(frame, display: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func ensureWindow(frame: NSRect) -> NSPanel {
        if let window { return window }

        let newWindow = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        newWindow.isMovable = false
        newWindow.hasShadow = false
        newWindow.hidesOnDeactivate = false
        newWindow.acceptsMouseMovedEvents = allowsInteraction
        newWindow.ignoresMouseEvents = !allowsInteraction
        window = newWindow
        return newWindow
    }
}

struct LockScreenWidgetCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let appearance = Defaults[.lockScreenWidgetAppearance]
        content
            .foregroundStyle(appearance == .dark ? .white : .black)
            .background(background(for: appearance))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        appearance == .dark ? .white.opacity(0.18) : .black.opacity(0.12),
                        lineWidth: 1
                    )
            }
            .preferredColorScheme(appearance == .dark ? .dark : .light)
    }

    @ViewBuilder
    private func background(for appearance: LockScreenWidgetAppearance) -> some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(
                    .clear.tint(appearance == .dark ? .white.opacity(0.16) : .white.opacity(0.28)),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(appearance == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.48))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

enum LockScreenWidgetLayout {
    static func media(in screen: NSRect, size: CGSize) -> NSRect {
        NSRect(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height - 100,
            width: size.width,
            height: size.height
        )
    }

    static func timer(in screen: NSRect, size: CGSize, offset: CGFloat) -> NSRect {
        let y = max(screen.minY + 100, screen.midY - 84 + clamped(offset))
        return NSRect(x: screen.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    static func weather(in screen: NSRect, size: CGSize, offset: CGFloat) -> NSRect {
        let y = min(screen.maxY - size.height - 72, screen.midY + 76 + clamped(offset))
        return NSRect(x: screen.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    static func reminder(
        in screen: NSRect,
        size: CGSize,
        alignment: LockScreenReminderAlignment,
        offset: CGFloat
    ) -> NSRect {
        let x: CGFloat
        switch alignment {
        case .leading: x = screen.minX + 24
        case .center: x = screen.midX - size.width / 2
        case .trailing: x = screen.maxX - size.width - 24
        }
        let y = min(screen.maxY - size.height - 40, screen.midY + 8 + clamped(offset))
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func clamped(_ offset: CGFloat) -> CGFloat {
        min(max(offset, -160), 160)
    }
}
