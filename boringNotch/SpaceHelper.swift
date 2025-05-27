import Foundation
import AppKit

class SpaceHelper {
    static func getCurrentSpaceNumber() -> Int? {
        // Get the active workspace
        let workspaceClass: AnyClass? = NSClassFromString("CGSWorkspace")
        guard let workspace = workspaceClass?.value(forKeyPath: "mainWorkspace") as? NSObject else {
            return nil
        }
        
        // Get the active space
        guard let activeSpace = workspace.value(forKeyPath: "activeSpace") as? NSObject,
              let spaceNumber = activeSpace.value(forKeyPath: "number") as? Int else {
            return nil
        }
        
        return spaceNumber
    }
} 