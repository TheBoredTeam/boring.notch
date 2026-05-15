import Foundation

struct WeatherTool: Tool {
    let name = "weather"
    let description = "Fetches current weather and forecast"
    let permissionTier: PermissionTier = .safe
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let lat = args["lat"] as? Double ?? WeatherService.defaultLat
        let lon = args["lon"] as? Double ?? WeatherService.defaultLon

        let data = try await WeatherService.fetch(lat: lat, lon: lon)

        await MainActor.run {
            KairoRuntime.shared.present(.weather, payload: data)
        }

        return ToolResult(
            success: true,
            output: "\(data.condition), \(data.temp)°C in \(data.location)",
            tierUsed: .native
        )
    }
}
