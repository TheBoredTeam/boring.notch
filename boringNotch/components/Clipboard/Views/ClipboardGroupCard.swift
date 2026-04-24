import SwiftUI
import AppKit

struct ClipboardGroupCard: View {
    let appName: String
    let bundleId: String
    let items: [ClipboardItem]
    let onTap: (ClipboardItem) -> Void
    let onPin: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Minimal header
            HStack(spacing: 6) {
                if let icon = AppIconHelper.getIcon(for: bundleId) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app")
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.secondary)
                }
                
                Text(appName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Text("•")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.5))
                
                Text("\(items.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.leading, 8)
            
            // Horizontal chips on two rows
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    // First row: odd elements (1st, 3rd, 5th...)
                    HStack(spacing: 8) {
                        ForEach(items.indices.filter { $0 % 2 == 0 }, id: \.self) { index in
                            ClipboardItemChip(
                                item: items[index],
                                onTap: { onTap(items[index]) },
                                onPin: { onPin(items[index]) },
                                onDelete: { onDelete(items[index]) }
                            )
                        }
                    }
                    
                    // Second row: even elements (2nd, 4th, 6th...)
                    if items.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(items.indices.filter { $0 % 2 == 1 }, id: \.self) { index in
                                ClipboardItemChip(
                                    item: items[index],
                                    onTap: { onTap(items[index]) },
                                    onPin: { onPin(items[index]) },
                                    onDelete: { onDelete(items[index]) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
        )
    }
}
