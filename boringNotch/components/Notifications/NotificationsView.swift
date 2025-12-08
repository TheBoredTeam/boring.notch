import Defaults
import SwiftUI

struct NotificationsView: View {
    @ObservedObject var manager = NotificationCenterManager.shared
    @Default(.enableNotifications) var enableNotifications
    @Default(.showBatteryNotifications) var showBatteryNotifications
    @Default(.showCalendarNotifications) var showCalendarNotifications
    @Default(.showShelfNotifications) var showShelfNotifications
    @Default(.showSystemNotifications) var showSystemNotifications
    @Default(.showInfoNotifications) var showInfoNotifications

    // Keep the open notch height consistent across tabs, even when notifications are disabled/empty.
    private let minContentHeight: CGFloat = 240

    private let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !enableNotifications {
                Text("알림이 비활성화되어 있어요. 설정에서 켜주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else if filteredNotifications.isEmpty {
                HStack {
                    Spacer()
                    EmptyStateView(message: "표시할 알림이 없어요")
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(filteredNotifications) { notification in
                            NotificationRow(
                                notification: notification,
                                formatter: formatter
                            )
                            .onTapGesture {
                                manager.markAsRead(notification.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .frame(minHeight: minContentHeight, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("배터리와 시스템 이벤트를 한 곳에서 확인하세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("모두 읽음") {
                        manager.markAllRead()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("비우기") {
                        manager.clear()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var filteredNotifications: [NotchNotification] {
        let enabledCategories = Set([
            showBatteryNotifications ? NotchNotificationCategory.battery : nil,
            showCalendarNotifications ? NotchNotificationCategory.calendar : nil,
            showShelfNotifications ? NotchNotificationCategory.shelf : nil,
            showSystemNotifications ? NotchNotificationCategory.system : nil,
            showInfoNotifications ? NotchNotificationCategory.info : nil
        ].compactMap { $0 })

        return manager.notifications.filter { enabledCategories.contains($0.category) }
    }
}

private struct NotificationRow: View {
    let notification: NotchNotification
    let formatter: RelativeDateTimeFormatter

    private var relativeDate: String {
        formatter.localizedString(for: notification.date, relativeTo: Date())
    }

    private var iconColor: Color {
        switch notification.category {
        case .battery:
            return .green
        case .calendar:
            return .cyan
        case .shelf:
            return .orange
        case .system:
            return .yellow
        case .info:
            return .blue
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.category.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .padding(6)
                .background(.black.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(relativeDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(notification.isRead ? Color.black.opacity(0.2) : Color(nsColor: .controlAccentColor).opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(notification.isRead ? Color.white.opacity(0.08) : Color(nsColor: .controlAccentColor).opacity(0.4), lineWidth: 1)
        )
    }
}

