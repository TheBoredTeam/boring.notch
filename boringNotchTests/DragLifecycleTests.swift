import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import boringNotch

final class DragLifecycleTests: XCTestCase {
    func testMixedRepresentationsAcceptUsableContentAndRejectEmpty() {
        XCTAssertTrue(ShelfTransferTypes.supports(typeIdentifiers: ["com.example.private-drag", UTType.fileURL.identifier]))
        XCTAssertTrue(ShelfTransferTypes.supports(typeIdentifiers: [UTType.url.identifier]))
        XCTAssertTrue(ShelfTransferTypes.supports(typeIdentifiers: [UTType.utf8PlainText.identifier]))
        XCTAssertFalse(ShelfTransferTypes.supports(typeIdentifiers: []))
        XCTAssertFalse(ShelfTransferTypes.supports(typeIdentifiers: ["com.example.private-drag"]))
        XCTAssertFalse(ShelfTransferTypes.supports([NSItemProvider]()))
    }

    func testEnterExitMouseUpAndDuplicateEndClearOnce() {
        let state = DropInteractionState()
        state.detectorTargeting = true
        state.detectorTargeting = false
        state.finish()
        state.finish()
        XCTAssertFalse(state.anyDropZoneTargeting)
        XCTAssertFalse(state.dropEvent)
        XCTAssertEqual(state.finishRevision, 1)
    }

    func testNativeDestinationKeepsDragAliveWhenGlobalRegionExits() {
        let state = DropInteractionState()
        state.detectorTargeting = true
        state.generalDropTargeting = true
        state.dragDetectorTargeting = true
        state.detectorTargeting = false
        XCTAssertTrue(state.anyDropZoneTargeting)
        state.finish(dropped: true)
        state.finish() // trailing mouse-up must not undo the accepted drop
        XCTAssertTrue(state.dropEvent)
        XCTAssertFalse(state.anyDropZoneTargeting)
        XCTAssertEqual(state.finishRevision, 1)
    }

    func testCancelDisableAndScreenRemovalClearEveryTarget() {
        for _ in 0..<100 {
            let state = DropInteractionState()
            state.detectorTargeting = true
            state.generalDropTargeting = true
            state.dragDetectorTargeting = true
            state.dropZoneTargeting = true
            state.finish()
            XCTAssertFalse(state.anyDropZoneTargeting)
            XCTAssertFalse(state.nativeDestinationTargeting)
            XCTAssertEqual(state.finishRevision, 1)
        }
    }

    func testNewDragDoesNotInheritPreviousSuccessfulDrop() {
        let state = DropInteractionState()
        state.dragDetectorTargeting = true
        state.finish(dropped: true)
        state.detectorTargeting = true
        XCTAssertFalse(state.dropEvent)
        state.finish()
        XCTAssertFalse(state.dropEvent)
        XCTAssertEqual(state.finishRevision, 2)
    }
}
