//
//  TodoStore.swift
//  boringNotch
//
//  Created by Sidharth Sangelia on 11/07/26.
//


import Defaults
import Foundation
import SwiftUI

@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore()

    @Published private(set) var todos: [Todo] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var pendingRemovals: [UUID: Task<Void, Never>] = [:]

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("boringNotch", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("todos.json")
        encoder.outputFormatting = [.prettyPrinted]

        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? decoder.decode([Todo].self, from: data) else { return }
        todos = saved
    }

    func save() {
        guard let data = try? encoder.encode(todos) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.insert(Todo(title: trimmed), at: 0)
        save()
    }

    func toggle(_ todo: Todo) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[index].completed.toggle()
        save()

        if todos[index].completed {
            scheduleRemoval(for: todo.id)
        } else {
            cancelScheduledRemoval(for: todo.id)
        }
    }

    func edit(_ todo: Todo, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[index].title = trimmed
        save()
    }

    func delete(_ todo: Todo) {
        cancelScheduledRemoval(for: todo.id)
        todos.removeAll { $0.id == todo.id }
        save()
    }

    // MARK: - Auto-remove completed todos

    private func scheduleRemoval(for id: UUID) {
        pendingRemovals[id]?.cancel()
        let delaySeconds = Defaults[.todosAutoRemoveDelay]
        pendingRemovals[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else { return }
            self?.removeIfStillCompleted(id)
        }
    }

    private func cancelScheduledRemoval(for id: UUID) {
        pendingRemovals[id]?.cancel()
        pendingRemovals[id] = nil
    }

    private func removeIfStillCompleted(_ id: UUID) {
        pendingRemovals[id] = nil
        guard let index = todos.firstIndex(where: { $0.id == id }), todos[index].completed else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            todos.remove(at: index)
        }
        save()
    }
}
