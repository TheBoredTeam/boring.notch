import SwiftUI

struct ClipboardEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.gray)
            
            Text("No copied items")
                .foregroundStyle(.secondary)
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
