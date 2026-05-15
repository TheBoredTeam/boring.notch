import Foundation
import AppKit

@MainActor
final class ContextBuilder {
    func build(userInput: String, shortTerm: [String], ambient: KairoAmbientContext) -> [KairoChatMessage] {
        var messages: [KairoChatMessage] = []
        messages.append(KairoChatMessage(role: "system", content: KairoSystemPrompt.kairo))
        let ctx = """
TIME: \(ambient.time)
LOCATION: \(ambient.location)
FOCUSED APP: \(ambient.focusedApp)
RECENT: \(shortTerm.suffix(5).joined(separator: " | "))
"""
        messages.append(KairoChatMessage(role: "system", content: ctx))
        messages.append(KairoChatMessage(role: "user", content: userInput))
        return messages
    }
}
