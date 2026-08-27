import CryptoKit
import Foundation

public struct CodexHookTrustState: Sendable {
    private enum QuoteStyle {
        case basic
        case literal
    }

    private let trustedHashes: [String: String]
    private let disabledSections: Set<String>

    public init(configuration: String) {
        let sectionPrefix = "[hooks.state.\""
        var currentSection: String?
        var trustedHashes = [String: String]()
        var disabledSections = Set<String>()

        for rawLine in configuration.components(separatedBy: .newlines) {
            let line = Self.removingInlineComment(from: rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
                trustedHashes[currentSection] = value
            case "enabled" where value.lowercased() == "false":
                disabledSections.insert(currentSection)
            default:
                continue
            }
        }

        self.trustedHashes = trustedHashes
        self.disabledSections = disabledSections
    }

    private static func removingInlineComment(from line: String) -> String {
        var quoteStyle: QuoteStyle?
        var isEscaped = false

        for index in line.indices {
            let character = line[index]
            switch quoteStyle {
            case .basic:
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    quoteStyle = nil
                }
            case .literal:
                if character == "'" {
                    quoteStyle = nil
                }
            case nil:
                switch character {
                case "#":
                    return String(line[..<index])
                case "\"":
                    quoteStyle = .basic
                case "'":
                    quoteStyle = .literal
                default:
                    continue
                }
            }
        }

        return line
    }

    public func areTrusted(
        _ expectedSections: Set<String>,
        matching currentHashes: [String: String]
    ) -> Bool {
        !expectedSections.isEmpty
            && expectedSections.allSatisfy {
                trustedHashes[$0] == currentHashes[$0]
            }
            && expectedSections.isDisjoint(with: disabledSections)
    }

    public static func currentHash(
        eventName: String,
        matcher: String? = nil,
        command: String,
        timeout: Int,
        asynchronous: Bool = false,
        statusMessage: String? = nil,
        additionalContextLimit: Int? = nil
    ) -> String {
        var handler: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": timeout,
            "async": asynchronous,
        ]
        if let statusMessage {
            handler["statusMessage"] = statusMessage
        }
        if let additionalContextLimit {
            handler["additionalContextLimit"] = additionalContextLimit
        }

        var identity: [String: Any] = [
            "event_name": eventName,
            "hooks": [handler],
        ]
        if let matcher,
           eventName != "user_prompt_submit",
           eventName != "stop" {
            identity["matcher"] = matcher
        }

        guard let serialized = try? JSONSerialization.data(
            withJSONObject: identity,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else {
            return "sha256:"
        }
        let digest = SHA256.hash(data: serialized)
            .map { String(format: "%02x", $0) }
            .joined()
        return "sha256:\(digest)"
    }
}
