//
//  SolarCalculator.swift
//  Gojo
//
//  Sunrise/sunset calculation (NOAA-style sunrise equation) for the Flux
//  night shift feature. Foundation-only so tests can compile it standalone.
//

import Foundation

enum SolarDayEvents: Equatable {
    /// Sunrise and sunset as minutes after local midnight (0..<1440).
    case regular(sunriseMinutes: Double, sunsetMinutes: Double)
    /// Sun never sets (e.g. arctic summer).
    case polarDay
    /// Sun never rises (e.g. arctic winter).
    case polarNight
}

enum SolarCalculator {
    /// Computes sunrise/sunset for a calendar date at the given coordinates.
    /// - Parameters:
    ///   - longitude: east-positive degrees
    ///   - timeZoneOffsetMinutes: offset from UTC (including DST) used to
    ///     express the result as local wall-clock minutes.
    static func events(
        year: Int,
        month: Int,
        day: Int,
        latitude: Double,
        longitude: Double,
        timeZoneOffsetMinutes: Double
    ) -> SolarDayEvents {
        let jdn = julianDayNumber(year: year, month: month, day: day)
        let n = Double(jdn) - 2451545.0 + 0.0008

        // Mean solar time at the observer's longitude
        let jStar = n - longitude / 360.0

        // Solar mean anomaly
        let m = normalizeDegrees(357.5291 + 0.98560028 * jStar)
        // Equation of the center
        let c = 1.9148 * sinDeg(m) + 0.0200 * sinDeg(2 * m) + 0.0003 * sinDeg(3 * m)
        // Ecliptic longitude
        let lambda = normalizeDegrees(m + c + 180 + 102.9372)

        // Solar transit (local true solar noon) as a Julian date
        let jTransit = 2451545.0 + jStar + 0.0053 * sinDeg(m) - 0.0069 * sinDeg(2 * lambda)

        // Declination of the sun
        let sinDelta = sinDeg(lambda) * sinDeg(23.4397)
        let cosDelta = cos(asin(sinDelta))

        // Hour angle, corrected for refraction and solar disc size (-0.833°)
        let latRad = latitude * .pi / 180
        let cosOmega = (sinDeg(-0.833) - sin(latRad) * sinDelta) / (cos(latRad) * cosDelta)

        if cosOmega > 1 { return .polarNight }
        if cosOmega < -1 { return .polarDay }

        let omegaDegrees = acos(cosOmega) * 180 / .pi
        let jRise = jTransit - omegaDegrees / 360
        let jSet = jTransit + omegaDegrees / 360

        return .regular(
            sunriseMinutes: localMinutes(julianDate: jRise, timeZoneOffsetMinutes: timeZoneOffsetMinutes),
            sunsetMinutes: localMinutes(julianDate: jSet, timeZoneOffsetMinutes: timeZoneOffsetMinutes)
        )
    }

    /// Integer Julian day number (valid for Gregorian calendar dates).
    private static func julianDayNumber(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    private static func localMinutes(julianDate: Double, timeZoneOffsetMinutes: Double) -> Double {
        let unixSeconds = (julianDate - 2440587.5) * 86400
        let localSeconds = unixSeconds + timeZoneOffsetMinutes * 60
        var minutes = (localSeconds / 60).truncatingRemainder(dividingBy: 1440)
        if minutes < 0 { minutes += 1440 }
        return minutes
    }

    private static func normalizeDegrees(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }

    private static func sinDeg(_ degrees: Double) -> Double {
        sin(degrees * .pi / 180)
    }
}
