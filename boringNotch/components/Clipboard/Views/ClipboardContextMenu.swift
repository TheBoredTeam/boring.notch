import SwiftUI

struct ClipboardContextMenu: View {
    let item: ClipboardItem
    let onPin: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button {
            onPin()
        } label: {
            Label(item.isPinned ? "Unpin" : "Pin", systemImage: "pin")
        }
        
        Divider()
        
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
