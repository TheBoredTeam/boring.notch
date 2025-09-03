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
		didSet { updateFocus()
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
//		if notchIsOpen {
//		} else {
//			if settingsIsOpen {
//				NSApp.keyWindow?.makeFirstResponder(NSResponder())
//			}
//		}
//
//		if settingsIsOpen {
//			// settings is open, push to front
//			// do nothing for now
////			NSApp.keyWindow?.makeFirstResponder(NSResponder())
//		} else {
//			// settings is not open, normal routing
//			if notesTabIsOpen {
//				// when switching to notes tab
//				NSApp.activate(ignoringOtherApps: true)
//			} else {
//				// when switching away from notes tab, reverts focus to foreground app
//				NSApp.hide(nil)
//				NSApp.keyWindow?.makeFirstResponder(nil)
//			}
//		}


		if notchIsOpen {

		} else {
			if settingsIsOpen {

			} else {

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
