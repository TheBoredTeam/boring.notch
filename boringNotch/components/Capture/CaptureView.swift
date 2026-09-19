//
//  CaptureView.swift
//  boringNotch
//
//  The Capture tab: a grid of action tiles, split into capture on the left and
//  "read something off the screen" on the right, with the save destination
//  under the capture group.
//

import Defaults
import SwiftUI

/// Palette for the capture surface, kept in one place so the tiles and the
/// status line can't drift apart.
enum CapturePalette {
    static let tile = Color.white.opacity(0.05)
    static let tileHover = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.07)
    static let group = Color.white.opacity(0.03)
    static let label = Color.white.opacity(0.5)
    static let recording = Color(red: 0.922, green: 0.290, blue: 0.259)
}

struct CaptureView: View {
    @ObservedObject private var coordinator = CaptureCoordinator.shared
    @ObservedObject private var recorder = GIFRecorder.shared
    @Default(.captureDestination) private var destination

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    private let readColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .top, spacing: 8) {
                captureGroup
                readGroup.frame(width: 168)
            }
            statusLine
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Capture group

    private var captureGroup: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(CaptureKind.allCases) { kind in
                    CaptureTile(title: kind.localizedTitle, systemImage: kind.systemImage) {
                        coordinator.takeScreenshot(kind)
                    }
                }

                CaptureTile(
                    title: NSLocalizedString("capture_pin", comment: "Capture tile: pin a capture on top"),
                    systemImage: "pin"
                ) {
                    coordinator.pinLastOrCapture()
                }

                CaptureTile(
                    title: NSLocalizedString("capture_measure", comment: "Capture tile: measure a region"),
                    systemImage: "ruler"
                ) {
                    coordinator.measure()
                }

                CaptureTile(
                    title: recorder.isRecording
                        ? NSLocalizedString("capture_gif_stop", comment: "Capture tile while recording: stop")
                        : NSLocalizedString("capture_gif", comment: "Capture tile: record a GIF"),
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle",
                    tint: recorder.isRecording ? CapturePalette.recording : nil,
                    // The frame count is the only feedback that a recording is
                    // actually running, since the overlay is gone by then.
                    badge: recorder.isRecording ? "\(recorder.frameCount)" : nil
                ) {
                    coordinator.toggleGIFRecording()
                }
            }

            destinationPicker
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CapturePalette.group))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CapturePalette.border, lineWidth: 1))
    }

    private var destinationPicker: some View {
        HStack(spacing: 5) {
            Text(NSLocalizedString("capture_save_to", comment: "Label before the capture destination picker"))
                .font(.system(size: 9))
                .foregroundStyle(CapturePalette.label)

            Picker("", selection: $destination) {
                ForEach(CaptureDestination.allCases) { option in
                    Label(option.localizedTitle, systemImage: option.systemImage).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.mini)
            .fixedSize()
            .accessibilityLabel(Text(NSLocalizedString("capture_save_to", comment: "Label before the capture destination picker")))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Read group

    private var readGroup: some View {
        LazyVGrid(columns: readColumns, spacing: 6) {
            CaptureTile(
                title: NSLocalizedString("capture_get_text", comment: "Capture tile: OCR text from the screen"),
                systemImage: "text.viewfinder"
            ) {
                coordinator.captureText()
            }

            CaptureTile(
                title: NSLocalizedString("capture_scan_code", comment: "Capture tile: read a QR code"),
                systemImage: "qrcode.viewfinder"
            ) {
                coordinator.scanCode()
            }

            CaptureTile(
                title: NSLocalizedString("capture_pick_color", comment: "Capture tile: sample a colour"),
                systemImage: "eyedropper",
                swatch: coordinator.lastColor
            ) {
                coordinator.pickColor()
            }

            CaptureTile(
                title: NSLocalizedString("capture_settings", comment: "Capture tile: open capture settings"),
                systemImage: "slider.horizontal.3"
            ) {
                SettingsWindowController.shared.showWindow()
            }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CapturePalette.group))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CapturePalette.border, lineWidth: 1))
    }

    // MARK: - Status

    @ViewBuilder
    private var statusLine: some View {
        // Reserve the row's height always, so the whole grid doesn't shift up
        // and down as messages come and go.
        Group {
            switch coordinator.status {
            case .idle:
                if !coordinator.hasScreenRecordingPermission {
                    label(
                        NSLocalizedString(
                            "capture_permission_hint",
                            comment: "Hint shown when Screen Recording has not been granted"
                        ),
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                } else {
                    Color.clear
                }
            case .working:
                label(
                    NSLocalizedString("capture_status_working", comment: "Status while a capture is in progress"),
                    systemImage: "hourglass",
                    color: CapturePalette.label
                )
            case .success(let message):
                label(message, systemImage: "checkmark.circle.fill", color: .green)
            case .failure(let message):
                label(message, systemImage: "exclamationmark.circle.fill", color: .orange)
            }
        }
        .frame(height: 13)
        .animation(.easeOut(duration: 0.2), value: coordinator.status)
    }

    private func label(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 8))
            Text(text).font(.system(size: 9)).lineLimit(1).truncationMode(.tail)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
    }
}

/// One action tile: glyph over a label, hover highlight, whole tile is the
/// button.
struct CaptureTile: View {
    let title: String
    let systemImage: String
    var tint: Color?
    var badge: String?
    var swatch: SampledColor?
    let action: () -> Void

    @State private var isHovering = false

    init(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        badge: String? = nil,
        swatch: SampledColor? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.badge = badge
        self.swatch = swatch
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(tint ?? .white.opacity(isHovering ? 1 : 0.85))
                        .frame(height: 18)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(CapturePalette.recording))
                            .offset(x: 12, y: -4)
                    }
                }

                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering ? CapturePalette.tileHover : CapturePalette.tile)
            )
            .overlay(alignment: .bottomTrailing) {
                // The eyedropper carries the last sampled colour, so the tile
                // doubles as a record of what is on the clipboard.
                if let swatch {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue))
                        .frame(width: 8, height: 8)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.35), lineWidth: 0.5))
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(title)
        .accessibilityLabel(Text(title))
    }
}
