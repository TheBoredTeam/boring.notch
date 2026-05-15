import SwiftUI

struct QuickAnswerData: Hashable {
    let text: String
    let icon: String?
}

struct QuickAnswerView: View {
    let data: QuickAnswerData

    var body: some View {
        HStack(spacing: 12) {
            if let i = data.icon { Text(i).font(.system(size: 28)) }
            Text(data.text).font(.system(size: 14, weight: .medium))
                .lineLimit(2).foregroundColor(Kairo.Palette.text)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}
