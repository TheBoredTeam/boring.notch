import SwiftUI
import AppKit

struct NotchClipboardHistoryView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Clipboard is empty")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.items) { item in
                            ClipboardHistoryRow(
                                item: item,
                                isActive: item.id == viewModel.activeItemID,
                                onCopy: {
                                    copyToClipboard(item)
                                    viewModel.setActiveItem(item)
                                },
                                onDelete: {
                                    viewModel.delete(item)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.content {
        case .text(let str):
            pb.setString(str, forType: .string)
        case .image(let img):
            if let tiffData = img.tiffRepresentation {
                pb.setData(tiffData, forType: .tiff)
            }
        }
    }
}

struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let isActive: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Preview
            switch item.content {
            case .text(let str):
                Text(str)
                    .lineLimit(2)
                    .foregroundColor(.white)
            case .image(let img):
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 60)
            }
            
            Spacer()
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.accentColor.opacity(0.2) :
                      (isPressed ? Color.white.opacity(0.15) :
                       (isHovered ? Color.white.opacity(0.08) : Color.clear)))
        )
        .focusable(false) // disables macOS focus ring
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.7), lineWidth: 0.3)
        )
        .contentShape(Rectangle()) // clickable anywhere
        .onHover { hovering in
            isHovered = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed { isPressed = true }
                }
                .onEnded { _ in
                    isPressed = false
                    onCopy()
                }
        )
    }
}
