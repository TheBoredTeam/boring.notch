//
//  LoftExtrasMenu.swift
//  Zenith Loft (LoftOS)
//
//  Clean-room replacement for BoringExtrasMenu.swift.
//  - No BoringViewModel
//  - No external assets/URLs required
//  - Inject actions for Hide / Settings / Exit
//

import SwiftUI
import AppKit

// MARK: - Building block button

struct LoftLargeButton: View {
    var action: () -> Void
    var systemIconName: String
    var title: String

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .frame(width: 70, height: 70)
                VStack(spacing: 8) {
                    Image(systemName: systemIconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.white)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.5), radius: 10)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Extras tray

struct LoftExtrasMenu: View {
    /// Inject behaviors from your HUD or app controller.
    var onHide: () -> Void = {}
    var onOpenSettings: () -> Void = {
        // If you have a controller, call it here instead:
        // SettingsWindowController.shared.showWindow()
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    var onExit: () -> Void = { NSApp.terminate(nil) }

    var body: some View {
        VStack {
            HStack(spacing: 20) {
                hide
                settings
                close
            }
        }
    }

    private var hide: some View {
        LoftLargeButton(
            action: {
                // small delay to feel less “instant” in the notch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onHide()
                }
            },
            systemIconName: "arrow.down.forward.and.arrow.up.backward",
            title: "Hide"
        )
    }

    private var settings: some View {
        LoftLargeButton(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onOpenSettings()
                }
            },
            systemIconName: "gear",
            title: "Settings"
        )
    }

    private var close: some View {
        LoftLargeButton(
            action: {
                // double-delay mirrors your original behavior
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onExit()
                    }
                }
            },
            systemIconName: "xmark",
            title: "Exit"
        )
    }
}

// MARK: - Optional: compatibility during migration
// If you still have `BoringExtrasMenu(vm:)` call sites, either change them to
// `LoftExtrasMenu(onHide:onOpenSettings:onExit:)` or uncomment the typealias below.
//
// typealias BoringExtrasMenu = LoftExtrasMenu

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        LoftExtrasMenu(
            onHide: { print("Hide tapped") },
            onOpenSettings: { print("Settings tapped") },
            onExit: { print("Exit tapped") }
        )
    }
    .frame(width: 260, height: 120)
}
