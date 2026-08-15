//
//  AudioPlayer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 09/08/24.
//

import Foundation
import AppKit

final class AudioPlayer: NSObject, NSSoundDelegate {
    /// Playing sounds must be retained or playback is cut off when ARC
    /// releases the instance at the end of the statement.
    private var sound: NSSound?

    func play(fileName: String, fileExtension: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        sound.delegate = self
        self.sound = sound
        sound.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        self.sound = nil
    }
}
