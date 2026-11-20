// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct WeatherView: View {
    var body: some View { UtilityPage(weatherPage: true) }
}
struct DevicesView: View {
    var body: some View { UtilityPage(weatherPage: false) }
}
private struct UtilityPage: View {
    @ObservedObject private var hub = NotchFeatures.shared
    @State private var query = ""
    let weatherPage: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if weatherPage { weather } else { devices }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }.scrollIndicators(.never).font(.system(size: 12))
    }
    @ViewBuilder private var weather: some View {
        HStack(spacing: 18) {
            if let weather = hub.forecast {
                Image(systemName: FeatureForecast.condition(weather.current.weather_code).1)
                    .font(.system(size: 40)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(hub.place.name).font(.headline)
                    Text("\(Int(weather.current.temperature_2m.rounded()))°  ·  \(FeatureForecast.condition(weather.current.weather_code).0)").font(.title2)
                    Text("Feels like \(Int(weather.current.apparent_temperature.rounded()))° · Wind \(Int(weather.current.wind_speed_10m.rounded())) km/h").foregroundStyle(.secondary)
                    if let date = hub.fetchedAt { Text("Updated \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
                }
            } else {
                Image(systemName: "cloud.sun.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) { Text(hub.place.name).font(.headline); Text(hub.loadingWeather ? "Loading weather…" : "Weather has not loaded yet.").foregroundStyle(.secondary) }
            }
            Spacer()
            Button { Task { await hub.refreshWeather(force: true) } } label: { Image(systemName: "arrow.clockwise") }.disabled(hub.loadingWeather).help("Refresh weather")
        }.padding(12).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        if let error = hub.weatherError { Text(error).foregroundStyle(.orange) }
        HStack { Image(systemName: "magnifyingglass"); TextField("Find a city", text: $query).textFieldStyle(.plain) }
            .padding(9).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: query) { hub.searchCities(query) }
        ForEach(hub.cityResults) { place in
            Button {
                hub.place = place; query = ""; hub.cityResults = []
            } label: {
                HStack { VStack(alignment: .leading) { Text(place.name); Text(place.detail).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "location.circle") }
            }.buttonStyle(.plain)
        }
        if let error = hub.searchError { Text(error).foregroundStyle(.secondary) }
        Link("Weather & city data: Open-Meteo", destination: URL(string: "https://open-meteo.com/")!).font(.caption2)
        Text("The selected city is saved on this Mac. No GPS access is used.").font(.caption2).foregroundStyle(.secondary)
    }
    @ViewBuilder private var devices: some View {
        Toggle("Bluetooth connection activity", isOn: $hub.bluetoothEnabled)
        Text("Shows a live activity when a paired Bluetooth device connects or disconnects. No device discovery scan is performed.").font(.caption).foregroundStyle(.secondary)
        if let error = hub.bridge.error { Text(error).foregroundStyle(.orange) }
        if hub.bluetoothEnabled && !hub.bridge.bluetoothRunning { Text("Bluetooth is unavailable or switched off. Check Bluetooth and app access in System Settings.").foregroundStyle(.orange) }
        ForEach(hub.bridge.devices) { device in
            HStack(spacing: 10) {
                Image(systemName: "headphones").foregroundStyle(Color.accentColor)
                Text(device.name).lineLimit(1)
                Spacer()
                Circle().fill(device.connected ? .green : .gray).frame(width: 6, height: 6)
                Text(device.connected ? "Connected" : "Disconnected").foregroundStyle(.secondary)
            }.padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        }
        if hub.bridge.devices.isEmpty { Text("No paired devices reported by macOS.").foregroundStyle(.secondary) }
    }
}
struct FeatureActivity: View {
    @ObservedObject private var hub = NotchFeatures.shared
    var centerWidth: CGFloat
    var body: some View {
        if let banner = hub.banner, !hub.locked {
            HStack(spacing: 10) {
                Image(systemName: banner.0).foregroundStyle(Color.accentColor)
                Text(banner.1).font(.caption).lineLimit(1).frame(width: 92, alignment: .leading)
                Color.clear.frame(width: max(0, centerWidth - 20))
                Text(banner.2).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(width: 122, alignment: .trailing)
            }.padding(.horizontal, 8).frame(height: 32)
        }
    }
}
