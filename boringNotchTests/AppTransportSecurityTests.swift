import Foundation
import XCTest

final class AppTransportSecurityTests: XCTestCase {
    func testInfoPlistAllowsLocalNetworkingWithoutArbitraryLoads() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("boringNotch/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        let transportSecurity = try XCTUnwrap(
            plist["NSAppTransportSecurity"] as? [String: Any]
        )

        XCTAssertNotEqual(transportSecurity["NSAllowsArbitraryLoads"] as? Bool, true)
        XCTAssertEqual(transportSecurity["NSAllowsLocalNetworking"] as? Bool, true)
    }
}
