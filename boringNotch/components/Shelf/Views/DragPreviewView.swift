import SwiftUI
import AppKit

struct DragPreviewView: View {
    let thumbnail: NSImage?
    let displayName: String

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(nsImage: thumbnail ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                .frame(alignment: .top)
        }
        .frame(width: 105)
    }
}
