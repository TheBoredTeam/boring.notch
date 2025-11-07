import Foundation
import SwiftUI
import Defaults

struct LoftSystemItemButton: View {
    @EnvironmentObject var vm: LoftViewModel
    @State var icon: String = "gear"
    var onTap: () -> Void
    @State var label: String?
    @State var showEmojis: Bool = true
    @State var emoji: String = "🔧"

    var body: some View {
        Button(action: onTap) {
            if Defaults[.tileShowLabels] {
                HStack {
                    if !showEmojis {
                        Image(systemName: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10)
                            .foregroundStyle(.gray)
                    }

                    Text((showEmojis ? "\(emoji) " : "") + (label ?? ""))
                        .font(.caption2)
                        .fontWeight(.regular)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            } else {
                Color.clear
                    .overlay {
                        Image(systemName: icon)
                            .foregroundStyle(.gray)
                    }
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .buttonStyle(LoftBouncingButtonStyle(vm: vm))
    }
}

func loftLogout() {
    DispatchQueue.global(qos: .background).async {
        let appleScript = """
        tell application "System Events" to log out
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                print("Error: \(error)")
            }
        }
    }
}

struct LoftSystemTiles: View {
    @EnvironmentObject var vm: LoftViewModel
    @ObservedObject var coordinator = LoftViewCoordinator.shared

    struct ItemButton {
        var icon: String
        var onTap: () -> Void
    }

    var body: some View {
        Grid {
            GridRow {
                // Example placeholder row for future items
                // LoftSystemItemButton(icon: "clipboard", onTap: { vm.openClipboard() }, label: "Clipboard History", showEmojis: Defaults[.showEmojis], emoji: "✨")
            }
            GridRow {
                LoftSystemItemButton(
                    icon: coordinator.currentMicStatus ? "mic" : "mic.slash",
                    onTap: {
                        coordinator.toggleMic()
                        vm.close()
                    },
                    label: "Toggle Microphone",
                    showEmojis: Defaults[.showEmojis],
                    emoji: coordinator.currentMicStatus ? "😀" : "🤫"
                )
                // LoftSystemItemButton(icon: "lock", onTap: { loftLogout() }, label: "Lock My Device", showEmojis: true, emoji: "🔒")
            }
        }
    }
}

#Preview {
    LoftSystemTiles()
        .padding()
        .environmentObject(LoftViewModel())
}
