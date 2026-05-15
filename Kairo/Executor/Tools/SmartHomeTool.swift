import Foundation

/// Real smart-home control via Home Assistant's REST API.
///
/// Configure with two environment variables (loaded by AppDelegate from
/// `~/.kairo.env` or `~/AI/Kairo/.env`):
///
///   HASS_URL=http://192.168.1.123:8123
///   HASS_TOKEN=<long-lived access token>
///
/// Without those, falls back to a logged stub so the LLM still gets a
/// shaped tool result (success: false, "HASS not configured").
///
/// Args:
///   device: friendly name ("lights", "ac", "tv", "front_door") OR a full
///           entity id ("light.living_room", "climate.bedroom")
///   action: toggle | on | off
///
/// Friendly names map to entity ids via `KAIRO_HASS_<device>_<n>` env vars:
///
///   KAIRO_HASS_LIGHTS=light.living_room,light.kitchen,light.studio
///   KAIRO_HASS_AC=climate.bedroom
///   KAIRO_HASS_TV=media_player.living_room_tv
///
/// Multiple entities (comma-separated) are toggled in sequence.
struct SmartHomeTool: Tool {
    let name = "smart_home"
    let description = "Controls lights, scenes, climate, and devices via Home Assistant"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let env = ProcessInfo.processInfo.environment
        guard
            let baseStr = env["HASS_URL"], let baseURL = URL(string: baseStr),
            let token = env["HASS_TOKEN"], !token.isEmpty
        else {
            let device = args["device"] as? String ?? "device"
            let action = args["action"] as? String ?? "toggle"
            return ToolResult(
                success: false,
                output: "HASS not configured (set HASS_URL + HASS_TOKEN). Would have \(action)d \(device).",
                tierUsed: .native
            )
        }

        let deviceArg = (args["device"] as? String ?? "").lowercased()
        let actionArg = (args["action"] as? String ?? "toggle").lowercased()

        guard !deviceArg.isEmpty else {
            return ToolResult(success: false, output: "Missing 'device' arg", tierUsed: .native)
        }

        let entities = resolveEntities(deviceArg)
        guard !entities.isEmpty else {
            return ToolResult(
                success: false,
                output: "No entity mapping for '\(deviceArg)'. Set KAIRO_HASS_\(deviceArg.uppercased())=<entity_id> in your .env.",
                tierUsed: .native
            )
        }

        var successes: [String] = []
        var failures: [String] = []
        for entity in entities {
            do {
                try await callService(baseURL: baseURL, token: token, entityID: entity, action: actionArg)
                successes.append(entity)
            } catch {
                failures.append("\(entity) (\(error.localizedDescription))")
            }
        }

        if failures.isEmpty {
            return ToolResult(success: true, output: "\(actionArg) \(successes.joined(separator: ", "))", tierUsed: .native)
        }
        return ToolResult(
            success: !successes.isEmpty,
            output: successes.isEmpty
                ? "Failed: \(failures.joined(separator: "; "))"
                : "Partial — ok: \(successes.joined(separator: ", ")); failed: \(failures.joined(separator: "; "))",
            tierUsed: .native
        )
    }

    // MARK: - HASS call

    private func callService(baseURL: URL, token: String, entityID: String, action: String) async throws {
        let domain = entityID.split(separator: ".").first.map(String.init) ?? "homeassistant"
        let service = mapAction(action, domain: domain)
        let url = baseURL.appendingPathComponent("api/services/\(domain)/\(service)")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        req.httpBody = try JSONSerialization.data(withJSONObject: ["entity_id": entityID])

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    /// Maps "on/off/toggle" → the right HASS service for the domain.
    /// HASS uses `turn_on`/`turn_off` for most domains, `set_hvac_mode` etc.
    /// for climate, but `toggle` works domain-agnostically for switches/lights.
    private func mapAction(_ action: String, domain: String) -> String {
        switch action {
        case "on":     return "turn_on"
        case "off":    return "turn_off"
        case "toggle": return "toggle"
        case "play":   return "media_play"
        case "pause":  return "media_pause"
        default:       return action      // pass through for advanced callers
        }
    }

    // MARK: - Friendly → entity-id resolution

    private func resolveEntities(_ device: String) -> [String] {
        // If it already looks like an entity id (contains a `.`), use it directly
        if device.contains(".") { return [device] }

        let env = ProcessInfo.processInfo.environment
        let key = "KAIRO_HASS_\(device.uppercased())"
        if let mapping = env[key], !mapping.isEmpty {
            return mapping
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        // Last-ditch default guesses for common terms
        switch device {
        case "lights":  return ["light.living_room"]
        case "ac", "climate": return ["climate.bedroom"]
        case "tv":      return ["media_player.living_room_tv"]
        default:        return []
        }
    }
}
