import SwiftUI

struct HomeControlView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeader("SCENES")
                HStack(spacing: 10) {
                    SceneButton(label: "Studio", icon: "music.mic")
                    SceneButton(label: "Focus",  icon: "brain.head.profile")
                    SceneButton(label: "Night",  icon: "moon.stars.fill")
                }
                sectionHeader("LIGHTS")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DeviceCard(name: "Living Room", value: "78%", icon: "lightbulb.fill", on: true)
                    DeviceCard(name: "Studio",      value: "Off",  icon: "lightbulb",      on: false)
                    DeviceCard(name: "Bedroom",     value: "40%",  icon: "lightbulb.fill", on: true)
                    DeviceCard(name: "Kitchen",     value: "Off",  icon: "lightbulb",      on: false)
                }
            }
            .padding(16)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.2)
            .foregroundColor(Kairo.Palette.textDim)
    }
}
