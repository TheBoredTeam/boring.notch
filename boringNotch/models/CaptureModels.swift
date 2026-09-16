//
//  CaptureModels.swift
//  boringNotch
//
//  Value types and pure helpers for screen capture and OCR.
//
//  The bits with real decisions in them — where a capture goes, what it is
//  named, how Vision's line fragments are reassembled into text a person can
//  paste — live here, free of ScreenCaptureKit, Vision and AppKit, so they
//  can be tested without a screen recording permission or a running display.
//

import CoreGraphics
import Foundation

// MARK: - What to capture

enum CaptureKind: String, CaseIterable, Identifiable, Sendable {
    /// A rubber-band selection the user drags.
    case area
    /// One whole display.
    case fullscreen
    /// A single window, picked by clicking it.
    case window

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .area: return NSLocalizedString("capture_area", comment: "Capture tile: drag out an area")
        case .fullscreen: return NSLocalizedString("capture_fullscreen", comment: "Capture tile: whole screen")
        case .window: return NSLocalizedString("capture_window", comment: "Capture tile: one window")
        }
    }

    var systemImage: String {
        switch self {
        case .area: return "crop"
        case .fullscreen: return "macwindow.on.rectangle"
        case .window: return "macwindow"
        }
    }
}

// MARK: - Where it goes

/// Where a finished capture is delivered.
///
/// The shelf is the default because it is the one destination that needs no
/// extra permission: a sandboxed app can always write into its own container,
/// and the shelf already knows how to hold, preview, drag out and share a
/// file. Saving elsewhere goes through a save panel, which is what grants
/// access to the chosen folder.
enum CaptureDestination: String, CaseIterable, Identifiable, Sendable {
    case shelf
    case clipboard
    case file

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .shelf: return NSLocalizedString("capture_destination_shelf", comment: "Capture destination: the notch shelf")
        case .clipboard: return NSLocalizedString("capture_destination_clipboard", comment: "Capture destination: the clipboard")
        case .file: return NSLocalizedString("capture_destination_file", comment: "Capture destination: save to a file")
        }
    }

    var systemImage: String {
        switch self {
        case .shelf: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .file: return "folder"
        }
    }
}

// MARK: - Naming

enum CaptureNaming {
    /// Matches the shape macOS uses for its own screenshots
    /// ("Screenshot 2026-09-16 at 14.32.05"), so captures sort sensibly
    /// beside them and never collide within a second.
    ///
    /// Colons are not used in the time even though APFS allows them: they
    /// still display as "/" in Finder, which reads as a path separator.
    static func filename(for date: Date, kind: CaptureKind, fileExtension: String, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // Fixed locale: a filename is not UI text, and a locale-dependent
        // one sorts differently per user and can contain characters the
        // filesystem displays oddly.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

        let stem = String(
            format: NSLocalizedString("capture_filename", comment: "Screenshot filename, e.g. 'Screenshot 2026-09-16 at 14.32.05'"),
            formatter.string(from: date)
        )
        return "\(sanitized(stem)).\(fileExtension)"
    }

    /// Strips the two characters that are not legal in an HFS/APFS filename
    /// as displayed: "/" is the path separator and ":" renders as one.
    static func sanitized(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Screenshot" : cleaned
    }
}

// MARK: - Selection geometry

/// A rubber-band selection, in the overlay window's own coordinate space.
struct SelectionRect: Equatable, Sendable {
    var origin: CGPoint
    var current: CGPoint

    /// The normalised rectangle, whichever direction the user dragged.
    ///
    /// Dragging up-and-left produces negative width/height, and a CGRect with
    /// a negative size fails `contains`, draws nothing, and captures an empty
    /// image — so every consumer reads this rather than building its own.
    var rect: CGRect {
        CGRect(
            x: min(origin.x, current.x),
            y: min(origin.y, current.y),
            width: abs(current.x - origin.x),
            height: abs(current.y - origin.y)
        )
    }

    /// Drags shorter than this in either axis are treated as a click, not a
    /// selection — a 2x3 pixel screenshot is never what someone meant.
    static let minimumSide: CGFloat = 8

    var isUsable: Bool {
        rect.width >= Self.minimumSide && rect.height >= Self.minimumSide
    }

    /// "1280 × 720" — shown live beside the cursor while dragging.
    var sizeLabel: String {
        "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
    }
}

