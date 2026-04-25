//
//  SpotifyMusicModels.swift
//  boringNotch
//
//  Created by Dan on 4/15/26.
//

struct SpotifyPlayerState {
    var isPlaying:  Bool   = false
    var trackName:  String = "Unknown"
    var artist:     String = "Unknown"
    var album:      String = "Unknown"
    var position:   Double = 0
    var duration:   Double = 0
    var trackID:    String = ""
    var shuffle:    Bool   = false
    var `repeat`:   Bool   = false
    var volume:     Int    = 50
    var artworkURL: String = ""
    var isLiked:    Bool   = false
}
