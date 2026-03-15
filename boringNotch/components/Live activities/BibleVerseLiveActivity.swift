//
//  BibleVerseLiveActivity.swift
//  boringNotch
//
//  Created on feature/bible-verse-of-the-day
//

import SwiftUI

struct BibleVerseLiveActivity: View {
    @ObservedObject private var bibleManager = BibleVerseManager.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .foregroundStyle(.white.opacity(0.8))
                .font(.system(size: 14, weight: .medium))
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )
            
            Rectangle()
                .fill(.black)
                .overlay(
                    VStack(alignment: .leading, spacing: 2) {
                        if let verse = bibleManager.todaysVerse {
                            Text(verse.reference)
                                .font(.caption2)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                            
                            MarqueeText(
                                .constant(verse.text),
                                font: .subheadline,
                                nsFont: .subheadline,
                                textColor: .white.opacity(0.9),
                                frameWidth: vm.closedNotchSize.width - 60
                            )
                            .lineLimit(2)
                        } else if bibleManager.isLoading {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Loading…")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        } else {
                            Text("No verse available")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
                .frame(
                    width: vm.closedNotchSize.width
                        - max(0, vm.effectiveClosedNotchHeight - 12)
                        - 20
                )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
        .task {
            await bibleManager.loadTodaysVerseIfNeeded()
        }
    }
}

