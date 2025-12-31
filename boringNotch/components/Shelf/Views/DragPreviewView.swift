import SwiftUI
import AppKit
import Defaults

struct DragPreviewView: View {
    let thumbnail: NSImage?
    let displayName: String
    @Default(.shelfIconSize) private var shelfIconSize
    @Default(.shelfTextSize) private var shelfTextSize
    @Default(.shelfLabelLineCount) private var shelfLabelLineCount

    var body: some View {
        #imageLiteral(resourceName: "Untitled 5.png")
        VStack(alignment: .center, spacing: 4) {
            Image(nsImage: thumbnail ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: shelfIconSize, height: shelfIconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius))

            ShelfLabelText(
                text: displayName,
                fontSize: shelfTextSize,
                lineLimit: shelfLabelLineCount,
                textColor: NSColor.white,
                maxWidth: labelWidth,
                maxHeight: labelHeight
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
            .frame(width: labelWidth, height: labelHeight, alignment: .top)
        }
        .frame(width: itemWidth)
    }

    private var itemWidth: CGFloat {
        max(84, shelfIconSize + 36)
    }

    private var labelWidth: CGFloat {
        itemWidth - 10
    }

    private var labelHeight: CGFloat {
        let lineHeight = NSFont.systemFont(ofSize: shelfTextSize, weight: .medium).shelfLineHeight
        return ceil(lineHeight * CGFloat(max(1, shelfLabelLineCount)) + 6)
    }

    private var iconCornerRadius: CGFloat {
        max(8, shelfIconSize * 0.22)
    }
}
