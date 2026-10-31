//
//  DropInteractionState.swift
//  boringNotch
//

import Observation

@Observable
final class DropInteractionState {
    var dragDetectorTargeting = false
    var generalDropTargeting = false
    var dropZoneTargeting = false
    var dropEvent = false

    var anyDropZoneTargeting: Bool {
        dragDetectorTargeting || generalDropTargeting || dropZoneTargeting
    }

    func reset() {
        dragDetectorTargeting = false
        generalDropTargeting = false
        dropZoneTargeting = false
        dropEvent = false
    }
}
