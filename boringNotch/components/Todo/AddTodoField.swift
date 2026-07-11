//
//  AddTodoField.swift
//  boringNotch
//
//  Created by Sidharth Sangelia on 11/07/26.
//

//  Return creates a todo and clears the field. That's the whole feature.


import SwiftUI

struct AddTodoField: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var newTitle = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))

            TextField("New Todo", text: $newTitle, onCommit: addTodo)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundColor(.white)
                .focused($isFocused)
        }
        .padding(.vertical, 2)
    }

    private func addTodo() {
        store.add(newTitle)
        newTitle = ""
    }
}
