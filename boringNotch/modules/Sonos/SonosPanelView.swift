//
//  SonosPanelView.swift
//  boringNotch
//
//  Pièces et favoris Sonos, dépliés depuis la ligne Sonos de UpNextPanelView (volume du groupe : touches du clavier).
//  Hors du drawingGroup du lecteur : ScrollView et TextField ne s'y dessinent pas.
//

import Defaults
import SwiftUI

struct SonosPanelView: View {
    @ObservedObject var store = SonosStore.shared
    @Default(.sonosFavorites) private var favorites
    @Default(.sonosLastGroup) private var lastGroup

    private var members: [String] { store.activeGroup?.memberIDs ?? [] }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.rooms) { room in roomRow(room) }
                chips.padding(.top, 4)
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .animation(.smooth(duration: 0.2), value: members)
    }

    private func roomRow(_ room: SonosRoom) -> some View {
        let isMember = members.contains(room.id)
        return HStack(spacing: 6) {
            Button { Task { await store.toggle(room.id) } } label: {
                Image(systemName: isMember ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isMember ? Color.effectiveAccent : .white.opacity(0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(isMember ? "Retirer du groupe" : "Ajouter au groupe")
            Button { Task { await store.move(to: room.id) } } label: {
                Text(room.name).font(.system(size: 11.5, weight: isMember ? .medium : .regular))
                    .foregroundStyle(.white.opacity(isMember ? 1 : 0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Écouter uniquement ici")
            if isMember && members.count > 1 {
                SonosVolumeSlider(value: store.roomVolumes[room.id] ?? 0) { v in await store.setRoomVolume(room.id, v) }
                    .frame(width: 46, height: 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(isMember ? 0.07 : 0)))
    }

    /// Favoris, retour au groupe précédent et enregistrement, en puces.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                if let last = lastGroup, Set(last) != Set(members), !store.label(for: last).isEmpty {
                    chip(icon: "arrow.uturn.backward", title: store.label(for: last)) { Task { await store.apply(last) } }
                }
                ForEach(favorites) { fav in
                    chip(icon: "star.fill", title: fav.name, active: Set(fav.roomIDs) == Set(members)) {
                        Task { await store.apply(fav.roomIDs) }
                    }
                    .contextMenu {
                        Button("Supprimer", role: .destructive) { store.deleteFavorite(fav.id) }
                    }
                }
                // La fenêtre du notch ne prend pas le clavier, sauf pendant une saisie de notes (allowsKey) : pas de champ de saisie,
                // le favori prend le nom des pièces du groupe.
                if !favorites.contains(where: { Set($0.roomIDs) == Set(members) }) {
                    chip(icon: "plus", title: favorites.isEmpty ? "Favori" : nil) { store.saveFavorite(name: store.label) }
                        .help("Enregistrer ce groupe en favori")
                }
            }
        }
    }

    private func chip(icon: String, title: String?, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8.5, weight: .semibold))
                if let title { Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1) }
            }
            .foregroundStyle(active ? Color.effectiveAccent : .white.opacity(0.75))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(active ? Color.effectiveAccent.opacity(0.18) : .white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Curseur 0–100 ; envoi throttlé (~150 ms) pendant le glisser, valeur finale au relâché.
struct SonosVolumeSlider: View {
    let value: Int
    let onChange: (Int) async -> Void
    @State private var local: Double = 0
    @State private var dragging = false
    @State private var lastSent = Date.distantPast

    var body: some View {
        CustomSlider(
            value: $local,
            range: 0...100,
            color: .white,
            dragging: $dragging,
            lastDragged: .constant(.distantPast),
            onValueChange: { v in Task { await onChange(Int(v.rounded())) } },
            onDragChange: { v in
                guard Date().timeIntervalSince(lastSent) > 0.15 else { return }
                lastSent = Date()
                Task { await onChange(Int(v.rounded())) }
            }
        )
        .onAppear { local = Double(value) }
        .onChange(of: value) { _, v in if !dragging { local = Double(v) } }
    }
}
