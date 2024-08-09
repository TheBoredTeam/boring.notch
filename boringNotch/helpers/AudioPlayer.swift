//
//  AudioPlayer.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 09/08/24.
//

import Foundation
import AppKit

class AudioPlayer {
    func play(fileName: String, fileExtension: String) {
        NSSound(contentsOf:Bundle.main.url(forResource: fileName, withExtension: fileExtension)!, byReference: false)?.play()
    }
}
