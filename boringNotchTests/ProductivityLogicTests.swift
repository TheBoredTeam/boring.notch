import XCTest
@testable import boringNotch

final class ProductivityLogicTests: XCTestCase {
    func testDownloadBrowserAndDisplayNameDetection() {
        XCTAssertEqual(DownloadFileInspector.browser(for: URL(fileURLWithPath: "/tmp/archive.zip.download")), .safari)
        XCTAssertEqual(DownloadFileInspector.browser(for: URL(fileURLWithPath: "/tmp/movie.mp4.crdownload")), .chromium)
        XCTAssertEqual(DownloadFileInspector.browser(for: URL(fileURLWithPath: "/tmp/image.png.part")), .firefox)
        XCTAssertNil(DownloadFileInspector.browser(for: URL(fileURLWithPath: "/tmp/finished.zip")))
        XCTAssertEqual(
            DownloadFileInspector.displayName(for: URL(fileURLWithPath: "/tmp/ARCHIVE.ZIP.DOWNLOAD")),
            "ARCHIVE.ZIP"
        )
    }

    func testSafariDownloadPackageIncludesNestedFileBytes() throws {
        let fileManager = FileManager.default
        let package = fileManager.temporaryDirectory
            .appendingPathComponent("boring-notch-tests-\(UUID().uuidString).download", isDirectory: true)
        let nested = package.appendingPathComponent("nested", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: package) }

        try Data(repeating: 0xA5, count: 128).write(to: package.appendingPathComponent("first.bin"))
        try Data(repeating: 0x5A, count: 384).write(to: nested.appendingPathComponent("second.bin"))

        XCTAssertEqual(DownloadFileInspector.bytesReceived(at: package, isDirectory: true), 512)
    }

    func testClipboardPrivacyFilterRejectsSecretMaterial() {
        XCTAssertTrue(ClipboardPrivacyFilter.isSensitivePasteboardType("org.nspasteboard.TransientType"))
        XCTAssertTrue(ClipboardPrivacyFilter.isSensitivePasteboardType("com.agilebits.onepassword"))
        XCTAssertTrue(ClipboardPrivacyFilter.looksSensitive("-----BEGIN PRIVATE KEY-----\nmaterial"))
        XCTAssertTrue(ClipboardPrivacyFilter.looksSensitive("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertTrue(ClipboardPrivacyFilter.looksSensitive("ghp_abcdefghijklmnopqrstuvwxyz1234567890"))
        XCTAssertFalse(ClipboardPrivacyFilter.looksSensitive("A harmless clipboard note"))
    }

    func testMeetingLinkDetectorUsesHTTPSAllowlist() {
        XCTAssertEqual(
            MeetingLinkDetector.find(in: ["Join at https://acme.zoom.us/j/123456"]),
            URL(string: "https://acme.zoom.us/j/123456")
        )
        XCTAssertEqual(
            MeetingLinkDetector.find(in: ["https://meet.google.com/abc-defg-hij"]),
            URL(string: "https://meet.google.com/abc-defg-hij")
        )
        XCTAssertNil(MeetingLinkDetector.find(in: ["http://zoom.us/j/123456"]))
        XCTAssertNil(MeetingLinkDetector.find(in: ["https://zoom.us.attacker.example/j/123456"]))
    }
}
