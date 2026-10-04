//
//  QuickNoteView.swift
//  boringNotch
//
//  A scratch pad that saves as you type.
//

import Defaults
import SwiftUI

struct QuickNoteView: View {
    @Default(.quickNoteText) var noteText

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Jot something down…")
                        .foregroundStyle(.gray)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $noteText)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
            }
            .font(.system(size: 13))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))

            HStack(spacing: 12) {
                Text("\(noteText.count) characters · saved automatically")
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(noteText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(noteText.isEmpty)
                Button {
                    noteText = ""
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(noteText.isEmpty)
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.gray)
        }
        .padding(.horizontal, 4)
    }
}
