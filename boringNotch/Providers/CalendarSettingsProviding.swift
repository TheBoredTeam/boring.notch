//
//  CalendarSettingsProviding.swift
//  boringNotch
//
//  Created by David Ashman on 6/17/25.
//


protocol CalendarSettingsProviding {
    func getCalendarSelected(_ calendar: CalendarModel) -> Bool
    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async
}
