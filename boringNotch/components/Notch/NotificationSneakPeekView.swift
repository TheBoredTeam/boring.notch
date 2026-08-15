//
//  NotificationSneakPeekView.swift
//  boringNotch
//
//  Passive marquee mirror of an incoming notification — shown below the
//  closed notch for a few seconds, then gone. Purely visual: it never holds
//  banners, never touches keyboard focus, never opens UI.
//

import SwiftUI

struct NotificationSneakPeekView: View {
    let payload: NotificationPeekPayload

    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 6) {
            if let bundleID = payload.bundleID,
               let icon = appIconAsNSImage(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }

            if let title = payload.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            GeometryReader { geo in
                MarqueeText(
                    bodyText,
                    font: .caption,
                    color: .gray,
                    delayDuration: 0.8,
                    frameWidth: geo.size.width
                )
            }
        }
        .frame(width: 320)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            // macOS-banner semantics: tapping the mirror opens the content —
            // the expanded notification panel inside the notch. The arrival
            // already registered the notification as the active live
            // activity, so opening the notch surfaces it directly.
            _ = vm.open()
        }
    }

    private var bodyText: String {
        var parts: [String] = []
        if payload.title == nil, let appName = payload.appName, !appName.isEmpty {
            parts.append(appName)
        }
        if let body = payload.body, !body.isEmpty {
            parts.append(body)
        }
        // Nothing but a title? Marquee the app name so the pill isn't empty.
        if parts.isEmpty, let appName = payload.appName { parts.append(appName) }
        return parts.joined(separator: " — ")
    }
}
