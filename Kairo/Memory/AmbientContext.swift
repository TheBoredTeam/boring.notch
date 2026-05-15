import AppKit

struct KairoAmbientContext {
    let time: String
    let location: String
    let focusedApp: String

    static func current() -> KairoAmbientContext {
        let df = DateFormatter()
        df.dateFormat = "EEE, MMM d · h:mm a"
        let focused = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        return KairoAmbientContext(
            time: df.string(from: Date()),
            location: "Kampala",
            focusedApp: focused
        )
    }
}
