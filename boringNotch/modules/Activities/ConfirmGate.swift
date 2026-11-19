//
//  ConfirmGate.swift
//  boringNotch
//
//  Double clic de confirmation : le premier arme, le second dans la fenêtre confirme.
//

import Foundation

struct ConfirmGate: Equatable {
    let window: TimeInterval
    private(set) var armedAt: Date?

    init(window: TimeInterval) { self.window = window }

    /// Premier appel : arme et renvoie false. Appel suivant dans la fenêtre : désarme et renvoie true.
    /// Après la fenêtre : ré-arme et renvoie false.
    mutating func press(at: Date) -> Bool {
        if isArmed(at: at) { armedAt = nil; return true }
        armedAt = at
        return false
    }

    func isArmed(at: Date) -> Bool {
        guard let armedAt else { return false }
        return at.timeIntervalSince(armedAt) < window
    }
}
