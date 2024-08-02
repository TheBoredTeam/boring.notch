import SwiftUI
import AVFoundation
import Combine

// MARK: - Data Models

struct Song: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let albumArt: String
}

// MARK: - Music Visualizer

struct MusicVisualizer: View {
    @State private var amplitudes: [CGFloat] = Array(repeating: 0, count: 5)
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: amplitudes[index])
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                for i in 0..<5 {
                    amplitudes[i] = CGFloat.random(in: 5...20)
                }
            }
        }
    }
}

// MARK: - Music Manager

class MusicManager: ObservableObject {
    private var player = AVPlayer()
    private var playerItem: AVPlayerItem?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var songTitle: String = "Blinding Lights"
    @Published var artistName: String = "The Weeknd"
    @Published var albumArt: String = "music.note"
    @Published var isPlaying = false
    
    init() {
        setupNowPlayingObserver()
        setupPlaybackStateObserver()
    }
    
    private func setupNowPlayingObserver() {
        NotificationCenter.default.publisher(for: .AVPlayerItemNewAccessLogEntry, object: playerItem)
            .sink { [weak self] _ in
                self?.updateNowPlayingInfo()
            }
            .store(in: &cancellables)
    }
    
    private func setupPlaybackStateObserver() {
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                self?.isPlaying = (status == .playing)
            }
            .store(in: &cancellables)
    }
    
    private func updateNowPlayingInfo() {
        // Example: Get metadata from the currently playing AVPlayerItem
        guard let item = player.currentItem else { return }
        // 'commonMetadata' was deprecated in macOS 13.0: Use load(.commonMetadata) instead
        let metadataList = item.asset.commonMetadata
        
        
        print("Metadata: \(metadataList)")
        
        for metadata in metadataList {
            if metadata.commonKey?.rawValue == "title" {
                songTitle = metadata.stringValue ?? "Unknown Title"
            } else if metadata.commonKey?.rawValue == "artist" {
                artistName = metadata.stringValue ?? "Unknown Artist"
            } else if metadata.commonKey?.rawValue == "artwork",
                      // 'commonMetadata' was deprecated in macOS 13.0: Use load(.commonMetadata) instead
                      let data = metadata.dataValue,
                      let image = NSImage(data: data) {
                albumArt = image.name() ?? "music.note"
            }
        }
    }
    
    func togglePlayPause() {
        isPlaying ? player.pause() : player.play()
    }
    
    func nextTrack() {
        // Implement next track functionality
    }
    
    func previousTrack() {
        // Implement previous track functionality
    }
}

struct BottomRoundedRectangle: Shape {
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Top left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        
        // Top right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        
        // Bottom right corner (rounded)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                    radius: radius,
                    startAngle: Angle(degrees: 0),
                    endAngle: Angle(degrees: 90),
                    clockwise: false)
        
        // Bottom left corner (rounded)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                    radius: radius,
                    startAngle: Angle(degrees: 90),
                    endAngle: Angle(degrees: 180),
                    clockwise: false)
        
        // Back to top left to close the path
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Dynamic Notch

struct BoringNotch: View {
    let onHover: () -> Void
    @State private var isExpanded = false
    @StateObject private var musicManager = MusicManager()
    
    var body: some View {
        ZStack {
            BottomRoundedRectangle(
                radius: 12)
            .fill(Color.black)
            .frame(width: isExpanded ? 500 : 290, height: isExpanded ? 200: 40)
            .animation(.spring(), value: isExpanded)
            
            HStack {
                Image(systemName: musicManager.albumArt)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(.white)
                
                if isExpanded {
                    VStack(alignment: .leading) {
                        Text(musicManager.songTitle)
                            .font(.caption)
                            .foregroundColor(.white)
                        Text(musicManager.artistName)
                            .font(.caption2)
                            .foregroundColor(.gray)
                        HStack(spacing: 15) {
                            Button(action: {
                                musicManager.previousTrack()
                            }) {
                                Image(systemName: "backward.fill")
                                    .foregroundColor(.white)
                            }
                            Button(action: {
                                musicManager.togglePlayPause()
                            }) {
                                Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                    .foregroundColor(.white)
                            }
                            Button(action: {
                                musicManager.nextTrack()
                            }) {
                                Image(systemName: "forward.fill")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .transition(.opacity)
                }
                
                Spacer()
                
                MusicVisualizer()
                    .frame(width: 30)
            }.frame(width: isExpanded ? 480 : 280)
                .padding(.horizontal, 10)
        }
        .onHover { hovering in
            withAnimation(.spring()) {
                isExpanded = hovering
                onHover()
            }
        }
    }
}

struct ContentView: View {
    let onHover: () -> Void
    var body: some View {
        BoringNotch(onHover: onHover)
            .frame(maxWidth: .infinity, maxHeight: 200)
            .background(Color.clear)
            .edgesIgnoringSafeArea(.top)
    }
}
