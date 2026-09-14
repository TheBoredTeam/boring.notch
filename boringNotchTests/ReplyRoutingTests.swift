//
//  ReplyRoutingTests.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest
@testable import boringNotch

final class ReplyRoutingTests: XCTestCase {
    func testWhatsAppReplyRemainsOneQueryValue() throws {
        let phone = "+15551234567"
        for text in [
            "Hello & goodbye+again #100% \"quoted\" 'single'",
            "&phone=999&text=injected#fragment",
            "नमस्ते 👋 café 中文\nsecond line",
            "%26 %2B + & # = ? /", ""
        ] {
            let url = try XCTUnwrap(SystemNotificationManager.whatsAppDraftURL(phone: phone, text: text))
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let items = try XCTUnwrap(components.queryItems)
            XCTAssertEqual(components.scheme, "whatsapp")
            XCTAssertEqual(components.host, "send")
            XCTAssertNil(components.fragment)
            XCTAssertEqual(items, [URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "text", value: text)])
        }
    }

    func testPlusSurvivesFormStyleQueryDecoding() throws {
        let text = "1+1 = 2 & +15551234567"
        let url = try XCTUnwrap(SystemNotificationManager.whatsAppDraftURL(phone: "+15550000000", text: text))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.percentEncodedQuery)
        XCTAssertFalse(query.contains("+"))
        var formDecoded = components
        formDecoded.percentEncodedQuery = query.replacingOccurrences(of: "+", with: " ")
        XCTAssertEqual(formDecoded.queryItems?.first(where: { $0.name == "text" })?.value, text)
    }
}
