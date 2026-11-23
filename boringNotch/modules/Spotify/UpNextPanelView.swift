//
//  UpNextPanelView.swift
//  boringNotch
//
//  Colonne droite du lecteur : titre précédent + deux à venir (Web API Spotify), visualiseur,
//  et Sonos réduit à une ligne en bas qui déplie pièces et favoris sur place.
//  Hors du drawingGroup du lecteur : AsyncImage et ScrollView ne s'y dessinent pas.
//

import SwiftUI

struct UpNextPanelView: View {
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var sonos = SonosStore.shared
    @ObservedObject private var api = SpotifyWebAPI.shared
    @State private var showRooms = false

    private var previous: SpotifyWebAPI.QueueTrack? { api.snapshot?.previous }
    private var next: [SpotifyWebAPI.QueueTrack] { api.snapshot?.next ?? [] }
    private var devices: [SpotifyDevice] { api.snapshot?.devices ?? [] }

    private var localName: String { Host.current().localizedName ?? "" }

    private var hasQueue: Bool { !next.isEmpty || previous != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showRooms && sonos.isActive {
                SonosPanelView().transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if hasQueue {
                tracks.transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                spectrum
                    .frame(width: 16, height: 12)
                    .scaleEffect(2.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if sonos.isActive {
                Spacer(minLength: 0)
                sonosLine
            } else if SpotifyConnect.remoteActive(devices, localName: localName) != nil
                        || SpotifyConnect.controllable(devices).count > 1 {
                Spacer(minLength: 0)
                deviceLine
            }
        }
        .frame(height: 110)
        .animation(.smooth(duration: 0.25), value: showRooms)
        .animation(.smooth(duration: 0.35), value: next)
        .animation(.smooth(duration: 0.35), value: previous)
        // La file vient du cache de SpotifyWebAPI (déjà là à l'ouverture) ; on la rafraîchit derrière, sans attendre.
        .onAppear { api.refresh() }
        .onChange(of: sonos.isActive) { _, active in if !active { showRooms = false } }
    }

    /// Frise : précédent, repère « en cours » (visualiseur), puis les titres à venir.
    @ViewBuilder
    private var tracks: some View {
        if !sonos.isActive, let previous {
            QueueRow(track: previous, direction: .backward) { music.previousTrack() }
        }
        nowMarker
        ForEach(Array(next.enumerated()), id: \.element.id) { i, track in
            // ponytail: « suivant » ×(i+1) — l'AppleScript ne sait pas sauter à un titre sans casser le contexte de lecture.
            QueueRow(track: track, direction: .forward) { for _ in 0...i { music.nextTrack() } }
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
        }
    }

    private var tint: Color { Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.6) }

    /// Le titre en cours, entre le passé et la suite : visualiseur dans la colonne des vignettes, filet qui s'efface.
    private var nowMarker: some View {
        HStack(spacing: 7) {
            spectrum.frame(width: 16, height: 9).frame(width: QueueRow.art)
            LinearGradient(colors: [tint.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .padding(.horizontal, 5)
        .frame(height: 10)
        .accessibilityLabel("En cours : \(music.songTitle)")
    }

    private var spectrum: some View {
        Rectangle()
            .fill(tint.gradient)
            .mask { AudioSpectrumView(isPlaying: $music.isPlaying) }
    }

    /// Où ça joue quand c'est un autre appareil que ce Mac ; le menu déplace la lecture (Spotify Connect).
    private var deviceLine: some View {
        let remote = SpotifyConnect.remoteActive(devices, localName: localName)
        return Menu {
            ForEach(SpotifyConnect.controllable(devices)) { d in
                Button {
                    guard let id = d.id else { return }
                    Task {
                        _ = await api.transfer(to: id)
                        api.refresh(settle: .seconds(1))
                    }
                } label: {
                    Label(SpotifyConnect.sameName(d.name, localName) ? "Ce Mac" : d.name,
                          systemImage: SpotifyConnect.symbol(for: d.type))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: remote.map { SpotifyConnect.symbol(for: $0.type) } ?? "hifispeaker.2")
                    .font(.system(size: 9))
                if let remote {
                    Text("Lecture sur \(remote.name)")
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Déplacer la lecture Spotify")
    }

    /// Sonos discret : le volume passe par les touches du clavier, la ligne ne fait que l'afficher.
    private var sonosLine: some View {
        Button { showRooms.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: (sonos.activeGroup?.memberIDs.count ?? 0) > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                    .font(.system(size: 9))
                Text("\(sonos.label) · \(sonos.isMuted ? "muet" : "\(sonos.groupVolume)")")
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Image(systemName: showRooms ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(showRooms ? Color.effectiveAccent : .white.opacity(0.55))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showRooms ? "Revenir à la file d'attente" : "Pièces et favoris Sonos")
    }
}

/// Ligne de la file : vignette cerclée d'un filet, au survol elle s'assombrit et annonce l'action (reculer / avancer).
private struct QueueRow: View {
    enum Direction { case backward, forward }
    static let art: CGFloat = 26

    let track: SpotifyWebAPI.QueueTrack
    let direction: Direction
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                AsyncImage(url: track.artURL) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    Color.white.opacity(0.08)
                }
                .frame(width: Self.art, height: Self.art)
                .overlay {
                    Image(systemName: direction == .backward ? "backward.fill" : "forward.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.45))
                        .opacity(hovering ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                // Filet intérieur : détache les pochettes sombres du fond noir.
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                    Text(track.artist).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.07 : 0)))
            .opacity(direction == .backward && !hovering ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .help(direction == .backward ? "Revenir à ce titre" : "Passer à ce titre")
    }
}
