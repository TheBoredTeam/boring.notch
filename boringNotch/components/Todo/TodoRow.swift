//
//  TodoRow.swift
//  boringNotch
//
//  Created by Sidharth Sangelia on 11/07/26.
//

import SwiftUI

struct TodoRow: View {
    let todo: Todo
    @ObservedObject private var store = TodoStore.shared

    @State private var isEditing = false
    @State private var editingTitle = ""
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TodoCheckbox(isOn: todo.completed) {
                store.toggle(todo)
            }

            if isEditing {
                TextField("", text: $editingTitle, onCommit: commitEdit)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .onExitCommand(perform: cancelEdit)
                    .onAppear { isFocused = true }
            } else {
                Text(todo.title)
                    .font(.callout)
                    .foregroundColor(.white)
                    .strikethrough(todo.completed, color: Color(white: 0.65))
                    .opacity(todo.completed ? 0.4 : 1.0)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2, perform: beginEdit)
            }

            Spacer(minLength: 0)

            if isHovering && !isEditing {
                Button(action: { store.delete(todo) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(white: 0.65))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 2)
        .onHover { isHovering = $0 }
    }

    private func beginEdit() {
        editingTitle = todo.title
        isEditing = true
    }

    private func commitEdit() {
        store.edit(todo, title: editingTitle)
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }
}

/// Same ring-checkbox look as the calendar's ReminderToggle, kept local
/// since todos don't share a calendar color.
private struct TodoCheckbox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.effectiveAccent, lineWidth: 2)
                    .frame(width: 14, height: 14)
                if isOn {
                    Circle()
                        .fill(Color.effectiveAccent)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}
