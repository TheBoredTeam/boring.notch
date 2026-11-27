//
//  SettingsSearchField.swift
//  boringNotch
//

import AppKit
import SwiftUI

// `NSSearchField` instead of `.searchable`: on macOS 15 `.searchable` puts the field inside the sidebar
// list as a row, so it cannot be spaced from the rows below it, and focusing it from code needs macOS 15.
struct SettingsSearchField: NSViewRepresentable {
    @Binding var text: String
    // Changing this value moves keyboard focus into the field.
    let focusRequest: Int
    let onMoveToResults: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        // The action also fires when the clear button or Esc empties the field.
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchTextChanged(_:))
        field.sendsSearchStringImmediately = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            // The field may not be in a window yet during the first update.
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SettingsSearchField
        var handledFocusRequest: Int

        init(_ parent: SettingsSearchField) {
            self.parent = parent
            handledFocusRequest = parent.focusRequest
        }

        @objc func searchTextChanged(_ sender: NSSearchField) {
            updateText(from: sender)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.moveDown(_:))
                || commandSelector == #selector(NSResponder.insertNewline(_:))
            else { return false }
            parent.onMoveToResults()
            return true
        }

        private func updateText(from field: NSSearchField) {
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }
    }
}
