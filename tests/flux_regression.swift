//
//  flux_regression.swift
//  Regression checks for the Flux night shift feature: color math,
//  sunrise/sunset calculation, and the schedule engine.
//
//  Run via: make test-flux (compiles against the Flux sources directly)
//

import Foundation

func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message) — expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertClose(_ actual: Double, _ expected: Double, tolerance: Double, _ message: String) {
    if abs(actual - expected) > tolerance {
        fputs("Assertion failed: \(message) — expected \(expected) ± \(tolerance), got \(actual)\n", stderr)
        exit(1)
    }
}

@main
struct FluxRegressionRunner {
    static func main() {
        testColorMath()
        testSolarCalculator()
        testScheduleEngine()
        print("flux-regression-pass")
    }

    // MARK: - Color math

    static func testColorMath() {
        let day = FluxColorMath.whitePoint(kelvin: 6500)
        assertTrue(day.red >= 0.95 && day.green >= 0.95 && day.blue >= 0.95,
                   "6500K should be near-white on all channels")
        assertClose(max(day.red, max(day.green, day.blue)), 1.0, tolerance: 0.0001,
                    "brightest channel is normalized to 1")

        for kelvin in stride(from: 1000.0, through: 6500.0, by: 100.0) {
            let rgb = FluxColorMath.whitePoint(kelvin: kelvin)
            for (channel, value) in [("red", rgb.red), ("green", rgb.green), ("blue", rgb.blue)] {
                assertTrue(value >= 0 && value <= 1,
                           "\(channel) in range at \(kelvin)K (got \(value))")
            }
        }

        // Warm temperatures are red-dominant
        assertClose(FluxColorMath.whitePoint(kelvin: 1900).red, 1.0, tolerance: 0.0001,
                    "1900K is red-dominant")
        assertClose(FluxColorMath.whitePoint(kelvin: 3400).red, 1.0, tolerance: 0.0001,
                    "3400K is red-dominant")

        // Blue attenuation increases monotonically as temperature drops
        var previousBlue = -1.0
        for kelvin in [1900.0, 2300.0, 3400.0, 5000.0, 6500.0] {
            let blue = FluxColorMath.whitePoint(kelvin: kelvin).blue
            assertTrue(blue > previousBlue, "blue increases with kelvin (\(kelvin)K)")
            previousBlue = blue
        }
        assertTrue(FluxColorMath.whitePoint(kelvin: 1900).blue < 0.4,
                   "1900K strongly attenuates blue")

        // Out-of-range inputs clamp instead of misbehaving
        assertEqual(FluxColorMath.whitePoint(kelvin: 500), FluxColorMath.whitePoint(kelvin: 1000),
                    "kelvin clamps at the low end")
        assertEqual(FluxColorMath.whitePoint(kelvin: 20000), FluxColorMath.whitePoint(kelvin: 6500),
                    "kelvin clamps at the high end")

        // Human-readable descriptors
        assertEqual(FluxColorMath.descriptor(kelvin: 6500), "Normal (Daylight)", "6500K descriptor")
        assertEqual(FluxColorMath.descriptor(kelvin: 10000), "Normal (Daylight)", "descriptor clamps high")
        assertEqual(FluxColorMath.descriptor(kelvin: 5000), "5000K (Sunlight)", "5000K descriptor")
        assertEqual(FluxColorMath.descriptor(kelvin: 3400), "3400K (Halogen)", "3400K descriptor")
        assertEqual(FluxColorMath.descriptor(kelvin: 2700), "2700K (Incandescent)", "2700K descriptor")
        assertEqual(FluxColorMath.descriptor(kelvin: 2300), "2300K (Dim Incandescent)", "2300K descriptor")
        assertEqual(FluxColorMath.descriptor(kelvin: 1900), "1900K (Candle)", "1900K descriptor")
        assertEqual(FluxColorMath.descriptor(kelvin: 6449), "6449K (Daylight)", "just below the Normal cutoff")
        assertEqual(FluxColorMath.descriptor(kelvin: 6450), "Normal (Daylight)", "Normal cutoff boundary")
    }

    // MARK: - Solar calculator

