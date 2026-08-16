//
//  Todo.swift
//  boringNotch
//
//  Created by Sidharth Sangelia on 11/07/26.
//


import Foundation

struct Todo: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var completed: Bool

    init(id: UUID = UUID(), title: String, completed: Bool = false) {
        self.id = id
        self.title = title
        self.completed = completed
    }
}
