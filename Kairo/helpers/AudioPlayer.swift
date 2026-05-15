//
//  AudioPlayer.swift
//  Kairo
//
//  Created by Harsh Vardhan  Goswami  on 09/08/24.
//

import Foundation
import AppKit

class AudioPlayer {
    func play(fileName: String, fileExtension: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            print("[Kairo] AudioPlayer: missing resource \(fileName).\(fileExtension) — skipping")
            return
        }
        NSSound(contentsOf: url, byReference: false)?.play()
    }
}
