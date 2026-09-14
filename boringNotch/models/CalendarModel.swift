//
//  CalendarModel.swift
//  Calendr
//
//  Created by Paker on 31/12/20.
//  Original source: https://github.com/pakerwreah/Calendr
//

import Cocoa
import Defaults

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)

    func settingSelected(_ calendarIDs: Set<String>, isSelected: Bool, availableIDs: Set<String>) -> Self {
        var identifiers: Set<String>
        switch self {
        case .all:
            if isSelected { return .all }
            identifiers = availableIDs
        case .selected(let selected):
            identifiers = selected
        }
        if isSelected {
            identifiers.formUnion(calendarIDs)
        } else {
            identifiers.subtract(calendarIDs)
        }
        // Empty means empty; the last checkbox is not a secret Select All button.
        if !availableIDs.isEmpty && availableIDs.isSubset(of: identifiers) {
            return .all
        }
        return .selected(identifiers)
    }
}

struct CalendarModel: Equatable {
    let id: String
    let account: String
    let title: String
    let color: NSColor
    let isSubscribed: Bool
    let isReminder: Bool // true if this is a reminder calendar
}