    static func testSolarCalculator() {
        // New York City, summer solstice 2024 (EDT, UTC-4): sunrise 5:25, sunset 20:31
        let nyc = SolarCalculator.events(
            year: 2024, month: 6, day: 21,
            latitude: 40.7128, longitude: -74.0060, timeZoneOffsetMinutes: -240)
        guard case .regular(let nycRise, let nycSet) = nyc else {
            fputs("Assertion failed: NYC June solstice should have sunrise/sunset\n", stderr)
            exit(1)
        }
        assertClose(nycRise, 5 * 60 + 25, tolerance: 10, "NYC summer solstice sunrise")
        assertClose(nycSet, 20 * 60 + 31, tolerance: 10, "NYC summer solstice sunset")

        // London, winter solstice 2024 (GMT): sunrise 8:04, sunset 15:53
        let london = SolarCalculator.events(
            year: 2024, month: 12, day: 21,
            latitude: 51.5074, longitude: -0.1278, timeZoneOffsetMinutes: 0)
        guard case .regular(let lonRise, let lonSet) = london else {
            fputs("Assertion failed: London winter solstice should have sunrise/sunset\n", stderr)
            exit(1)
        }
        assertClose(lonRise, 8 * 60 + 4, tolerance: 10, "London winter solstice sunrise")
        assertClose(lonSet, 15 * 60 + 53, tolerance: 10, "London winter solstice sunset")

        // Quito (equator), equinox 2024 (UTC-5): roughly 6:18 / 18:24
        let quito = SolarCalculator.events(
            year: 2024, month: 3, day: 20,
            latitude: -0.1807, longitude: -78.4675, timeZoneOffsetMinutes: -300)
        guard case .regular(let quitoRise, let quitoSet) = quito else {
            fputs("Assertion failed: Quito equinox should have sunrise/sunset\n", stderr)
            exit(1)
        }
        assertClose(quitoRise, 6 * 60 + 18, tolerance: 10, "Quito equinox sunrise")
        assertClose(quitoSet, 18 * 60 + 24, tolerance: 10, "Quito equinox sunset")

        // Tromsø, Norway: polar night in December, midnight sun in June
        assertEqual(
            SolarCalculator.events(
                year: 2024, month: 12, day: 21,
                latitude: 69.6492, longitude: 18.9553, timeZoneOffsetMinutes: 60),
            .polarNight, "Tromsø December is polar night")
        assertEqual(
            SolarCalculator.events(
                year: 2024, month: 6, day: 21,
                latitude: 69.6492, longitude: 18.9553, timeZoneOffsetMinutes: 120),
            .polarDay, "Tromsø June is polar day")
    }

    // MARK: - Schedule engine

