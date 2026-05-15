import Foundation
import EventKit

/// Creates a calendar event in the user's default calendar via EventKit.
///
/// Args:
///   title:     String (required) — event title
///   starts:    String (required) — when. Accepts:
///                  ISO8601 ("2026-05-16T19:00:00")
///                  "today 7pm" / "tomorrow 9am" / "today 19:30"
///                  "in 30 minutes" / "in 2 hours"
///   duration:  Int (optional) — minutes; defaults to 60
///   notes:     String (optional)
///   location:  String (optional)
///
/// Permission: .destructive — adds something to the user's calendar.
///   PermissionGate will prompt-confirm before the actual write goes through
///   if a confirm handler is wired.
///
/// EventKit access is requested on first use. On macOS 14+ this calls
/// `requestFullAccessToEvents`; older systems fall back to
/// `requestAccess(to:)`.
struct CalendarEventTool: Tool {
    let name = "calendar_event"
    let description = "Creates a calendar event"
    let permissionTier: PermissionTier = .destructive
    let supportedTiers: [ExecutionTier] = [.native]

    func execute(tier: ExecutionTier, args: [String: Any]) async throws -> ToolResult {
        let title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let starts = (args["starts"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = (args["duration"] as? Int) ?? 60
        let notes = args["notes"] as? String
        let location = args["location"] as? String

        guard !title.isEmpty else {
            return ToolResult(success: false, output: "Missing 'title'", tierUsed: .native)
        }
        guard !starts.isEmpty else {
            return ToolResult(success: false, output: "Missing 'starts'", tierUsed: .native)
        }
        guard let startDate = Self.parseDate(starts) else {
            return ToolResult(success: false, output: "Couldn't parse 'starts' = \"\(starts)\"", tierUsed: .native)
        }

        let store = EKEventStore()
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
        }
        guard granted else {
            return ToolResult(success: false, output: "Calendar access denied. Grant in System Settings → Privacy → Calendars.", tierUsed: .native)
        }

        guard let calendar = store.defaultCalendarForNewEvents else {
            return ToolResult(success: false, output: "No default calendar configured.", tierUsed: .native)
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(duration * 60))
        event.calendar = calendar
        if let notes { event.notes = notes }
        if let location { event.location = location }

        do {
            try store.save(event, span: .thisEvent)
        } catch {
            return ToolResult(success: false, output: "Calendar save failed: \(error.localizedDescription)", tierUsed: .native)
        }

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return ToolResult(
            success: true,
            output: "Created \"\(title)\" at \(df.string(from: startDate)) (\(duration) min)",
            tierUsed: .native
        )
    }

    // MARK: - Date parsing
    //
    // Order: ISO8601 → "today/tomorrow + time" → "in N minutes/hours" →
    // DateFormatter common forms. Returns nil if nothing matches.

    static func parseDate(_ raw: String) -> Date? {
        let input = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. ISO8601
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: input) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: input) { return d }

        // 2. "in N minutes/hours"
        if let r = input.range(of: #"^in\s+(\d+)\s+(minute|minutes|min|mins|hour|hours|hr|hrs)$"#,
                               options: .regularExpression) {
            let scanner = Scanner(string: String(input[r]))
            _ = scanner.scanString("in")
            if let n = scanner.scanInt() {
                let unit = (scanner.scanCharacters(from: .alphanumerics) ?? "").lowercased()
                let seconds = unit.hasPrefix("h") ? n * 3600 : n * 60
                return Date().addingTimeInterval(TimeInterval(seconds))
            }
        }

        // 3. "today HH:MM" / "today 7pm" / "tomorrow 9am" / etc.
        let now = Date()
        let cal = Calendar.current
        var baseDay: Date? = nil
        var rest = input
        if input.hasPrefix("today") {
            baseDay = cal.startOfDay(for: now)
            rest = String(input.dropFirst("today".count)).trimmingCharacters(in: .whitespaces)
        } else if input.hasPrefix("tomorrow") {
            baseDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
            rest = String(input.dropFirst("tomorrow".count)).trimmingCharacters(in: .whitespaces)
        }
        if let base = baseDay, let (h, m) = Self.parseTime(rest) {
            return cal.date(bySettingHour: h, minute: m, second: 0, of: base)
        }

        // 4. Common explicit formats
        let formats = [
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy/MM/dd HH:mm",
            "MM/dd HH:mm",
            "MMM d HH:mm",
            "MMM d h:mma",
            "MMM d h a"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        for fmt in formats {
            df.dateFormat = fmt
            if let d = df.date(from: raw) { return d }
        }

        return nil
    }

    /// Parses "7pm", "7:30pm", "19:30", "9am", "noon", "midnight"
    static func parseTime(_ raw: String) -> (Int, Int)? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if s == "noon"     { return (12, 0) }
        if s == "midnight" { return (0, 0) }

        // 24-hour HH:MM
        if let m = s.range(of: #"^(\d{1,2}):(\d{2})$"#, options: .regularExpression) {
            let parts = s[m].split(separator: ":")
            if let h = Int(parts[0]), let mi = Int(parts[1]), h < 24, mi < 60 {
                return (h, mi)
            }
        }

        // 12-hour with am/pm — "7pm", "7:30am", "7 pm"
        if let m = s.range(of: #"^(\d{1,2})(:(\d{2}))?\s*(am|pm)$"#, options: .regularExpression) {
            let match = String(s[m])
            let isPM = match.hasSuffix("pm")
            let body = match.replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "am", with: "")
                .replacingOccurrences(of: "pm", with: "")
            let parts = body.split(separator: ":")
            if let hRaw = parts.first.flatMap({ Int($0) }) {
                var h = hRaw % 12
                if isPM { h += 12 }
                let mi: Int = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                return (h, mi)
            }
        }

        // Bare hour ("19", "7")
        if let h = Int(s), h < 24 {
            return (h, 0)
        }

        return nil
    }
}
