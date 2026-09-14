//
//  LockScreenSettingsView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct LockScreenSettings: View {
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.keepAwakeMode) var keepAwakeMode
    @Default(.playSoundOnLock) var playSoundOnLock
    @Default(.playSoundOnUnlock) var playSoundOnUnlock
    @Default(.lockSoundName) var lockSoundName
    @Default(.unlockSoundName) var unlockSoundName

    /// System sounds that ship with macOS, so there is nothing to bundle.
    private let soundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
        "Hero", "Morse", "Ping", "Pop", "Purr", "Submarine", "Tink",
    ]

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show on lock screen")
                }
                Defaults.Toggle(key: .showOnScreenSaver) {
                    Text("Show on screen saver")
                }
            } header: {
                Text("Visibility")
            } footer: {
                HelpText("Activities are hidden while the Mac is locked, unless you turn on “Show on lock screen”.")
            }

            Section {
                HStack {
                    Text("Keep awake")
                    Spacer()
                    Picker("", selection: $keepAwakeMode) {
                        ForEach(KeepAwakeMode.allCases) { mode in
                            Text(mode.localizedString).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HelpText("Prevents the display from sleeping. Timed options switch themselves off when they expire, and the assertion is always released when Boring Notch quits.")
            } header: {
                Text("Keep Awake")
            }

            Section {
                Defaults.Toggle(key: .playSoundOnLock) {
                    Text("Play sound on lock")
                }
                Picker("Lock sound", selection: $lockSoundName) {
                    ForEach(soundNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(!playSoundOnLock)

                Defaults.Toggle(key: .playSoundOnUnlock) {
                    Text("Play sound on unlock")
                }
                Picker("Unlock sound", selection: $unlockSoundName) {
                    ForEach(soundNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(!playSoundOnUnlock)

                Button("Preview") {
                    NSSound(named: NSSound.Name(lockSoundName))?.play()
                }
            } header: {
                Text("Sounds")
            } footer: {
                HelpText("macOS does not allow apps to replace or restyle the real lock screen, or to detect how you unlocked. These options act around the lock event instead.")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Lock Screen")
    }
}

#Preview {
    LockScreenSettings().frame(width: 500, height: 600)
}
