import SwiftUI

struct NotificationData: Hashable {
    let app: String
    let title: String
    let body: String
    let icon: String
    let timestamp: String
}

struct NotificationView: View {
    let data: NotificationData

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(data.icon).font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(data.app.uppercased()).font(.system(size: 10, weight: .semibold))
                        .tracking(1.0).foregroundColor(Kairo.Palette.textDim)
                    Spacer()
                    Text(data.timestamp).font(.system(size: 10))
                        .foregroundColor(Kairo.Palette.textFaint)
                }
                Text(data.title).font(.system(size: 14, weight: .semibold))
                Text(data.body).font(.system(size: 12))
                    .foregroundColor(Kairo.Palette.textDim).lineLimit(3)
            }
            Spacer()
        }
        .padding(20)
        .foregroundColor(Kairo.Palette.text)
    }
}