/// Converts a selection made in a screen's coordinate space into the
/// bottom-left-origin CGRect that ScreenCaptureKit expects, relative to that
/// display.
///
/// Worth isolating: AppKit windows are bottom-left origin and global, while a
/// content filter's `sourceRect` is relative to the display and in points, so
/// the conversion is easy to get subtly wrong on a multi-display setup and
/// impossible to notice until someone with a second monitor tries it.
enum CaptureGeometry {
    static func sourceRect(forSelection selection: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: selection.minX - screenFrame.minX,
            y: selection.minY - screenFrame.minY,
            width: selection.width,
            height: selection.height
        )
    }

    /// Clamps a selection to the display it was made on, so a drag that runs
    /// off the edge doesn't ask for pixels that aren't there.
    static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let intersection = rect.intersection(bounds)
        return intersection.isNull ? .zero : intersection
    }
}

// MARK: - OCR

/// One line Vision recognised, with where it sat on screen.
///
/// `boundingBox` is Vision's normalised, bottom-left-origin space.
struct RecognizedLine: Equatable, Sendable {
    var text: String
    var boundingBox: CGRect
    var confidence: Float
}

enum OCRTextAssembler {
    /// Below this, a result is more likely noise than text. Vision happily
    /// "recognises" letterforms in textures and UI chrome at low confidence,
    /// and pasting that is worse than pasting nothing.
    static let minimumConfidence: Float = 0.3

    /// Reassembles recognised lines into text a person can paste.
    ///
    /// Vision returns observations in no guaranteed reading order and with no
    /// notion of paragraphs, so this:
    ///   1. drops low-confidence and empty fragments,
    ///   2. sorts top-to-bottom, then left-to-right for lines on the same row,
    ///   3. inserts a blank line where the vertical gap is much larger than
    ///      the usual line spacing, which is what makes paragraphs survive.
    static func assemble(_ lines: [RecognizedLine]) -> String {
        let usable = lines
            .filter { $0.confidence >= minimumConfidence }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usable.isEmpty else { return "" }

        // Vision's Y axis points up, so descending midY is top-to-bottom.
        // Lines whose centres are within half a line height count as the same
        // row and are ordered left-to-right instead.
        let sorted = usable.sorted { lhs, rhs in
            let lhsMid = lhs.boundingBox.midY
            let rhsMid = rhs.boundingBox.midY
            let tolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) / 2
            if abs(lhsMid - rhsMid) <= tolerance {
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            return lhsMid > rhsMid
        }

        let gaps = zip(sorted, sorted.dropFirst()).map { $0.boundingBox.minY - $1.boundingBox.maxY }
        let typicalGap = median(gaps.filter { $0 > 0 })

        var output = sorted[0].text.trimmingCharacters(in: .whitespaces)
        for (index, line) in sorted.enumerated().dropFirst() {
            let gap = sorted[index - 1].boundingBox.minY - line.boundingBox.maxY
            // 1.6x the usual gap reads as a paragraph break rather than the
            // next line. Without a typical gap to compare against (a two-line
            // capture) treat everything as one paragraph.
            let isParagraphBreak = typicalGap > 0 && gap > typicalGap * 1.6
            output += isParagraphBreak ? "\n\n" : "\n"
            output += line.text.trimmingCharacters(in: .whitespaces)
        }
        return output
    }

    /// Median rather than mean: one oversized gap (a heading, a figure)
    /// would drag a mean up far enough that no break is ever detected.
    static func median(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

// MARK: - Colour

/// A sampled screen colour, in every representation the user might want to
/// paste somewhere.
struct SampledColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    private func component(_ value: Double) -> Int {
        Int((min(1, max(0, value)) * 255).rounded())
    }

    /// Uppercase, matching how hex colours are written in nearly every design
    /// tool and stylesheet convention.
    var hex: String {
        String(format: "#%02X%02X%02X", component(red), component(green), component(blue))
    }

    var rgb: String {
        "rgb(\(component(red)), \(component(green)), \(component(blue)))"
    }

    /// CSS-style HSL, rounded to whole degrees and percents.
    var hsl: String {
        let redValue = min(1, max(0, red))
        let greenValue = min(1, max(0, green))
        let blueValue = min(1, max(0, blue))
        let maxValue = max(redValue, greenValue, blueValue)
        let minValue = min(redValue, greenValue, blueValue)
        let delta = maxValue - minValue
        let lightness = (maxValue + minValue) / 2

        var hue: Double = 0
        var saturation: Double = 0
        if delta > 0 {
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch maxValue {
            case redValue:
                hue = 60 * (((greenValue - blueValue) / delta).truncatingRemainder(dividingBy: 6))
            case greenValue:
                hue = 60 * (((blueValue - redValue) / delta) + 2)
            default:
                hue = 60 * (((redValue - greenValue) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }

        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    /// What lands on the clipboard for a given user preference.
    func string(for format: ColorFormat) -> String {
        switch format {
        case .hex: return hex
        case .rgb: return rgb
        case .hsl: return hsl
        }
    }
}

enum ColorFormat: String, CaseIterable, Identifiable, Sendable {
    case hex
    case rgb
    case hsl

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        }
    }
}
