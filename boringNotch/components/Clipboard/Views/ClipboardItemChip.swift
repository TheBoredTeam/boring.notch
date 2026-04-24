import SwiftUI
import AppKit

struct ClipboardItemChip: View {
    let item: ClipboardItem
    let onTap: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    private var truncatedContent: String {
        switch item.kind {
        case .text(let content):
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 25 ? String(trimmed.prefix(25)) + "..." : trimmed
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // App icon on the left
            if let icon = AppIconHelper.getIcon(for: item.sourceApp) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.secondary)
            }
            
            // Content on the left after the icon
            Text(truncatedContent)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .padding(.leading, 8)
            
            Spacer(minLength: 8)
            
            // Pin on the right (if present)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 180, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovering ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            ClipboardContextMenu(
                item: item,
                onPin: onPin,
                onDelete: onDelete
            )
        }
    }
}
