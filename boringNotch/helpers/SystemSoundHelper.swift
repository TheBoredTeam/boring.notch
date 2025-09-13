import Foundation

final class SystemSoundHelper {
    static func availableSystemSounds() -> [String] {
        let soundDirectory = "/System/Library/Sounds"
        guard let soundFiles = try? FileManager.default.contentsOfDirectory(atPath: soundDirectory) else {
            return []
        }
        return soundFiles.map { $0.replacingOccurrences(of: ".aiff", with: "") }
    }
}