    static func testScheduleEngine() {
        // Sunrise 5:30, sunset 20:15, bedtime 23:00, 60 min wind-down/transitions
        let config = FluxScheduleConfig(
            dayKelvin: 6500, sunsetKelvin: 3400, bedtimeKelvin: 2300,
            bedtimeMinutes: 23 * 60, windDownMinutes: 60, transitionMinutes: 60)
        let solar = SolarDayEvents.regular(sunriseMinutes: 5 * 60 + 30, sunsetMinutes: 20 * 60 + 15)

        func at(_ hour: Int, _ minute: Int, _ s: SolarDayEvents? = nil) -> (kelvin: Double, phase: FluxPhase) {
            FluxScheduleEngine.evaluate(
                nowMinutes: Double(hour * 60 + minute), solar: s ?? solar, config: config)
        }

        // Midday: full daylight temperature
        let noon = at(12, 0)
        assertEqual(noon.kelvin, 6500, "noon is day kelvin")
        assertEqual(noon.phase, .day, "noon phase is day")

        // Halfway through the sunset transition
        let dusk = at(20, 45)
        assertClose(dusk.kelvin, 4950, tolerance: 1, "halfway through sunset transition")
        assertEqual(dusk.phase, .sunset, "dusk phase is sunset")

        // Settled evening, before wind-down
        let evening = at(21, 45)
        assertEqual(evening.kelvin, 3400, "evening holds sunset kelvin")
        assertEqual(evening.phase, .evening, "evening phase")

        // Wind-down gets monotonically darker as bedtime approaches
        let halfway = at(22, 30)
        assertClose(halfway.kelvin, 2850, tolerance: 1, "halfway through wind-down")
        assertEqual(halfway.phase, .windDown, "wind-down phase")
        var previous = at(22, 1).kelvin
        for minute in [15, 30, 45, 59] {
            let kelvin = at(22, minute).kelvin
            assertTrue(kelvin < previous, "wind-down darkens towards bedtime (22:\(minute))")
            previous = kelvin
        }

        // At and after bedtime, hold the bedtime temperature through the night
        assertEqual(at(23, 0).kelvin, 2300, "bedtime reaches bedtime kelvin")
        assertEqual(at(23, 0).phase, .bedtime, "bedtime phase")
        assertEqual(at(3, 0).kelvin, 2300, "3 AM stays at bedtime kelvin")
        assertEqual(at(3, 0).phase, .bedtime, "3 AM phase is bedtime")

        // Sunrise releases back toward day, never brighter than the solar ramp
        let dawn = at(5, 45)
        assertEqual(dawn.phase, .sunrise, "dawn phase is sunrise")
        assertClose(dawn.kelvin, 3350, tolerance: 1, "dawn releases from bedtime kelvin")
        assertEqual(at(7, 0).kelvin, 6500, "post-sunrise is day kelvin")

        // Bedtime after midnight wraps correctly
        var lateConfig = config
        lateConfig.bedtimeMinutes = 30 // 00:30
        let lateWind = FluxScheduleEngine.evaluate(nowMinutes: 23 * 60 + 50, solar: solar, config: lateConfig)
        assertEqual(lateWind.phase, .windDown, "23:50 is wind-down for a 00:30 bedtime")
        assertClose(lateWind.kelvin, 3400 + (2300 - 3400) / 3, tolerance: 1,
                    "a third into the post-midnight wind-down")
        let lateNight = FluxScheduleEngine.evaluate(nowMinutes: 60, solar: solar, config: lateConfig)
        assertEqual(lateNight.kelvin, 2300, "1 AM is bedtime for a 00:30 bedtime")

        // A bedtime before sunset still wins over daylight
        var earlyConfig = config
        earlyConfig.bedtimeMinutes = 16 * 60
        let earlyBed = FluxScheduleEngine.evaluate(nowMinutes: 17 * 60, solar: solar, config: earlyConfig)
        assertEqual(earlyBed.kelvin, 2300, "bedtime before sunset overrides daylight")
        assertEqual(earlyBed.phase, .bedtime, "bedtime-before-sunset phase")

        // ...and its wind-down starts from the daylight temperature, with no
        // cliff at the window boundary (15:00 for a 16:00 bedtime)
        let windEntry = FluxScheduleEngine.evaluate(nowMinutes: 15 * 60, solar: solar, config: earlyConfig)
        assertClose(windEntry.kelvin, 6500, tolerance: 1, "daytime wind-down enters continuously")
        var previousEarly = windEntry.kelvin
        for minute in [10, 20, 30, 40, 50, 59] {
            let kelvin = FluxScheduleEngine.evaluate(
                nowMinutes: Double(15 * 60 + minute), solar: solar, config: earlyConfig).kelvin
            assertTrue(kelvin < previousEarly, "daytime wind-down decreases (15:\(minute))")
            previousEarly = kelvin
        }

        // Default-style bedtime with a late sunset: the wind-down window starts
        // inside the sunset transition and must hand off continuously
        let lateSunset = SolarDayEvents.regular(sunriseMinutes: 4 * 60 + 45, sunsetMinutes: 21 * 60 + 21)
        let handoff = FluxScheduleEngine.evaluate(nowMinutes: 22 * 60, solar: lateSunset, config: config)
        let solarAtHandoff = 6500 + (3400 - 6500) * (39.0 / 60.0)
        assertClose(handoff.kelvin, solarAtHandoff, tolerance: 1,
                    "wind-down inside the sunset transition starts at the solar value")
        let beforeHandoff = FluxScheduleEngine.evaluate(nowMinutes: 22 * 60 - 1, solar: lateSunset, config: config)
        assertTrue(abs(beforeHandoff.kelvin - handoff.kelvin) < 120,
                   "no cliff crossing the wind-down boundary (late sunset)")

        // Bedtime after sunrise (night-shift worker): the hold is capped at a
        // night's sleep instead of pinning the screen warm all day
        var morningConfig = config
        morningConfig.bedtimeMinutes = 6 * 60 // 06:00, sunrise is 05:30
        let asleep = FluxScheduleEngine.evaluate(nowMinutes: 12 * 60, solar: solar, config: morningConfig)
        assertEqual(asleep.kelvin, 2300, "morning bedtime holds through the sleep window")
        let awake = FluxScheduleEngine.evaluate(nowMinutes: 16 * 60 + 30, solar: solar, config: morningConfig)
        assertEqual(awake.kelvin, 6500, "morning bedtime releases to day after the capped hold")
        assertEqual(awake.phase, .day, "post-release phase is day")

        // Zero wind-down doesn't divide by zero and still hits bedtime kelvin
        var instantConfig = config
        instantConfig.windDownMinutes = 0
        let instant = FluxScheduleEngine.evaluate(nowMinutes: 23 * 60, solar: solar, config: instantConfig)
        assertEqual(instant.kelvin, 2300, "zero wind-down reaches bedtime kelvin at bedtime")

        // No location: falls back to 07:00/19:00
        let fallbackNoon = FluxScheduleEngine.evaluate(nowMinutes: 12 * 60, solar: nil, config: config)
        assertEqual(fallbackNoon.kelvin, 6500, "fallback noon is day kelvin")
        let fallbackNight = FluxScheduleEngine.evaluate(nowMinutes: 20 * 60 + 30, solar: nil, config: config)
        assertEqual(fallbackNight.kelvin, 3400, "fallback evening uses sunset kelvin")

        // Polar cases
        let polarDayNoon = at(12, 0, SolarDayEvents.polarDay)
        assertEqual(polarDayNoon.kelvin, 6500, "polar day noon stays at day kelvin")
        let polarDayBed = at(23, 30, SolarDayEvents.polarDay)
        assertEqual(polarDayBed.kelvin, 2300, "bedtime still applies during polar day")
        let polarNightNoon = at(12, 0, SolarDayEvents.polarNight)
        assertEqual(polarNightNoon.kelvin, 3400, "polar night noon uses sunset kelvin")
        assertEqual(polarNightNoon.phase, .evening, "polar night phase is evening")
    }
}
