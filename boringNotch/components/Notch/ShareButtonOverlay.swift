//
//  ShareButtonOverlay.swift
//  boringNotch
//

import SwiftUI

struct ShareButtonOverlay: View {
    @ObservedObject private var musicManager = MusicManager.shared

    @State private var isResolving: ShareKind?
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?
    @State private var searchHintWorkItem: DispatchWorkItem?

    private let linkService = OdesliLinkService.shared

    var body: some View {
        ZStack {
            shareMenu
            resolvingIndicator
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                toastView(toastMessage)
                    .fixedSize()
                    .offset(y: -36)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: toastMessage)
        .animation(.smooth(duration: 0.2), value: isResolving)
    }

    private var shareMenu: some View {
        Menu {
            Button("Share Track") { share(.track) }
            Button("Share Album") { share(.album) }
                .disabled(!isEnabled(.album))
        } label: {
            Image(systemName: "link")
                .font(.body)
                .foregroundColor(.primary)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .opacity(isResolving == nil ? 1 : 0)
        .allowsHitTesting(isResolving == nil)
    }

    private var resolvingIndicator: some View {
        ProgressView()
            .frame(width: 30, height: 30)
            .opacity(isResolving != nil ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func isEnabled(_ kind: ShareKind) -> Bool {
        switch kind {
        case .track:
            return true
        case .album:
            return !musicManager.album.isEmpty && musicManager.album != "Self Love"
        }
    }

    private func share(_ kind: ShareKind) {
        guard isResolving == nil else { return }
        isResolving = kind
        let title = musicManager.songTitle
        let artist = musicManager.artistName
        let album = musicManager.album

        // Keep the notch open for the whole fetch — the button sits near the
        // bottom edge, so the cursor easily strays outside it mid-lookup.
        SharingStateManager.shared.beginInteraction()

        let hintWorkItem = DispatchWorkItem {
            showToast(NSLocalizedString("Searching…", comment: "Share button: shown while a link is still resolving"))
        }
        searchHintWorkItem = hintWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: hintWorkItem)

        Task {
            do {
                let result = try await linkService.resolveShareLink(kind: kind, title: title, artist: artist, album: album)
                await MainActor.run {
                    searchHintWorkItem?.cancel()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.pageUrl.absoluteString, forType: .string)
                    isResolving = nil
                    showToast(NSLocalizedString("Link copied", comment: "Share button: toast shown after the link is copied to the clipboard"))
                }
            } catch ShareLinkError.rateLimited {
                await MainActor.run {
                    searchHintWorkItem?.cancel()
                    isResolving = nil
                    showToast(NSLocalizedString("Too many requests, please try again later", comment: "Share button: toast shown when the link-lookup API is rate-limiting us"))
                }
            } catch {
                await MainActor.run {
                    searchHintWorkItem?.cancel()
                    isResolving = nil
                    showToast(NSLocalizedString("Couldn't find a link", comment: "Share button: toast shown when no shareable link could be found"))
                }
            }
            // Grace period so the toast is readable before auto-hide can resume.
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                SharingStateManager.shared.endInteraction()
            }
        }
    }

    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        toastMessage = message

        let workItem = DispatchWorkItem {
            toastMessage = nil
        }
        toastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.75))
            .foregroundColor(.white)
            .cornerRadius(6)
    }
}
