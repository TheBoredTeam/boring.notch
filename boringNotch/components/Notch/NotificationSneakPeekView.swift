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
        VStack(alignment: .leading, spacing: 2) {
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
                }

                if let appName = payload.appName, !appName.isEmpty, payload.title == nil {
                    Text(appName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            // Message goes UNDER the name, single line, stripped — long
            // messages are silently truncated rather than scrolled, exactly
            // like a macOS banner.
            if let message = strippedMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // The pill floats over the wallpaper now — it needs its own backdrop
        // or the title melts into whatever's below (white/gray text on a
        // light background, gray-on-black over the notch shape).
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Cap: single stripped line, so anything longer than ~380 truncates.
        .frame(maxWidth: 380)
        .contentShape(Rectangle())
        .onTapGesture {
            // macOS-banner semantics: tapping the mirror opens the content —
            // the expanded notification panel inside the notch. The arrival
            // already registered the notification as the active live
            // activity, so opening the notch surfaces it directly.
            _ = vm.open()
        }
    }

    /// Flattened display message stripped to the essential body.
    private var strippedMessage: String? {
        guard let body = payload.body else { return nil }
        let cleaned = body
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
