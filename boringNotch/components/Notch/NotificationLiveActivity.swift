//
//  NotificationLiveActivity.swift
//  boringNotch
//
import SwiftUI

private struct NotificationSourceIcon: View {
    let bundleID: String?
    let size: CGFloat

    var body: some View {
        if let bundleID {
            appIcon(for: bundleID)
                .resizable()
                .aspectRatio(contentMode: .fit)
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

    var body: some View {
        HStack(spacing: 8) {
            NotificationSourceIcon(
                bundleID: notification.bundleID,
                size: max(0, vm.effectiveClosedNotchHeight - 12)
            )
            if let title = notification.title ?? notification.appName {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight)
    }

}

struct NotificationExpandedView: View {
    @ObservedObject private var manager = SystemNotificationManager.shared
    let notification: SystemNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NotificationSourceIcon(bundleID: notification.bundleID, size: 42)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(notification.appName ?? "Notification")
                        .font(.headline)
                        .lineLimit(1)
                    if manager.queuedNotifications.count > 0 {
                        Text("+\(manager.queuedNotifications.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(notification.receivedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let title = notification.title, title != notification.appName {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                if let subtitle = notification.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let body = notification.body {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Button {
                    Task {
                        _ = await manager.open(notification)
                        manager.dismissActive(token: notification.id)
                    }
                } label: {
                    Label("Open in \(notification.appName ?? "app")", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: 300, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .onAppear { manager.holdActive() }
        .onDisappear { manager.resumeDismiss() }
    }

}
