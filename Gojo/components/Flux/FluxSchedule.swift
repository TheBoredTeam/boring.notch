//
//  FluxSchedule.swift
//  Gojo
//
//  Schedule engine for the Flux night shift feature. Given the time of day,
//  solar events, and the user's bedtime, computes the target color
//  temperature and the named phase. Foundation-only for standalone testing.
//

import Foundation

enum FluxPhase: String {
    case day = "Day"
    case sunset = "Sunset"
    case evening = "Evening"
    case windDown = "Winding Down"
    case bedtime = "Bedtime"
    case sunrise = "Sunrise"
}

struct FluxScheduleConfig: Equatable {
    /// Target temperature during daylight.
    var dayKelvin: Double = 6500
    /// Target temperature after sunset.
    var sunsetKelvin: Double = 3400
    /// Target temperature at and after bedtime.
    var bedtimeKelvin: Double = 2300
    /// Bedtime as minutes after local midnight.
    var bedtimeMinutes: Double = 23 * 60
    /// How long before bedtime the wind-down ramp starts.
    var windDownMinutes: Double = 60
    /// Duration of the sunrise/sunset transitions.
    var transitionMinutes: Double = 60
}

enum FluxScheduleEngine {
    /// Fallback solar times (07:00 / 19:00) used when no location is set.
    static let fallbackSunriseMinutes: Double = 7 * 60
    static let fallbackSunsetMinutes: Double = 19 * 60

    /// The bedtime hold normally ends at sunrise, but never runs longer than
    /// this — an early-morning bedtime (later than sunrise) would otherwise
    /// pin the screen at the bedtime temperature for the entire waking day.
    static let maxBedtimeHoldMinutes: Double = 9 * 60

    /// Evaluates the schedule at a moment in time.
    /// - Parameters:
    ///   - nowMinutes: minutes after local midnight (0..<1440)
    ///   - solar: today's solar events, or nil when location is unknown
    static func evaluate(
        nowMinutes: Double,
        solar: SolarDayEvents?,
        config: FluxScheduleConfig
    ) -> (kelvin: Double, phase: FluxPhase) {
        let now = wrap(nowMinutes)

        let sunrise: Double
        let sunset: Double
        switch solar {
        case .regular(let rise, let set):
            sunrise = wrap(rise)
            sunset = wrap(set)
        case .polarDay, .polarNight, nil:
            // Polar days keep a sensible bedtime anchor; the solar component
            // below is overridden for polar cases.
            sunrise = fallbackSunriseMinutes
            sunset = fallbackSunsetMinutes
        }

        let (solarKelvin, solarPhase) = solarComponent(
            now: now, sunrise: sunrise, sunset: sunset, solar: solar, config: config)

        // The wind-down ramp starts from whatever the solar cycle shows at
        // that moment, so the hand-off stays continuous even when the window
        // begins in daylight or inside the sunset transition.
        let windStart = wrap(config.bedtimeMinutes - max(config.windDownMinutes, 1))
        let (windStartKelvin, _) = solarComponent(
            now: windStart, sunrise: sunrise, sunset: sunset, solar: solar, config: config)
        let (bedKelvin, bedPhase) = bedtimeComponent(
            now: now, sunrise: sunrise, windStartKelvin: windStartKelvin, config: config)

        // The dimmer of the two wins, so a bedtime before sunset (or a late
        // sunset) never produces a brighter screen than the other component.
        if bedKelvin < solarKelvin {
            return (bedKelvin, bedPhase)
        }
        return (solarKelvin, solarPhase)
    }

    /// Day/night cycle: day kelvin during daylight, sunset kelvin overnight,
    /// linear ramps across the sunset and sunrise transitions.
    private static func solarComponent(
        now: Double,
        sunrise: Double,
        sunset: Double,
        solar: SolarDayEvents?,
        config: FluxScheduleConfig
    ) -> (Double, FluxPhase) {
        switch solar {
        case .polarDay:
            return (config.dayKelvin, .day)
        case .polarNight:
            return (config.sunsetKelvin, .evening)
        default:
            break
        }

        let dayLength = forwardDistance(from: sunrise, to: sunset)
        let transition = min(config.transitionMinutes, dayLength / 2)

        let sinceSunrise = forwardDistance(from: sunrise, to: now)
        if sinceSunrise < transition {
            let progress = sinceSunrise / transition
            return (lerp(config.sunsetKelvin, config.dayKelvin, progress), .sunrise)
        }
        if sinceSunrise < dayLength {
            return (config.dayKelvin, .day)
        }

        let sinceSunset = forwardDistance(from: sunset, to: now)
        if sinceSunset < transition {
            let progress = sinceSunset / transition
            return (lerp(config.dayKelvin, config.sunsetKelvin, progress), .sunset)
        }
        return (config.sunsetKelvin, .evening)
    }

    /// Bedtime override: ramps from the solar temperature at the wind-down
    /// start down to the bedtime temperature, holds it until sunrise (capped
    /// at a night's sleep), then releases back to day across the transition.
    private static func bedtimeComponent(
        now: Double,
        sunrise: Double,
        windStartKelvin: Double,
        config: FluxScheduleConfig
    ) -> (Double, FluxPhase) {
        let windDown = max(config.windDownMinutes, 1)
        let windStart = wrap(config.bedtimeMinutes - windDown)

        let sinceWindStart = forwardDistance(from: windStart, to: now)
        if sinceWindStart < windDown {
            let progress = sinceWindStart / windDown
            return (lerp(windStartKelvin, config.bedtimeKelvin, progress), .windDown)
        }

        let bedtime = wrap(config.bedtimeMinutes)
        let holdLength = min(forwardDistance(from: bedtime, to: sunrise), maxBedtimeHoldMinutes)
        let sinceBedtime = forwardDistance(from: bedtime, to: now)
        if sinceBedtime < holdLength {
            return (config.bedtimeKelvin, .bedtime)
        }

        let releaseStart = wrap(bedtime + holdLength)
        let sinceRelease = forwardDistance(from: releaseStart, to: now)
        if sinceRelease < config.transitionMinutes {
            let progress = sinceRelease / config.transitionMinutes
            return (lerp(config.bedtimeKelvin, config.dayKelvin, progress), .sunrise)
        }

        return (config.dayKelvin, .day)
    }

    private static func lerp(_ from: Double, _ to: Double, _ progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return from + (to - from) * p
    }

    /// Minutes from `a` forward (clockwise) to `b` on the 24h circle.
    private static func forwardDistance(from a: Double, to b: Double) -> Double {
        wrap(b - a)
    }

    private static func wrap(_ minutes: Double) -> Double {
        let r = minutes.truncatingRemainder(dividingBy: 1440)
        return r < 0 ? r + 1440 : r
    }
}
