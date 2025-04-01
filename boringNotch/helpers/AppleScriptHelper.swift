//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander Greco on 2025-03-29.
//

import Foundation

class AppleScriptHelper {
    class func execute(_ scriptText: String) -> NSAppleEventDescriptor? {
        let script = NSAppleScript(source: scriptText)
        var error: NSDictionary?
        
        guard let descriptor = script?.executeAndReturnError(&error) else {
            print("AppleScript error: \(error?.description ?? "Unknown error")")
            return nil
        }
        
        return descriptor
    }
    
    class func executeVoid(_ scriptText: String) {
        _ = execute(scriptText) // Ignore result for commands without return values
    }
}
