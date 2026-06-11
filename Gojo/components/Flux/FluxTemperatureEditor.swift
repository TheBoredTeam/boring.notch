//
//  FluxTemperatureEditor.swift
//  Gojo
//
//  f.lux-style color temperature controls: a gradient slider with tick
//  marks, and a 24-hour schedule curve showing how the screen temperature
//  changes across the day.
//

import Charts
import SwiftUI

enum FluxEditablePhase: String, CaseIterable, Identifiable {
    case daytime = "Daytime"
    case sunset = "Sunset"
    case bedtime = "Bedtime"

    var id: String { rawValue }
}

// MARK: - Gradient slider

struct FluxKelvinSlider: View {
    @Binding var kelvin: Double
    var range: ClosedRange<Double> = 1900...6500
    var step: Double = 50

    private let thumbSize: CGFloat = 18

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let width = geo.size.width
                let fraction = (kelvin - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(gradient: trackGradient, startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: CGFloat(fraction) * (width - thumbSize))
                }
                .frame(height: thumbSize, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let usable = width - thumbSize
                            guard usable > 0 else { return }
                            let f = min(max((value.location.x - thumbSize / 2) / usable, 0), 1)
                            let raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                            kelvin = (raw / step).rounded() * step
                        }
                )
            }
            .frame(height: thumbSize)

            tickMarks

            HStack {
                Spacer()
                Text(FluxColorMath.descriptor(kelvin: kelvin))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tickMarks: some View {
        HStack(spacing: 0) {
            ForEach(0..<41, id: \.self) { index in
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 1, height: index % 5 == 0 ? 7 : 4)
                if index < 40 {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, thumbSize / 2)
    }

    private var trackGradient: Gradient {
        let span = range.upperBound - range.lowerBound
        let stops = stride(from: range.lowerBound, through: range.upperBound, by: 250).map { k -> Gradient.Stop in
            let rgb = FluxColorMath.whitePoint(kelvin: k)
            return Gradient.Stop(
                color: Color(red: rgb.red, green: rgb.green, blue: rgb.blue),
                location: CGFloat((k - range.lowerBound) / span)
            )
        }
        return Gradient(stops: stops)
    }
}

// MARK: - 24-hour schedule curve

struct FluxCurveSample: Identifiable {
    let minute: Double
    let kelvin: Double
    let phase: FluxPhase

    var id: Double { minute }
}

struct FluxScheduleChart: View {
    let samples: [FluxCurveSample]
    let nowMinute: Double
    let nowKelvin: Double
    let sunlightLabel: String

    static func sampleCurve(config: FluxScheduleConfig, solar: SolarDayEvents?) -> [FluxCurveSample] {
        stride(from: 0.0, through: 1440.0, by: 5.0).map { minute in
            let result = FluxScheduleEngine.evaluate(
                nowMinutes: minute.truncatingRemainder(dividingBy: 1440), solar: solar, config: config)
            return FluxCurveSample(minute: minute, kelvin: result.kelvin, phase: result.phase)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(samples) { sample in
                    // Explicit baseline at the domain minimum — an implicit
                    // y=0 baseline lies outside the clipped 1500...6700 domain
                    AreaMark(
                        x: .value("Time", sample.minute),
                        yStart: .value("Temperature", 1500),
                        yEnd: .value("Temperature", sample.kelvin)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.06), Color.orange.opacity(0.45)],
                            startPoint: .top, endPoint: .bottom))
                    LineMark(
                        x: .value("Time", sample.minute),
                        y: .value("Temperature", sample.kelvin)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.orange.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                PointMark(
                    x: .value("Time", nowMinute),
                    y: .value("Temperature", nowKelvin)
                )
                .foregroundStyle(.orange)
                .symbolSize(110)
            }
            .chartXScale(domain: 0...1440)
            .chartYScale(domain: 1500...6700)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [0, 360, 720, 1080, 1440]) { value in
                    AxisValueLabel {
                        if let minute = value.as(Double.self) {
                            Text(Self.hourLabel(minute: minute))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            phaseBar
                .frame(height: 4)
                .clipShape(Capsule())

            Text(sunlightLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Blue while the sun is up, orange in the evening, red around bedtime —
    /// mirrors f.lux's day-strip under the curve.
    private var phaseBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color.opacity(0.75))
                        .frame(width: max((segment.end - segment.start) * geo.size.width, 1))
                        .offset(x: segment.start * geo.size.width)
                }
            }
        }
    }

    private struct PhaseSegment: Identifiable {
        let id: Int
        let start: CGFloat
        let end: CGFloat
        let color: Color
    }

    private var segments: [PhaseSegment] {
        var result: [PhaseSegment] = []
        var startIndex = 0
        for index in 1...samples.count {
            let isLast = index == samples.count
            if isLast || Self.barColor(samples[index].phase) != Self.barColor(samples[startIndex].phase) {
                result.append(PhaseSegment(
                    id: startIndex,
                    start: CGFloat(samples[startIndex].minute / 1440),
                    end: CGFloat((isLast ? 1440 : samples[index].minute) / 1440),
                    color: Self.barColor(samples[startIndex].phase)
                ))
                startIndex = index
            }
        }
        return result
    }

    private static func barColor(_ phase: FluxPhase) -> Color {
        switch phase {
        case .day, .sunrise:
            return .blue
        case .sunset, .evening:
            return .orange
        case .windDown, .bedtime:
            return .red
        }
    }

    private static func hourLabel(minute: Double) -> String {
        let hour = Int(minute / 60) % 24
        switch hour {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case ..<12: return "\(hour) AM"
        default: return "\(hour - 12) PM"
        }
    }
}
