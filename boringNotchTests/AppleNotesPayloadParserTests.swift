import XCTest

@testable import boringNotch

final class AppleNotesPayloadParserTests: XCTestCase {
    func testParsesRecordsAndMarksManagedNotes() {
        let payload = [
            "remote-1\u{001F}Imported\u{001F}1.7E+9\u{001F}1,8E+9\u{001F}Read only\u{001F}iCloud",
            "local-1\u{001F}Managed\u{001F}150\u{001F}250\u{001F}Editable\u{001F}On My Mac"
        ].joined(separator: "\u{001E}")

        let notes = AppleNotesPayloadParser.parse(
            payload,
            managedIDs: ["local-1"],
            pinnedIDs: ["remote-1"],
            colorOverrides: ["remote-1": 4]
        )

        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first(where: { $0.id == "remote-1" })?.isManagedByBoringNotch, false)
        XCTAssertEqual(notes.first(where: { $0.id == "local-1" })?.isManagedByBoringNotch, true)
        XCTAssertEqual(notes.first(where: { $0.id == "remote-1" })?.isPinned, true)
        XCTAssertEqual(notes.first(where: { $0.id == "remote-1" })?.colorIndex, 4)
        XCTAssertEqual(notes.first(where: { $0.id == "remote-1" })?.creationDate.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(notes.first(where: { $0.id == "remote-1" })?.modificationDate.timeIntervalSince1970, 1_800_000_000)
        XCTAssertEqual(notes.first(where: { $0.id == "local-1" })?.modificationDate.timeIntervalSince1970, 250)
    }

    func testIgnoresMalformedRecords() {
        let payload = [
            "incomplete\u{001F}record",
            "valid\u{001F}Title\u{001F}10\u{001F}20\u{001F}Body\u{001F}Account"
        ].joined(separator: "\u{001E}")

        let notes = AppleNotesPayloadParser.parse(payload, managedIDs: [])

        XCTAssertEqual(notes.map(\.id), ["valid"])
    }

    func testUsesUntitledLabelForBlankTitles() {
        let payload = "note\u{001F}   \u{001F}10\u{001F}20\u{001F}Body\u{001F}Account"

        let notes = AppleNotesPayloadParser.parse(payload, managedIDs: [])

        XCTAssertEqual(notes.first?.title, String(localized: "Untitled Note"))
    }

    func testCanFilterImportedNotesUsingManagedState() {
        let payload = [
            "remote\u{001F}Imported\u{001F}10\u{001F}20\u{001F}Body\u{001F}iCloud",
            "managed\u{001F}Managed\u{001F}10\u{001F}20\u{001F}Body\u{001F}iCloud"
        ].joined(separator: "\u{001E}")

        let notes = AppleNotesPayloadParser.parse(payload, managedIDs: ["managed"])
            .filter(\.isManagedByBoringNotch)

        XCTAssertEqual(notes.map(\.id), ["managed"])
    }
}
