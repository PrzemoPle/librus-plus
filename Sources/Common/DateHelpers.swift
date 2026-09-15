import Foundation

enum LibrusDate {
    /// Poland is the only relevant timezone for a Librus gradebook.
    static let timeZone = TimeZone(identifier: "Europe/Warsaw") ?? .current

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 2 // Monday
        return c
    }()

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoNoTZ: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func fromYMD(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return ymd.date(from: string)
    }

    static func ymdString(_ date: Date) -> String { ymd.string(from: date) }

    /// Handles both "2026-09-01T10:00:00+02:00" and "2026-09-01 10:00:00".
    static func fromISO(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = iso.date(from: string) { return d }
        if let d = isoNoTZ.date(from: string) { return d }
        return fromYMD(String(string.prefix(10)))
    }

    private static let dottedDateTime = formatter("dd.MM.yyyy HH:mm")
    private static let dottedDate = formatter("dd.MM.yyyy")
    private static let isoMinutes = formatter("yyyy-MM-dd HH:mm")

    /// Date from a scraped table cell: finds the first date-like token inside
    /// whatever else the cell holds and accepts the formats Synergia is known to
    /// use — "2026-09-15 07:45:12", "2026-09-15 07:45", "15.09.2026 07:45",
    /// "15.09.2026" — plus ISO 8601. nil when no date is recognisable.
    static func fromScrapedCell(_ string: String?) -> Date? {
        guard let string else { return nil }
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let iso = HTTP.firstMatch(#"(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?(?:[+-]\d{2}:\d{2}|Z)?)?)"#, in: text) {
            return fromISO(iso) ?? isoMinutes.date(from: iso)
        }
        if let dotted = HTTP.firstMatch(#"(\d{2}\.\d{2}\.\d{4}(?: \d{2}:\d{2})?)"#, in: text) {
            return dottedDateTime.date(from: dotted) ?? dottedDate.date(from: dotted)
        }
        return nil
    }

    /// True when the text carries something `fromScrapedCell` would parse.
    static func looksLikeDate(_ string: String) -> Bool {
        string.range(of: #"\d{4}-\d{2}-\d{2}|\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) != nil
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }

    /// Monday of the week that contains `date`.
    static func weekStart(of date: Date = Date()) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? date
    }

    /// Week to open the timetable on: current week, or next week on the weekend.
    static func defaultTimetableWeekStart() -> Date {
        let weekday = calendar.component(.weekday, from: Date()) // 1 = Sunday, 7 = Saturday
        let start = weekStart()
        return (weekday == 1 || weekday == 7) ? addDays(7, to: start) : start
    }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    static var today: Date { calendar.startOfDay(for: Date()) }

    /// "HH:mm" -> minutes since midnight.
    static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    static var nowMinutesOfDay: Int {
        let c = calendar.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static var nowSecondsOfDay: Int {
        let c = calendar.dateComponents([.hour, .minute, .second], from: Date())
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }
}

extension Date {
    func formattedPL(_ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = LibrusDate.timeZone
        f.dateFormat = format
        return f.string(from: self)
    }

    var dayMonthShort: String { formattedPL("d MMM") }
    var weekdayName: String { formattedPL("EEEE") }
    var dayMonthYear: String { formattedPL("d MMMM yyyy") }
}
