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

	@Published var frontRequiringTabIsOpen: Bool = false {
		didSet {
			updateFocus()
			print("notesTabIsOpen: \(frontRequiringTabIsOpen)")

		}
	}

	@Published var notchIsOpen: Bool = false {
		didSet { updateFocus()
			print("notchIsOpen: \(notchIsOpen)")
		}
	}

	@Published var airDropFileDialogIsOpen = false {
		didSet {
			print("airDropFileDialogIsOpen: \(airDropFileDialogIsOpen)")
		}
	}

	var editorCanFocus: Bool {
		frontRequiringTabIsOpen
	}

	@Published var resignToggle = false

	@Published var frontToggle = false


	var canBecomeKey: Bool {
		if settingsIsOpen {
			return true
		} else {
			if notchIsOpen {
				if frontRequiringTabIsOpen {
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
				if frontRequiringTabIsOpen {
					NSApp.keyWindow?.makeFirstResponder(NSResponder.init())
					frontToggle.toggle()
				} else {
					resignToggle.toggle()
				}
			} else {
				if frontRequiringTabIsOpen {
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
