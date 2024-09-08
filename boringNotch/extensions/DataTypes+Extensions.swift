    //
    //  DataTypes+Extensions.swift
    //  boringNotch
    //
    //  Created by Harsh Vardhan  Goswami  on 27/08/24.
    //

import Foundation



extension Date {
    static var yesterday: Date { return Date().dayBefore }
    static var tomorrow:  Date { return Date().dayAfter }
    var dayBefore: Date {
        return Calendar.current.date(byAdding: .day, value: -1, to: noon)!
    }
    var dayAfter: Date {
        return Calendar.current.date(byAdding: .day, value: 1, to: noon)!
    }
    var noon: Date {
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: self)!
    }
    
    var date: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd"
        return dateFormatter.string(from: self)
    }
    
    var month: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM"
        return dateFormatter.string(from: self)
    }
    
    func dayOfTheWeek(dayOfWeek: Int) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE"
        let date = Calendar.current.date(bySetting: .weekday, value: dayOfWeek, of: self) ?? self
        return dateFormatter.string(from: date)
    }
}

extension NSSize {
    var s: String { "\(width.i)×\(height.i)" }
    
    var aspectRatio: Double {
        width / height
    }
    func scaled(by factor: Double) -> CGSize {
        CGSize(width: (width * factor).evenInt, height: (height * factor).evenInt)
    }
    
}

extension Int {
    var s: String {
        String(self)
    }
    var d: Double {
        Double(self)
    }
}

extension Double {
    @inline(__always) @inlinable var intround: Int {
        rounded().i
    }
    
    @inline(__always) @inlinable var i: Int {
        Int(self)
    }
    
    var evenInt: Int {
        let x = intround
        return x + x % 2
    }
}

extension CGFloat {
    @inline(__always) @inlinable var intround: Int {
        rounded().i
    }
    
    @inline(__always) @inlinable var i: Int {
        Int(self)
    }
    
    var evenInt: Int {
        let x = intround
        return x + x % 2
    }
}
