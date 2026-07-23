import AppKit
import SwiftUI

struct ClosedNotchBatteryRenderData {
    let statusTextKey: String
    let level: Float
    let isCharging: Bool
    let isInLowPowerMode: Bool
    let isPluggedIn: Bool
    let maxAdapterWatts: Int

    var leadingWidth: CGFloat {
        let localizedStatus = NSLocalizedString(statusTextKey, comment: "")
        let font = NSFont.preferredFont(forTextStyle: .subheadline)
        return ceil((localizedStatus as NSString).size(withAttributes: [.font: font]).width)
    }
}

struct ClosedNotchRenderData {
    let music: ClosedNotchMusicRenderData
    let battery: ClosedNotchBatteryRenderData
    let osd: Binding<sneakPeek>
}

struct ClosedNotchRenderSnapshot {
    let presentation: ClosedNotchPresentationState
    let renderData: ClosedNotchRenderData
    let displayHeight: CGFloat
    let cornerRadiusScaleFactor: CGFloat?
    let albumArtWidth: CGFloat
    let spectrumWidth: CGFloat

    init(
        presentationInput: ClosedNotchPresentationInput,
        renderData: ClosedNotchRenderData,
        displayHeight: CGFloat,
        cornerRadiusScaleFactor: CGFloat?,
        albumArtWidth: CGFloat,
        spectrumWidth: CGFloat
    ) {
        presentation = ClosedNotchPresentationResolver.resolve(presentationInput)
        self.renderData = renderData
        self.displayHeight = displayHeight
        self.cornerRadiusScaleFactor = cornerRadiusScaleFactor
        self.albumArtWidth = albumArtWidth
        self.spectrumWidth = spectrumWidth
    }
}
