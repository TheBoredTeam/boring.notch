import Foundation

extension Date {
    static var loftYesterday: Date { Date().loftDayBefore }
    static var loftTomorrow: Date { Date().loftDayAfter }
    
    var loftDayBefore: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: loftNoon)!
    }
    
    var loftDayAfter: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: loftNoon)!
    }
    
    var loftNoon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: self)!
    }
    
    var loftDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd"
        return formatter.string(from: self)
    }
    
    var loftMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: self)
    }
    
    func loftDayOfTheWeek(for dayOfWeek: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let date = Calendar.current.date(bySetting: .weekday, value: dayOfWeek, of: self) ?? self
        return formatter.string(from: date)
    }
}

extension NSSize {
    var loftDescription: String { "\(width.loftInt)×\(height.loftInt)" }
    
    var loftAspectRatio: Double {
        width / height
    }
    
    func loftScaled(by factor: Double) -> CGSize {
        CGSize(width: (width * factor).loftEvenInt, height: (height * factor).loftEvenInt)
    }
}

extension Int {
    var loftString: String {
        String(self)
    }
    
    var loftDouble: Double {
        Double(self)
    }
}

extension Double {
    @inline(__always) @inlinable var loftRoundedInt: Int {
        rounded().loftInt
    }
    
    @inline(__always) @inlinable var loftInt: Int {
        Int(self)
    }
    
    var loftEvenInt: Int {
        let x = loftRoundedInt
        return x + x % 2
    }
}

extension CGFloat {
    @inline(__always) @inlinable var loftRoundedInt: Int {
        rounded().loftInt
    }
    
    @inline(__always) @inlinable var loftInt: Int {
        Int(self)
    }
    
    var loftEvenInt: Int {
        let x = loftRoundedInt
        return x + x % 2
    }
}
