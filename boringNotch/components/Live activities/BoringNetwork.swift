import SwiftUI

struct BoringNetworkActivityView: View {
    var statusText: String
    var symbolName: String
    var isConnected: Bool
    var textWidth: CGFloat
    var centerWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(width: textWidth, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: centerWidth)

            HStack {
                Image(systemName: symbolName)
                    .foregroundStyle(isConnected ? .white : .gray)
                    .frame(width: 18, height: 18)
                    .contentTransition(.interpolate)
            }
            .frame(width: 76, alignment: .trailing)
        }
    }
}
