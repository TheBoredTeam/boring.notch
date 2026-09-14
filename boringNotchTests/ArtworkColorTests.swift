//
//  ArtworkColorTests.swift
//  boringNotchTests
//

import AppKit
import XCTest
@testable import boringNotch

@MainActor
final class ArtworkColorTests: XCTestCase {
    private func image(width: Int, height: Int, color: CGColor) throws -> NSImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Interpret fixture components in the explicit source profile, avoiding
        // an implicit Generic RGB -> sRGB conversion in CGColor(red:...).
        let sourceColor = try XCTUnwrap(CGColor(colorSpace: space, components: try XCTUnwrap(color.components)))
        context.setFillColor(sourceColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: width, height: height))
    }

    func testLargeOpaqueArtworkKeepsItsColor() async throws {
        let artwork = try image(width: 2400, height: 1600, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let sampled = await artwork.averageColor()
        let color = try XCTUnwrap(sampled)
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.02)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 0.02)
        XCTAssertEqual(color.blueComponent, 0, accuracy: 0.02)
    }

    func testTransparentArtworkKeepsNeutralBrightnessFallback() async throws {
        let artwork = try image(width: 512, height: 512, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        let sampled = await artwork.averageColor()
        let color = try XCTUnwrap(sampled)
        XCTAssertEqual(color.redComponent, 0.5, accuracy: 0.02)
        XCTAssertEqual(color.greenComponent, 0.5, accuracy: 0.02)
        XCTAssertEqual(color.blueComponent, 0.5, accuracy: 0.02)
    }

    func testNarrowTranslucentArtworkKeepsPremultipliedColor() async throws {
        let artwork = try image(width: 1, height: 2000, color: CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
        let sampled = await artwork.averageColor()
        let color = try XCTUnwrap(sampled)
        XCTAssertEqual(color.redComponent, 0.5, accuracy: 0.02)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 0.02)
        XCTAssertEqual(color.blueComponent, 0, accuracy: 0.02)
    }
}
