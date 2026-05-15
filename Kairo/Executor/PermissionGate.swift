import Foundation

@MainActor
final class PermissionGate {
    var onConfirmRequest: ((String) async -> Bool)?
    var onPassphraseRequest: (() async -> String?)?
    private let passphrase = "aurora"

    func allow(tool: Tool, args: [String: Any]) async -> Bool {
        switch tool.permissionTier {
        case .safe: return true
        case .destructive:
            let msg = "Confirm: \(tool.name)"
            return await onConfirmRequest?(msg) ?? false
        case .critical:
            let entered = await onPassphraseRequest?()
            return entered == passphrase
        }
    }
}
