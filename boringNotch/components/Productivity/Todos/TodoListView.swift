//
//  TodoListView.swift
//  boringNotch
//
//  A quick to-do list kept on this Mac. Starred items stay at the top.
//

import Defaults
import SwiftUI

struct TodoItem: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id = UUID()
    var title: String
    var isDone = false
    var isStarred = false
    var createdAt = Date()
}

struct TodoListView: View {
    @Default(.todoItems) var todos
    @State private var newTitle = ""

    /// Starred first, finished last, otherwise newest first.
    private var sortedTodos: [TodoItem] {
        todos.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            if lhs.isStarred != rhs.isStarred { return lhs.isStarred }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var remainingCount: Int {
        todos.filter { !$0.isDone }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.effectiveAccent)
                TextField("Add a to-do and press Return", text: $newTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addTodo)
                Spacer()
                Text("\(remainingCount) left")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                if todos.contains(where: \.isDone) {
                    Button("Clear done") {
                        withAnimation(.smooth) { todos.removeAll(where: \.isDone) }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.08)))

            if todos.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.title2)
                    Text("Nothing to do. Nice.")
                        .font(.caption)
                }
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(sortedTodos) { todo in
                            TodoRow(
                                todo: todo,
                                onToggleDone: { update(todo.id) { $0.isDone.toggle() } },
                                onToggleStar: { update(todo.id) { $0.isStarred.toggle() } },
                                onDelete: { todos.removeAll { $0.id == todo.id } }
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func addTodo() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation(.smooth) {
            todos.append(TodoItem(title: title))
        }
        newTitle = ""
    }

    private func update(_ id: UUID, _ change: (inout TodoItem) -> Void) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.smooth) {
            change(&todos[index])
        }
    }
}

private struct TodoRow: View {
    let todo: TodoItem
    let onToggleDone: () -> Void
    let onToggleStar: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleDone) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? Color.effectiveAccent : .gray)
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone ? .gray : .white)
                .lineLimit(1)

            Spacer()

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }

            Button(action: onToggleStar) {
                Image(systemName: todo.isStarred ? "star.fill" : "star")
                    .foregroundStyle(todo.isStarred ? .yellow : .gray)
                    .opacity(todo.isStarred || isHovering ? 1 : 0)
            }
            .buttonStyle(.plain)
            .help(todo.isStarred ? "Unstar" : "Star")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(isHovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
