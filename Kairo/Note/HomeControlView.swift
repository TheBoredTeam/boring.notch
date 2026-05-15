import SwiftUI

/// Smart home control surface. Scenes (instant actions) on top, controllable
/// devices below. Layout reflows on width changes; spacing follows the
/// 4pt grid from the design system.
struct HomeControlView: View {

    // Sample data — replace with real HomeKit/HASS state in a later phase.
    private let scenes: [SceneItem] = [
        .init(label: "Studio", icon: "music.mic"),
        .init(label: "Focus",  icon: "brain.head.profile"),
        .init(label: "Night",  icon: "moon.stars.fill")
    ]

    private let lights: [LightItem] = [
        .init(name: "Living Room", value: "78%", icon: "lightbulb.fill", on: true),
        .init(name: "Studio",      value: "Off",  icon: "lightbulb",      on: false),
        .init(name: "Bedroom",     value: "40%",  icon: "lightbulb.fill", on: true),
        .init(name: "Kitchen",     value: "Off",  icon: "lightbulb",      on: false)
    ]

    private let columns = [
        GridItem(.flexible(), spacing: Kairo.Space.sm),
        GridItem(.flexible(), spacing: Kairo.Space.sm)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kairo.Space.xl) {
                section(title: "Scenes") {
                    HStack(spacing: Kairo.Space.sm) {
                        ForEach(scenes) { scene in
                            SceneButton(label: scene.label, icon: scene.icon)
                        }
                    }
                }

                section(title: "Lights") {
                    LazyVGrid(columns: columns, spacing: Kairo.Space.sm) {
                        ForEach(lights) { light in
                            DeviceCard(
                                name: light.name,
                                value: light.value,
                                icon: light.icon,
                                on: light.on
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, Kairo.Space.lg)
            .padding(.vertical, Kairo.Space.md)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Kairo.Space.md) {
            Text(title.uppercased())
                .font(Kairo.Typography.captionStrong)
                .tracking(1.2)
                .foregroundStyle(Kairo.Palette.textDim)
            content()
        }
    }
}

// MARK: - Sample data types

private struct SceneItem: Identifiable {
    let label: String
    let icon: String
    var id: String { label }
}

private struct LightItem: Identifiable {
    let name: String
    let value: String
    let icon: String
    let on: Bool
    var id: String { name }
}
