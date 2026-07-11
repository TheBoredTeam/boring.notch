//
//  AddTodoField.swift
//  boringNotch
//
//  Created by Sidharth Sangelia on 11/07/26.
//

//  Return creates a todo and clears the field. That's the whole feature.

import AppKit
import SwiftUI

struct AddTodoField: View {
    @ObservedObject private var store = TodoStore.shared
    @State private var newTitle = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.caption)
                .foregroundColor(Color.white.opacity(0.4))

            TextField("Add a todo…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundColor(.white)
                .focused($isFocused)
                .onSubmit(addTodo)
        }
        .padding(.vertical, 3)
        .onAppear {
            // Make the panel key so typing works immediately, without
            // requiring an extra click first.
            NSApp.windows
                .first(where: { $0 is BoringNotchSkyLightWindow })?
                .makeKey()
            isFocused = true
        }
    }

    private func addTodo() {
        let title = newTitle
        store.add(title)
        DispatchQueue.main.async {
            newTitle = ""
            isFocused = true
        }
    }
}
