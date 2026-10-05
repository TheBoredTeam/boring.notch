//
//  HUDComponents.swift
//  boringNotch
//
//  Small shared building blocks for the Developer and GitHub HUDs.
//

import SwiftUI

/// Rounded capsule used for compact status values (branch, status, counts).
struct HUDChip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .gray

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.18)))
    }
}

/// Full-area placeholder for loading / empty / offline / auth states.
struct HUDStateView: View {
    enum Kind { case loading, empty, offline, error, action }

    let kind: Kind
    let title: String
    var message: String? = nil
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    private var icon: String {
        switch kind {
        case .loading: return "hourglass"
        case .empty: return "tray"
        case .offline: return "wifi.slash"
        case .error: return "exclamationmark.triangle"
        case .action: return "lock"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if kind == .loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.gray)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.blurReplace.animation(.smooth(duration: 0.3)))
    }
}

/// Thin horizontal gauge (0...1).
struct HUDGauge: View {
    let label: String
    let value: Double
    var tint: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
                Spacer(minLength: 4)
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(value > 0.85 ? Color.red : (value > 0.6 ? Color.orange : tint))
                        .frame(width: max(3, geo.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 4)
        }
        .animation(.smooth(duration: 0.4), value: value)
    }
}

/// Card container matching the notch's dark, rounded look.
struct HUDCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

extension Date {
    /// "3m ago" style string without allocating a formatter per call site.
    var hudRelative: String {
        Self.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
