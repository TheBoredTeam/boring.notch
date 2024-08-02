func fetchNowPlayingInfo() {
        guard let scriptURL = Bundle.main.url(forResource: "NowPlaying", withExtension: "scpt") else { return }
        var error: NSDictionary?
        if let script = NSAppleScript(contentsOf: scriptURL, error: &error) {
            if let output = script.executeAndReturnError(&error).stringValue {
                parseNowPlayingInfo(output)
            } else if let error = error {
                print("Error executing AppleScript: \(error)")
            }
        }
    }


    func parseNowPlayingInfo(_ info: String) {
        let components = info.split(separator: "||").map { String($0) }
        guard components.count == 5 else {
            print("Invalid now playing info format")
            return
        }
        let trackName = components[0]
        let artistName = components[1]
        let albumName = components[2]
        let artworkDataString = components[3]
        let currentApp = components[4]

        // Handle artwork data (convert from Base64 if necessary)
        var artwork: NSImage? = nil
        if !artworkDataString.isEmpty, let artworkData = Data(base64Encoded: artworkDataString) {
            artwork = NSImage(data: artworkData)
        }

        nowPlayingInfo = NowPlayingInfo(trackName: trackName, artistName: artistName, albumName: albumName, artwork: artwork)
        // Update your UI with this information
    }