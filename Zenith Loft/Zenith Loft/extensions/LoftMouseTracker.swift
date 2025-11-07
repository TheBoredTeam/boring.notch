import SwiftUI

extension NSScreen {
    static var loftScreenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}
