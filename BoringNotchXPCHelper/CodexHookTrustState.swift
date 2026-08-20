import Foundation

public struct CodexHookTrustState: Sendable {
    private let trustedSections: Set<String>
    private let disabledSections: Set<String>

    public init(configuration: String) {
        let sectionPrefix = "[hooks.state.\""
        var currentSection: String?
        var trustedSections = Set<String>()
        var disabledSections = Set<String>()

        for rawLine in configuration.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix(sectionPrefix), line.hasSuffix("\"]") {
                currentSection = String(
                    line.dropFirst(sectionPrefix.count).dropLast(2)
                )
                continue
            }
            if line.hasPrefix("[") {
                currentSection = nil
                continue
            }
            guard let currentSection else { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "trusted_hash":
                guard value.hasPrefix("sha256:"),
                      value.dropFirst("sha256:".count).count == 64,
                      value.dropFirst("sha256:".count).allSatisfy(\.isHexDigit) else {
                    continue
                }
                trustedSections.insert(currentSection)
            case "enabled" where value.lowercased() == "false":
                disabledSections.insert(currentSection)
            default:
                continue
            }
        }

        self.trustedSections = trustedSections
        self.disabledSections = disabledSections
    }

    public func areTrusted(_ expectedSections: Set<String>) -> Bool {
        !expectedSections.isEmpty
            && expectedSections.isSubset(of: trustedSections)
            && expectedSections.isDisjoint(with: disabledSections)
    }
}
