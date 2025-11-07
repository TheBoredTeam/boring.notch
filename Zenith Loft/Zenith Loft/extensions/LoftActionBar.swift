import SwiftUI

extension View {
    func loftActionBar<Content: View>(padding: CGFloat = 10, @ViewBuilder content: () -> Content) -> some View {
        self
            .padding(.bottom, 24)
            .overlay(alignment: .bottom) {
                VStack(spacing: -1) {
                    Divider()
                    HStack(spacing: 0) {
                        content()
                            .buttonStyle(PlainButtonStyle())
                    }
                    .frame(height: 16)
                    .padding(.vertical, 4)
                    .padding(.horizontal, padding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 24)
                .background(.separator)
            }
    }
}
