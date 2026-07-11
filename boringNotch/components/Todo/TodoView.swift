//
//  TodoView.swift
//  boringNotch
//
//  Created by Sidharth Sangelia on 11/07/26.
//


import SwiftUI

struct TodoView: View {
    @ObservedObject private var store = TodoStore.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Todos")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color.white.opacity(0.5))

            AddTodoField()

            if !store.todos.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.todos) { todo in
                            TodoRow(todo: todo)
                                .transition(.opacity)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onHover { vm.isHoveringTodos = $0 }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview {
    TodoView()
        .environmentObject(BoringViewModel())
        .frame(width: 320, height: 150)
        .background(.black)
}
