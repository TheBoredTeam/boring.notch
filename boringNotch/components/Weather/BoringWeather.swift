//
//  BoringWeather.swift
//  boringNotch
//
//  Created by Arsh Anwar on 26/12/25.
//

import SwiftUI
import Defaults

struct WeatherView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var weatherManager = WeatherManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            if weatherManager.isLoading {
                loadingView
            } else if let error = weatherManager.errorMessage {
                errorView(message: error)
            } else if let weather = weatherManager.currentWeather {
                weatherContent(weather: weather)
            } else {
                emptyStateView
            }
        }
        .frame(height: 120)
        .onAppear {
            weatherManager.checkLocationAuthorization()
        }
        .onChange(of: vm.notchState) { _, _ in
            if vm.notchState == .open {
                weatherManager.fetchWeather()
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .tint(.white)
            Text("Loading weather...")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
                .multilineTextAlignment(.center)
            
            if weatherManager.locationAuthorizationStatus == .denied {
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.effectiveAccent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.fill")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text("No weather data")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enable location access")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func weatherContent(weather: WeatherData) -> some View {
        VStack(spacing: 8) {
            // Location and main weather
            HStack(alignment: .center, spacing: 8) {
                // Weather icon
                Image(systemName: weather.systemIconName)
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Location
                    Text(weather.location)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                    
                    // Temperature
                    Text(weather.temperatureString)
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white)
                }
                
                Spacer(minLength: 0)
                
                // Condition on the right
                VStack(alignment: .trailing, spacing: 2) {
                    Text(weather.condition)
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                    
                    Text("Feels \(String(format: "%.0f°", weather.feelsLike))")
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            Divider()
                .background(Color(white: 0.3))
                .padding(.horizontal, 12)
            
            // Weather details
            HStack(spacing: 12) {
                WeatherDetailItem(
                    icon: "humidity.fill",
                    label: "Humidity",
                    value: "\(weather.humidityInt)%"
                )
                
                Divider()
                    .background(Color(white: 0.3))
                    .frame(height: 20)
                
                WeatherDetailItem(
                    icon: "wind",
                    label: "Wind",
                    value: String(format: "%.0f km/h", weather.windSpeed)
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

struct WeatherDetailItem: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(Color(white: 0.65))
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    WeatherView()
        .frame(width: 215, height: 130)
        .background(.black)
        .environmentObject(BoringViewModel())
}
