//
//  TodoView.swift
//  boringNotch
//
//  Created by Sidharth Sangelia on 11/07/26.
//


import SwiftUI

struct TodoView: View {
    @ObservedObject private var store = TodoStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Todos")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color(white: 0.65))

            if store.todos.isEmpty {
                Spacer(minLength: 0)
                Text("No todos yet")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.65))
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.todos) { todo in
                            TodoRow(todo: todo)
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            AddTodoField()
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    TodoView()
        .frame(width: 320, height: 150)
        .background(.black)
}
