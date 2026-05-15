import SwiftUI

struct SearchResultsData: Hashable {
    let query: String
    let results: [Result]

    struct Result: Hashable {
        let title: String
        let subtitle: String
        let snippet: String
        let imageURL: URL?
        let rating: Double?
        let url: URL
    }
}

struct SearchResultsView: View {
    let data: SearchResultsData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Kairo.Palette.textDim)
                Text(data.query).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(data.results.count) results")
                    .font(.system(size: 12)).foregroundColor(Kairo.Palette.textDim)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(data.results.enumerated()), id: \.offset) { _, r in
                        ResultCard(result: r)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .foregroundColor(Kairo.Palette.text)
    }
}

private struct ResultCard: View {
    let result: SearchResultsData.Result
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AsyncImage(url: result.imageURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Kairo.Palette.surfaceHi }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(result.subtitle).font(.system(size: 12))
                    .foregroundColor(Kairo.Palette.textDim).lineLimit(1)
                Text(result.snippet).font(.system(size: 12))
                    .foregroundColor(Kairo.Palette.textDim).lineLimit(2)
                if let rating = result.rating {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill").font(.system(size: 10))
                            .foregroundColor(Kairo.Palette.accent)
                        Text(String(format: "%.1f", rating)).font(.system(size: 11, weight: .medium))
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(hover ? Kairo.Palette.surfaceHi : Kairo.Palette.surface)
        )
        .onHover { hover = $0 }
        .onTapGesture { NSWorkspace.shared.open(result.url) }
    }
}
