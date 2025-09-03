//
//  FocusManager.swift
//  boringNotch
//
//  Created by Adon Omeri on 3/9/2025.
//

import AppKit

@MainActor
final class FocusManager: ObservableObject {
	static let shared = FocusManager()

	private init() {}

	@Published var settingsIsOpen: Bool = false {
		didSet { updateFocus()
			print("settingsIsOpen: \(settingsIsOpen)")

		}
	}

	@Published var notesTabIsOpen: Bool = false {
		didSet {
			updateFocus()
			print("notesTabIsOpen: \(notesTabIsOpen)")

		}
	}

	@Published var notchIsOpen: Bool = false {
		didSet { updateFocus()
			print("notchIsOpen: \(notchIsOpen)")
		}
	}

	var editorCanFocus: Bool {
		notesTabIsOpen
	}

	@Published var resignToggle = false

	@Published var frontToggle = false


	var canBecomeKey: Bool {
		if settingsIsOpen {
			return true
		} else {
			if notchIsOpen {
				if notesTabIsOpen {
					return true
				} else {
					return false
				}
			} else {
				return false
			}
		}
	}

	private func updateFocus() {

		if notchIsOpen {
			if settingsIsOpen {
				if notesTabIsOpen {
					NSApp.keyWindow?.makeFirstResponder(NSResponder.init())
					frontToggle.toggle()
				} else {
					resignToggle.toggle()
				}
			} else {
				if notesTabIsOpen {
					NSApp.keyWindow?.makeFirstResponder(NSResponder.init())
					frontToggle.toggle()
				} else {
					NSApp.hide(nil)
					NSApp.keyWindow?.makeFirstResponder(nil)

						resignToggle.toggle()

				}
			}
		} else {
			if settingsIsOpen {
				NSApp.keyWindow?.makeFirstResponder(NSResponder.init())
				frontToggle.toggle()
			} else {
				NSApp.hide(nil)
				NSApp.keyWindow?.makeFirstResponder(nil)
				resignToggle.toggle()
			}
		}


	}


}

// .onChange(of: coordinator.currentView) {
//	if coordinator.currentView != .notes {
//		focusManager.notesTabIsOpen = true
//
//		NSApp.hide(nil)
//
//		NSApp.keyWindow?.makeFirstResponder(nil)
//	} else {
//		focusManager.notesTabIsOpen = false
//
//		NSApp.keyWindow?.makeFirstResponder(nil)
//	}
// }
