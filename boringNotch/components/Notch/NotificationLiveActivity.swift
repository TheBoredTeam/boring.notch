// Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
// Attribution applies to the extension platform contributions.

//
//  NotificationLiveActivity.swift
//  boringNotch
//

import SwiftUI

struct NotificationSourceIcon: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        if let bundleID {
            appIcon(for: bundleID)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        } else {
            Image(systemName: "bell")
                .font(.system(size: size * 0.55))
                .frame(width: size, height: size)
        }
    }
}

struct NotificationLiveActivity: View {
    @EnvironmentObject private var vm: BoringViewModel
    let notification: SystemNotification

    private var itemSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    var body: some View {
        NotchActivityHost(
            contentID: notification.id,
            safeAreaWidth: vm.closedNotchSize.width,
            height: vm.effectiveClosedNotchHeight,
            maximumWidth: windowSize.width - 2 * cornerRadiusInsets.closed.bottom
        ) {
            NotificationSourceIcon(bundleID: notification.bundleID, size: itemSize)
        } trailing: {
            NotificationActivityIndicator(itemSize: itemSize)
        }
    }
}

struct NotificationActivityIndicator: View {
    let itemSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.effectiveAccent, lineWidth: 1.5)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)
            Circle()
                .fill(Color.effectiveAccent)
                .frame(width: 7, height: 7)
        }
        .frame(width: itemSize, height: itemSize)
        .onAppear { pulse() }
        .accessibilityHidden(true)
    }

    private func pulse() {
        guard !reduceMotion else { return }
        ringScale = 1
        ringOpacity = 0.8
        withAnimation(.easeOut(duration: 0.6)) {
            ringScale = 1.8
            ringOpacity = 0
        }
    }
}

struct NotificationExpandedView: View {
    @ObservedObject private var manager = SystemNotificationManager.shared
    let notification: SystemNotification

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: openSourceApp) {
                HStack(alignment: .center, spacing: 12) {
                    NotificationSourceIcon(bundleID: notification.bundleID, size: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(notification.appName ?? "Notification")
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)

                            Text(notification.receivedAt, style: .relative)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                        }

                        if let title = notification.title, title != notification.appName {
                            Text(title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }

                        if let subtitle = notification.subtitle {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let body = notification.body {
                            Text(body)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary.opacity(0.9))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(notification.appName ?? "App") notification")
            .accessibilityHint("Opens \(notification.appName ?? "the app")")

            HStack(spacing: 4) {
                if !manager.queuedNotifications.isEmpty {
                    Button {
                        manager.showNextQueued()
                    } label: {
                        Text("+\(manager.queuedNotifications.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show next queued notification")
                }

                Button {
                    manager.dismissActive(token: notification.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification")
            }
            .padding(.trailing, 4)
        }
        .onAppear { manager.holdActive() }
        .onDisappear { manager.resumeDismiss() }
    }

    private func openSourceApp() {
        Task {
            guard await manager.open(notification) else { return }
            manager.dismissActive(token: notification.id)
        }
    }
}
