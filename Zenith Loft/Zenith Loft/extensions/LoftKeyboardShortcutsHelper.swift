import KeyboardShortcuts
import SwiftUI
import Carbon

extension View {
    public func loftKeyboardShortcut(_ shortcut: KeyboardShortcuts.Name) -> some View {
        if let shortcut = shortcut.shortcut {
            if let keyEquivalent = shortcut.loftToKeyEquivalent() {
                return AnyView(self.keyboardShortcut(keyEquivalent, modifiers: shortcut.loftToEventModifiers()))
            }
        }
        return AnyView(self)
    }
}

extension KeyboardShortcuts.Shortcut {
    func loftToKeyEquivalent() -> KeyEquivalent? {
        let carbonKeyCode = UInt16(self.carbonKeyCode)
        let maxNameLength = 4
        var nameBuffer = [UniChar](repeating: 0, count: maxNameLength)
        var nameLength = 0

        let modifierKeys = UInt32(alphaLock >> 8) & 0xFF // Caps Lock
        var deadKeys: UInt32 = 0
        let keyboardType = UInt32(LMGetKbdType())

        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            NSLog("Could not get keyboard layout data")
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        let osStatus = layoutData.withUnsafeBytes {
            UCKeyTranslate(
                $0.bindMemory(to: UCKeyboardLayout.self).baseAddress,
                carbonKeyCode,
                UInt16(kUCKeyActionDown),
                modifierKeys,
                keyboardType,
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeys,
                maxNameLength,
                &nameLength,
                &nameBuffer
            )
        }
        guard osStatus == noErr else {
            NSLog("Code: 0x%04X  Status: %+i", carbonKeyCode, osStatus)
            return nil
        }

        return KeyEquivalent(Character(String(utf16CodeUnits: nameBuffer, count: nameLength)))
    }

    func loftToEventModifiers() -> SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []

        if self.modifiers.contains(NSEvent.ModifierFlags.command) {
            modifiers.update(with: .command)
        }
        if self.modifiers.contains(NSEvent.ModifierFlags.control) {
            modifiers.update(with: .control)
        }
        if self.modifiers.contains(NSEvent.ModifierFlags.option) {
            modifiers.update(with: .option)
        }
        if self.modifiers.contains(NSEvent.ModifierFlags.shift) {
            modifiers.update(with: .shift)
        }
        if self.modifiers.contains(NSEvent.ModifierFlags.capsLock) {
            modifiers.update(with: .capsLock)
        }
        if self.modifiers.contains(NSEvent.ModifierFlags.numericPad) {
            modifiers.update(with: .numericPad)
        }

        return modifiers
    }
}
