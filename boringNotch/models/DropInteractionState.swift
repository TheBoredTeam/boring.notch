//
//  DropInteractionState.swift
//  boringNotch
//

import Observation

@Observable
final class DropInteractionState {
    var dragDetectorTargeting = false { didSet { if dragDetectorTargeting { sessionActive = true; dropEvent = false } } }
    var generalDropTargeting = false { didSet { if generalDropTargeting { sessionActive = true; dropEvent = false } } }
    var dropZoneTargeting = false { didSet { if dropZoneTargeting { sessionActive = true; dropEvent = false } } }
    var dropEvent = false
    private(set) var finishRevision = 0
    private var sessionActive = false

    var nativeDestinationTargeting: Bool {
        generalDropTargeting || dropZoneTargeting || dragDetectorTargeting
    }

    var detectorTargeting = false { didSet { if detectorTargeting { sessionActive = true; dropEvent = false } } }

    /// Every terminal path clears the same state. A second terminal callback
    /// (for example mouse-up after performDrop) must not undo a successful drop.
    func finish(dropped: Bool = false) {
        guard sessionActive || dropped else { return }
        sessionActive = false
        dropEvent = dropped
        detectorTargeting = false
        dragDetectorTargeting = false
        generalDropTargeting = false
        dropZoneTargeting = false
        finishRevision += 1
    }

    var anyDropZoneTargeting: Bool {
        detectorTargeting || nativeDestinationTargeting
    }
}
