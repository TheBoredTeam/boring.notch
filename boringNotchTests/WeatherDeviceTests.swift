import XCTest
@testable import boringNotch

final class WeatherDeviceTests: XCTestCase {
    func testCurrentForecastWithoutHourlyData() throws {
        let data = Data(#"{"current":{"temperature_2m":12.3,"apparent_temperature":10.2,"weather_code":3,"wind_speed_10m":4.5,"is_day":0}}"#.utf8)
        let value = try JSONDecoder().decode(FeatureForecast.self, from: data)
        XCTAssertEqual(value.current.temperature_2m, 12.3)
        XCTAssertNil(value.hourly)
    }
    func testConnectionChangesAndRepeatedSnapshots() {
        let device = FeatureDevice(id: "test", name: "Headphones", connected: true)
        XCTAssertEqual(FeatureLayout.transitions(old: [], new: [device]).count, 1)
        XCTAssertTrue(FeatureLayout.transitions(old: [device], new: [device]).isEmpty)
        let disconnected = FeatureDevice(id: device.id, name: device.name, connected: false)
        let changes = FeatureLayout.transitions(old: [device], new: [disconnected])
        XCTAssertEqual(changes.count, 1)
        XCTAssertFalse(changes[0].1)
    }
    func testCitySelectionRoundTrip() throws {
        let place = FeaturePlace(id: 1, name: "Test City", latitude: 45, longitude: 39, country: nil, admin1: nil)
        XCTAssertEqual(try JSONDecoder().decode(FeaturePlace.self, from: JSONEncoder().encode(place)), place)
    }
}
