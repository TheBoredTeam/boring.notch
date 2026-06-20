//
//  QuickNoteView.swift
//  boringNotch
//
//  Quick-capture surface for the notch: jot a thought and it appends to today's
//  capture file in the Obsidian vault. Left column composes, right column shows
//  what you've already captured today.
//

import SwiftUI
import Defaults

struct QuickNoteView: View {
    @ObservedObject private var manager = QuickNoteManager.shared
    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool

    private let accent = Color(red: 0.55, green: 0.7, blue: 1.0)

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            composer
            Divider().overlay(Color.white.opacity(0.08))
            todayList
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            manager.reloadToday()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { editorFocused = true }
        }
    }

    // MARK: - Composer (left)

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent)
                Text("Quick Note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { manager.revealInFinder() }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("Reveal today's capture file in Finder")
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(editorFocused ? accent.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )

                if draft.isEmpty {
                    Text("What's on your mind?")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draft)
                    .focused($editorFocused)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .frame(height: 52)

            HStack(spacing: 8) {
                Text(manager.destinationLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                saveButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        Button(action: saveNote) {
            HStack(spacing: 5) {
                Image(systemName: manager.savedFlash ? "checkmark" : "arrow.down.doc.fill")
                    .font(.system(size: 10, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(manager.savedFlash ? "Saved" : "Save")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(
                Capsule().fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                               ? Color.white.opacity(0.25) : accent)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help("Save to vault (⌘↵)")
    }

    private func saveNote() {
        if manager.save(draft) {
            draft = ""
            editorFocused = true
        }
    }

    // MARK: - Today's captures (right)

    private var todayList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("TODAY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                if !manager.todaysEntries.isEmpty {
                    Text("\(manager.todaysEntries.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }

            if manager.todaysEntries.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "tray")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.2))
                        Text("No captures yet")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(manager.todaysEntries) { entry in
                            HStack(alignment: .top, spacing: 7) {
                                Text(entry.time)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(accent.opacity(0.8))
                                    .frame(width: 32, alignment: .leading)
                                Text(entry.text)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: 250)
    }
}

#Preview {
    QuickNoteView()
        .frame(width: 600, height: 160)
        .background(.black)
}
