//
//  PrivacyActivity.swift
//  boringNotch
//

import SwiftUI

/// Microphone or camera use starting or stopping, in the closed notch.
///
/// Follows the same geometry as the other closed-notch activities: content on either side
/// of a black spacer the width of the physical notch.
struct PrivacyActivity: View {
    @EnvironmentObject var vm: BoringViewModel

    let announcement: PrivacyActivityManager.Announcement
    let notchHeight: CGFloat

    private var symbol: String {
        switch announcement.resource {
        case .microphone: return announcement.isStarting ? "mic.fill" : "mic.slash.fill"
        case .camera: return announcement.isStarting ? "video.fill" : "video.slash.fill"
        }
    }

    /// Green while in use, matching the colour macOS itself uses for the camera indicator.
    private var tint: Color {
        announcement.isStarting ? .green : .gray
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .imageScale(.medium)

                Group {
                    switch announcement.resource {
                    case .microphone: Text("Microphone")
                    case .camera: Text("Camera")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
            }
            .frame(width: activitySlotWidth, alignment: .trailing)

            // The spacer only needs to clear a physical notch. On displays without one it
            // is dead space that pushes the two labels to opposite ends of the bar.
            Rectangle()
                .fill(.black)
                .frame(width: vm.hasNotch ? vm.closedNotchSize.width + activityNotchClearance : 16)

            HStack(spacing: 6) {
                if !announcement.isStarting {
                    Text("Stopped")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                } else if let name = announcement.appName {
                    // Runtime data, so verbatim: it must not be picked up as a
                    // localization key. No fixedSize either — the slot has to truncate it.
                    Text(verbatim: name)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    // The camera never has an app name, and a microphone recorder without a
                    // bundle identifier cannot be named either.
                    Text("In use")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(width: activitySlotWidth, alignment: .leading)
        }
        .frame(height: notchHeight, alignment: .center)
    }
}

#Preview {
    VStack(spacing: 4) {
        // Microphone starting, with the responsible app named.
        PrivacyActivity(
            announcement: .init(resource: .microphone, isStarting: true, appName: "zoom.us"),
            notchHeight: 32
        )

        // The camera can never be attributed to an app.
        PrivacyActivity(
            announcement: .init(resource: .camera, isStarting: true, appName: nil),
            notchHeight: 32
        )

        // Stopping.
        PrivacyActivity(
            announcement: .init(resource: .microphone, isStarting: false, appName: nil),
            notchHeight: 32
        )

        // A long app name has to truncate rather than overflow the slot.
        PrivacyActivity(
            announcement: .init(
                resource: .microphone, isStarting: true,
                appName: "Microsoft Teams (work or school)"),
            notchHeight: 32
        )
    }
    .background(Color.black)
    .environmentObject(BoringViewModel())
}
