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

/// Panel-sized search results list. Header row shows the query +
/// result count; below is a scrollable list of result cards. Click a
/// card to open the URL in the user's default browser.
struct SearchResultsView: View {
    let data: SearchResultsData

    var body: some View {
        VStack(alignment: .leading, spacing: Kairo.Space.lg) {
            header
            ScrollView {
                LazyVStack(spacing: Kairo.Space.sm) {
                    ForEach(Array(data.results.enumerated()), id: \.offset) { _, r in
                        ResultCard(result: r)
                    }
                }
                .padding(.horizontal, Kairo.Space.lg)
                .padding(.bottom, Kairo.Space.lg)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack(spacing: Kairo.Space.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Kairo.Palette.textDim)
            Text(data.query)
                .font(Kairo.Typography.titleSmall)
                .foregroundStyle(Kairo.Palette.text)
            Spacer()
            Text("\(data.results.count) results")
                .font(Kairo.Typography.bodySmall)
                .foregroundStyle(Kairo.Palette.textDim)
        }
        .padding(.horizontal, Kairo.Space.xl)
        .padding(.top, Kairo.Space.xl)
    }
}

// MARK: - Result card

private struct ResultCard: View {
    let result: SearchResultsData.Result
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: Kairo.Space.md) {
            AsyncImage(url: result.imageURL) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Kairo.Palette.surfaceHi
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(Kairo.Palette.textFaint)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: Kairo.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: Kairo.Space.xxs) {
                Text(result.title)
                    .font(Kairo.Typography.bodyEmphasis)
                    .foregroundStyle(Kairo.Palette.text)
                    .lineLimit(1)
                Text(result.subtitle)
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Kairo.Palette.textDim)
                    .lineLimit(1)
                Text(result.snippet)
                    .font(Kairo.Typography.bodySmall)
                    .foregroundStyle(Kairo.Palette.textDim)
                    .lineLimit(2)
                if let rating = result.rating {
                    HStack(spacing: Kairo.Space.xxs) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Kairo.Palette.accent)
                        Text(String(format: "%.1f", rating))
                            .font(Kairo.Typography.captionStrong)
                            .foregroundStyle(Kairo.Palette.text)
                    }
                    .padding(.top, Kairo.Space.xxs)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Kairo.Space.md)
        .background {
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                        .fill(Kairo.Palette.glassTint.opacity(hover ? 1.6 : 1.0))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Kairo.Radius.md, style: .continuous)
                .strokeBorder(
                    hover ? Kairo.Palette.accent.opacity(0.35) : Kairo.Palette.glassStroke,
                    lineWidth: 0.5
                )
        }
        .kairoElevation(hover ? Kairo.Elevation.hover : Kairo.Elevation.flat)
        .onHover { hovering in
            withAnimation(Kairo.Motion.hover) { hover = hovering }
        }
        .onTapGesture { NSWorkspace.shared.open(result.url) }
    }
}
