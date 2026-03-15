//
//  BibleVersePanelView.swift
//  boringNotch
//
//  Panel that replaces the calendar section when the user toggles to verse view.
//

import SwiftUI

struct BibleVersePanelView: View {
    @ObservedObject private var bibleManager = BibleVerseManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.9))
                Text("Verse of the day")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            if let verse = bibleManager.todaysVerse {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verse.reference)
                            .font(.caption)
                            .foregroundStyle(Color(white: 0.65))
                        Text(verse.text)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
            } else if bibleManager.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading…")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No verse available")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .frame(height: 120)
        .task {
            await bibleManager.loadTodaysVerseIfNeeded()
        }
    }
}
