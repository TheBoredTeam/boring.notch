import SwiftUI

struct NotificationCenterView: View {
    @ObservedObject var bridge: KairoNotificationBridge

    var body: some View {
        ScrollView {
            if bridge.items.isEmpty {
                VStack(spacing: 8) {
                    Text("All caught up").font(.system(size: 14, weight: .medium))
                    Text("Nothing to show").font(.system(size: 12))
                        .foregroundColor(Kairo.Palette.textDim)
                }
                .frame(maxWidth: .infinity).padding(.top, 80)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(bridge.items, id: \.self) { item in
                        NotificationRow(item: item, onDismiss: { bridge.dismiss(item) })
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
                .padding(12)
                .animation(Kairo.Motion.snappy, value: bridge.items)
            }
        }
    }
}

private struct NotificationRow: View {
    let item: NotificationData
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.icon).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.app.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.0)
                        .foregroundColor(Kairo.Palette.textDim)
                    Spacer()
                    Text(item.timestamp).font(.system(size: 9))
                        .foregroundColor(Kairo.Palette.textFaint)
                }
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.body).font(.system(size: 11))
                    .foregroundColor(Kairo.Palette.textDim).lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(Kairo.Palette.surface)
        )
        .contextMenu {
            Button("Dismiss", action: onDismiss)
        }
    }
}
