import Foundation

final class KairoLongTermMemory {
    private(set) var facts: [String] = [
        "John builds KushTunes, Ember Records, Tech4SSD.",
        "Manages socials for Lady Kola.",
        "Mac username: wizlox.",
        "Based in Kampala."
    ]

    func add(_ fact: String) { facts.append(fact) }
    func all() -> [String] { facts }
}
