//
//  OSDSettingsViewModel.swift
//  boringNotch
//
//  Created by Alexander on 2026-02-07.
//

import Foundation
import Combine
import SwiftUI
import Defaults

final class OSDSettingsViewModel: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []

    // Defaults-backed storage (read-only here; Published mirrors used for bindings)
    @Default(.osdReplacement) private var osdReplacementDefault
    @Default(.inlineOSD) private var inlineOSDDefault
    @Default(.enableGradient) private var enableGradientDefault
    @Default(.systemEventIndicatorShadow) private var systemEventIndicatorShadowDefault
    @Default(.systemEventIndicatorUseAccent) private var systemEventIndicatorUseAccentDefault
    @Default(.showOpenNotchOSD) private var showOpenNotchOSDDefault
    @Default(.showOpenNotchOSDPercentage) private var showOpenNotchOSDPercentageDefault
    @Default(.showClosedNotchOSDPercentage) private var showClosedNotchOSDPercentageDefault
    @Default(.optionKeyAction) private var optionKeyActionDefault
    @Default(.osdBrightnessSource) private var osdBrightnessSourceDefault
    @Default(.osdVolumeSource) private var osdVolumeSourceDefault
    @Default(.osdKeyboardSource) private var osdKeyboardSourceDefault

    // Published properties for UI binding
    @Published var osdReplacement: Bool = Defaults[.osdReplacement]
    @Published var inlineOSD: Bool = Defaults[.inlineOSD]
    @Published var enableGradient: Bool = Defaults[.enableGradient]
    @Published var systemEventIndicatorShadow: Bool = Defaults[.systemEventIndicatorShadow]
    @Published var systemEventIndicatorUseAccent: Bool = Defaults[.systemEventIndicatorUseAccent]
    @Published var showOpenNotchOSD: Bool = Defaults[.showOpenNotchOSD]
    @Published var showOpenNotchOSDPercentage: Bool = Defaults[.showOpenNotchOSDPercentage]
    @Published var showClosedNotchOSDPercentage: Bool = Defaults[.showClosedNotchOSDPercentage]
    @Published var optionKeyAction: OptionKeyAction = Defaults[.optionKeyAction]
    @Published var osdBrightnessSource: OSDControlSource = Defaults[.osdBrightnessSource]
    @Published var osdVolumeSource: OSDControlSource = Defaults[.osdVolumeSource]
    @Published var osdKeyboardSource: OSDControlSource = Defaults[.osdKeyboardSource]

    // External provider availability
    @Published var isBetterDisplayAvailable: Bool = false
    @Published var isLunarAvailable: Bool = false

    init() {
        // Sync Published -> Defaults
        $osdReplacement
            .removeDuplicates()
            .sink { Defaults[.osdReplacement] = $0 }
            .store(in: &cancellables)

        $inlineOSD
            .removeDuplicates()
            .sink { Defaults[.inlineOSD] = $0 }
            .store(in: &cancellables)

        $enableGradient
            .removeDuplicates()
            .sink { Defaults[.enableGradient] = $0 }
            .store(in: &cancellables)

        $systemEventIndicatorShadow
            .removeDuplicates()
            .sink { Defaults[.systemEventIndicatorShadow] = $0 }
            .store(in: &cancellables)

        $systemEventIndicatorUseAccent
            .removeDuplicates()
            .sink { Defaults[.systemEventIndicatorUseAccent] = $0 }
            .store(in: &cancellables)

        $showOpenNotchOSD
            .removeDuplicates()
            .sink { Defaults[.showOpenNotchOSD] = $0 }
            .store(in: &cancellables)

        $showOpenNotchOSDPercentage
            .removeDuplicates()
            .sink { Defaults[.showOpenNotchOSDPercentage] = $0 }
            .store(in: &cancellables)

        $showClosedNotchOSDPercentage
            .removeDuplicates()
            .sink { Defaults[.showClosedNotchOSDPercentage] = $0 }
            .store(in: &cancellables)

        $optionKeyAction
            .removeDuplicates()
            .sink { Defaults[.optionKeyAction] = $0 }
            .store(in: &cancellables)

        $osdBrightnessSource
            .removeDuplicates()
            .sink { Defaults[.osdBrightnessSource] = $0 }
            .store(in: &cancellables)

        $osdVolumeSource
            .removeDuplicates()
            .sink { Defaults[.osdVolumeSource] = $0 }
            .store(in: &cancellables)

        $osdKeyboardSource
            .removeDuplicates()
            .sink { Defaults[.osdKeyboardSource] = $0 }
            .store(in: &cancellables)

        // Observe provider availability from managers
        if let bd = Optional(BetterDisplayManager.shared) {
            bd.$isBetterDisplayAvailable
                .receive(on: DispatchQueue.main)
                .assign(to: \.isBetterDisplayAvailable, on: self)
                .store(in: &cancellables)
        }

        if let lm = Optional(LunarManager.shared) {
            lm.$isLunarAvailable
                .receive(on: DispatchQueue.main)
                .assign(to: \.isLunarAvailable, on: self)
                .store(in: &cancellables)
        }
    }

    func openPreview() {
        NotificationCenter.default.post(name: Notification.Name("OSDPreviewRequested"), object: nil)
    }
}
