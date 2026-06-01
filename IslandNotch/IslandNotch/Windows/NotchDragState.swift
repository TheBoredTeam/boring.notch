//  NotchDragState.swift
//  IslandNotch
//
//  Purpose: Transient, observable "a drag is over the notch" signal. Set by
//           NotchController when the AppKit DropCatcher's drag session enters the
//           notch (no global mouse monitor) and read by the shelf so it can present
//           a clear "drop your image here" affordance the instant the notch expands.
//  Layer: Window

import Observation

@MainActor
@Observable
final class NotchDragState {
    /// True while a drag is hovering the notch's catch zone — drives the prominent
    /// drop affordance in the expanded shelf.
    var isInbound = false
}
