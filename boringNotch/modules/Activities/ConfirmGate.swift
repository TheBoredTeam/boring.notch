//
//  ConfirmGate.swift
//  boringNotch
//
//  Double clic de confirmation : le premier arme, le second dans la fenêtre confirme.
//

import Foundation

struct ConfirmGate: Equatable {
    let window: TimeInterval
    let minGap: TimeInterval = 0.4
    private(set) var armedAt: Date?

    init(window: TimeInterval) { self.window = window }

    /// Premier appel : arme et renvoie false. Appel suivant dans la fenêtre : désarme et renvoie true.
    /// Après la fenêtre : ré-arme et renvoie false. Un appui à moins de `minGap` du premier (double clic réflexe)
    /// est ignoré : renvoie false et reste armé depuis le premier appui.
    mutating func press(at: Date) -> Bool {
        if let armedAt, isArmed(at: at) {
            guard at.timeIntervalSince(armedAt) >= minGap else { return false }
            self.armedAt = nil
            return true
        }
        armedAt = at
        return false
    }

    func isArmed(at: Date) -> Bool {
        guard let armedAt else { return false }
        return at.timeIntervalSince(armedAt) < window
    }
}
