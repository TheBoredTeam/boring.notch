//
//  StackedDragPreviewView.swift
//  boringNotch
//
//  Created for Issue #890 - File Stacking / Group Dragging Feature
//

import SwiftUI
import AppKit

struct StackedDragPreviewView: View {
    let thumbnails: [NSImage]
    let count: Int

    private let cardWidth: CGFloat = 56
    private let cardHeight: CGFloat = 56
    private let stackOffset: CGFloat = 3
    private let maxStackLayers: Int = 3

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            // Stacked cards with count badge
            ZStack(alignment: .topTrailing) {
                // Stack layers (up to 3)
                ForEach(0..<min(maxStackLayers, thumbnails.count), id: \.self) { index in
                    let reverseIndex = min(maxStackLayers, thumbnails.count) - 1 - index

                    Image(nsImage: thumbnails[min(reverseIndex, thumbnails.count - 1)])
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(opacityForLayer(reverseIndex))
                        .offset(
                            x: CGFloat(reverseIndex) * stackOffset,
                            y: CGFloat(reverseIndex) * stackOffset
                        )
                }

                // Count badge
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                        .offset(x: 8, y: -8)
                }
            }
            .frame(
                width: cardWidth + CGFloat(min(maxStackLayers - 1, 2)) * stackOffset,
                height: cardHeight + CGFloat(min(maxStackLayers - 1, 2)) * stackOffset
            )

            // Label showing item count
            Text(count == 1 ? "1 item" : "\(count) items")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                .frame(alignment: .top)
        }
        .frame(width: 105)
    }

    private func opacityForLayer(_ layer: Int) -> Double {
        switch layer {
        case 0: return 1.0
        case 1: return 0.85
        case 2: return 0.7
        default: return 0.6
        }
    }
}

// Preview for development
#Preview {
    VStack(spacing: 20) {
        StackedDragPreviewView(
            thumbnails: [
                NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)!,
                NSImage(systemSymbolName: "photo.fill", accessibilityDescription: nil)!,
                NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)!
            ],
            count: 3
        )

        StackedDragPreviewView(
            thumbnails: [
                NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)!
            ],
            count: 5
        )
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
