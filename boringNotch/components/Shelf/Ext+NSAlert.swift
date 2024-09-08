//
//  Ext+NSAlert.swift
//  NotchDrop
//
//  Created by 秋星桥 on 2024/7/9.
//

import Cocoa

extension NSAlert {
    static func popError(_ error: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Error", comment: "")
        alert.alertStyle = .critical
        alert.informativeText = error
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
    }

    static func popRestart(_ error: String, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Need Restart", comment: "")
        alert.alertStyle = .critical
        alert.informativeText = error
        alert.addButton(withTitle: NSLocalizedString("Exit", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            completion()
        }
    }

    static func popError(_ error: Error) {
        popError(error.localizedDescription)
    }
}
