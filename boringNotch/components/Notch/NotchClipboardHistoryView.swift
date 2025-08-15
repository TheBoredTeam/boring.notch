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
                            HStack(spacing: 12) {
                                
                                // Preview
                                preview(for: item)
                                    .onTapGesture {
                                        copyToClipboard(item)
                                        viewModel.setActiveItem(item)
                                    }
                                
                                Spacer()
                                
                                // Delete button
                                Button {
                                    viewModel.delete(item)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(item.id == viewModel.activeItemID ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Preview renderer for text or image
    @ViewBuilder
    private func preview(for item: ClipboardItem) -> some View {
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
    }
    
    // Copy back to system clipboard
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
